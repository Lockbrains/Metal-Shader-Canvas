//
//  MetalRenderer.swift
//  macOSShaderCanvas
//
//  The core Metal rendering engine. This class owns all GPU resources and
//  implements the multi-pass rendering pipeline.
//
//  DESIGN OVERVIEW:
//  ────────────────
//  MetalRenderer is the "backend" of the app. It receives high-level commands
//  from MetalView (e.g. "shaders changed", "mesh type changed") and translates
//  them into Metal API calls: compiling shader source into GPU pipelines,
//  allocating textures, and encoding multi-pass draw commands every frame.
//
//  ARCHITECTURE:
//  ─────────────
//  The renderer manages four categories of GPU resources:
//
//  1. PIPELINES — Pre-compiled vertex+fragment shader pairs:
//     • meshPipelineState: renders the 3D mesh (vertex + fragment shaders)
//     • fullscreenPipelineStates: one pipeline per post-processing layer
//     • blitPipelineState: copies the final result to the screen drawable
//     • bgBlitPipelineState: draws the background image behind the mesh
//
//  2. TEXTURES — Offscreen render targets for multi-pass rendering:
//     • offscreenTextureA/B: ping-pong buffers for post-processing chain
//     • depthTexture: depth buffer for the mesh pass (z-testing)
//     • backgroundTexture: user-uploaded image, used as scene backdrop
//
//  3. MESH — A 3D model loaded via ModelIO:
//     • Supports sphere, cube, and custom USD/OBJ files
//     • Vertex layout: position(float3) + normal(float3) + texCoord(float2)
//
//  4. UNIFORMS — Per-frame data uploaded to the GPU:
//     • modelViewProjectionMatrix: combined camera transform
//     • time: elapsed seconds, used for animation in shaders
//
//  RENDERING PIPELINE (per frame):
//  ───────────────────────────────
//  ┌──────────────────────────────────────────────────────────┐
//  │ PASS 1: Base Mesh                                        │
//  │   Target: offscreenTextureA                              │
//  │   Steps:                                                 │
//  │     1. Clear to dark gray                                │
//  │     2. Draw background image (if any) as fullscreen quad │
//  │     3. Draw 3D mesh with MVP transform + depth testing   │
//  ├──────────────────────────────────────────────────────────┤
//  │ PASS 2..N: Post-Processing (Ping-Pong)                   │
//  │   For each fullscreen shader layer:                      │
//  │     • Read from currentSourceTex                         │
//  │     • Write to currentDestTex                            │
//  │     • Swap textures after each pass                      │
//  │   This chains effects: bloom → blur → color grading etc  │
//  ├──────────────────────────────────────────────────────────┤
//  │ PASS FINAL: Blit to Screen                               │
//  │   Copy currentSourceTex → view.currentDrawable           │
//  │   Simple texture sampling, no effects applied            │
//  └──────────────────────────────────────────────────────────┘
//
//  RUNTIME SHADER COMPILATION:
//  ───────────────────────────
//  Unlike typical Metal apps that pre-compile shaders into .metallib bundles,
//  this app compiles Metal Shading Language (MSL) source strings at runtime
//  using `device.makeLibrary(source:options:)`. This enables the live-editing
//  workflow: the user types shader code, and it compiles on the next frame.
//
//  SHADER ENTRY POINT CONVENTION:
//  ──────────────────────────────
//  All shaders must define `vertex_main` and `fragment_main` as entry points.
//  Uniforms are always bound at buffer index 1.
//

import MetalKit
import ModelIO
import simd

// MARK: - PP Uniforms (Fullscreen shaders only)

/// Lightweight uniform struct matching the self-contained Uniforms definition
/// inside fullscreen (post-processing) shaders. These shaders define their own
/// smaller Uniforms struct, so we must send data in the expected layout.
private struct PPUniforms {
    var modelViewProjectionMatrix: simd_float4x4
    var time: Float
    var mouseX: Float = 0
    var mouseY: Float = 0
    var _pad: Float = 0
}

// MARK: - MetalRenderer

/// The Metal rendering engine. Manages all GPU resources and executes the
/// multi-pass rendering pipeline every frame.
///
/// Conforms to `MTKViewDelegate` to receive frame callbacks (`draw(in:)`)
/// and resize notifications (`mtkView(_:drawableSizeWillChange:)`).
class MetalRenderer: NSObject, MTKViewDelegate {

    /// Weak shared reference for cross-component access (e.g. AI snapshot capture).
    /// Set automatically on init; only one MetalRenderer exists at a time.
    static weak var current: MetalRenderer?

    // MARK: - Core Metal Objects

    /// The GPU device handle. All Metal resources are created through this object.
    var device: MTLDevice!

    /// Serializes GPU command buffers. One queue per renderer is standard practice.
    var commandQueue: MTLCommandQueue!

    /// Depth testing configuration: less-than comparison with depth writes enabled.
    /// Applied during the mesh rendering pass to handle occlusion correctly.
    var depthStencilState: MTLDepthStencilState!

    // MARK: - Render Pipeline States

    /// Pipeline for the 3D mesh pass (user's vertex + fragment shaders).
    /// Recompiled whenever the vertex or fragment shader code changes.
    var meshPipelineState: MTLRenderPipelineState?

    /// One pipeline per fullscreen (post-processing) shader layer, keyed by shader UUID.
    /// Recompiled whenever any fullscreen shader's code changes.
    var fullscreenPipelineStates: [UUID: MTLRenderPipelineState] = [:]

    /// Pipeline that copies the final composited texture to the screen drawable.
    /// Uses a simple fullscreen triangle + texture sampler. Compiled once at init.
    var blitPipelineState: MTLRenderPipelineState?

    // MARK: - Mesh & Animation

    /// The currently loaded 3D mesh (sphere, cube, or custom model).
    var mesh: MTKMesh?

    /// Elapsed time in seconds, incremented each frame. Passed to shaders as `uniforms.time`.
    var time: Float = 0

    /// Y-axis rotation angle in degrees, controlled by the UI slider.
    var rotationAngle: Float = 0

    /// The current shader layer configuration, mirrored from the SwiftUI state.
    var activeShaders: [ActiveShader] = []
    
    /// The Data Flow configuration that determines which vertex fields are active.
    /// Changes trigger recompilation of all mesh shaders (VS + FS).
    var dataFlowConfig: DataFlowConfig = DataFlowConfig()
    
    /// Current user parameter values (keyed by param name).
    /// Updated every frame from ContentView via MetalView.
    var paramValues: [String: [Float]] = [:]
    
    /// Parsed params from the last mesh shader compilation (for buffer packing).
    private var meshParams: [ShaderParam] = []
    
    /// Parsed params per fullscreen shader (for buffer packing).
    private var fullscreenParams: [UUID: [ShaderParam]] = [:]

    // MARK: - Mouse & Canvas Mode

    /// Normalised mouse position [0,1] read from TrackingMTKView each frame.
    var mousePosition: simd_float2 = .zero

    /// 2D vs 3D canvas mode. Set from MetalView on every SwiftUI update.
    var canvasMode: CanvasMode = .threeDimensional

    /// Kept for backward-compat with single-shape documents (unused by new scene path).
    var shape2DType: Shape2DType = .roundedRectangle

    // MARK: - 2D Scene State

    /// All objects in the 2D scene. Set from MetalView on SwiftUI updates.
    var objects2D: [Object2D] = []
    /// Scene-wide shared vertex (distortion) shader code.
    var sharedVertexCode2D: String = ShaderSnippets.distortion2DTemplate
    /// Scene-wide shared fragment (color) shader code.
    var sharedFragmentCode2D: String = ShaderSnippets.fragment2DDemo
    /// 2D Data Flow configuration controlling which fields appear in VertexOut.
    var dataFlow2DConfig: DataFlow2DConfig = DataFlow2DConfig()
    /// Canvas camera zoom level.
    var canvasZoom: Float = 1.0
    /// Canvas camera pan offset (NDC).
    var canvasPan: simd_float2 = .zero

    /// Per-object compiled pipeline (VS distort + FS color + SDF mask, single pass).
    var object2DPipelineStates: [UUID: MTLRenderPipelineState] = [:]

    /// Pipeline for the 2D grid background (compiled once).
    var gridPipelineState: MTLRenderPipelineState?

    /// Background-image blit for 2D mode (no depth attachment).
    var bg2DBlitPipelineState: MTLRenderPipelineState?

    // MARK: - Offscreen Textures (Ping-Pong)

    /// Primary offscreen render target. The mesh is initially rendered here.
    /// Also serves as one side of the ping-pong buffer for post-processing.
    var offscreenTextureA: MTLTexture?

    /// Secondary ping-pong buffer. Post-processing alternates between A and B.
    var offscreenTextureB: MTLTexture?

    /// Depth buffer for the mesh rendering pass. Format: .depth32Float.
    var depthTexture: MTLTexture?

    // MARK: - Background Image

    /// GPU texture created from the user's background image.
    /// Drawn as a fullscreen quad behind the 3D mesh.
    var backgroundTexture: MTLTexture?

    /// Pipeline for rendering the background image into the offscreen texture.
    /// Uses the same blit shader but targets .bgra8Unorm + .depth32Float (mesh pass format).
    var bgBlitPipelineState: MTLRenderPipelineState?

    // MARK: - Mesh Type (with automatic rebuild)

    /// The current mesh type. Setting this property triggers mesh reconstruction
    /// and pipeline recompilation via the `didSet` observer, but ONLY when the
    /// value actually changes — avoiding unnecessary GPU work.
    var currentMeshType: MeshType = .sphere {
        didSet {
            if currentMeshType != oldValue {
                setupMesh(type: currentMeshType)
                compileMeshPipeline()
            }
        }
    }

    // MARK: - Initialization

    /// Initializes the renderer with a pre-configured MTKView.
    ///
    /// Setup sequence:
    /// 1. Capture the Metal device from the MTKView
    /// 2. Create the command queue
    /// 3. Configure depth stencil state
    /// 4. Build the default mesh (sphere)
    /// 5. Compile all initial pipelines
    ///
    /// Returns nil if any critical Metal resource cannot be created.
    ///
    /// - Parameter metalView: An MTKView with its `device` property already set.
    init?(metalView: MTKView) {
        guard let device = metalView.device else { return nil }
        self.device = device
        super.init()

        // Register as the MTKView's delegate to receive draw callbacks.
        metalView.delegate = self

        // The view's clear color is only visible if no content is drawn.
        // In practice, our blit pass always covers the entire drawable.
        metalView.clearColor = MTLClearColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)

        // The view's own framebuffer does NOT need depth — depth testing happens
        // in the offscreen mesh pass. Setting .invalid saves memory.
        metalView.depthStencilPixelFormat = .invalid
        metalView.framebufferOnly = true

        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        // Configure depth testing: fragments closer to the camera pass; farther ones are discarded.
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        self.depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)

        // Build the default mesh and compile all initial pipelines.
        setupMesh(type: currentMeshType)
        compileMeshPipeline()
        compileBlitPipeline(metalView: metalView)
        compileBgBlitPipeline()
        compileGridPipeline()

        MetalRenderer.current = self
    }

    // MARK: - Mesh Setup

    /// Loads or generates a 3D mesh based on the given type.
    ///
    /// Uses Apple's ModelIO framework to create parametric meshes (sphere, cube)
    /// or load external 3D files (USDZ, OBJ). The vertex layout is:
    ///
    /// | Attribute | Format   | Buffer Index | Offset |
    /// |-----------|----------|--------------|--------|
    /// | position  | float3   | 0            | 0      |
    /// | normal    | float3   | 0            | 12     |
    /// | texCoord  | float2   | 0            | 24     |
    /// | (stride)  |          |              | 32     |
    ///
    /// - Parameter type: The mesh to create (.sphere, .cube, or .custom(URL)).
    func setupMesh(type: MeshType) {
        let allocator = MTKMeshBufferAllocator(device: device)
        var mdlMesh: MDLMesh?

        // Define a consistent vertex layout used by all meshes.
        // This layout must match the VertexIn struct in the user's vertex shader.
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<Float>.stride * 3, bufferIndex: 0)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: MemoryLayout<Float>.stride * 6, bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.stride * 8)

        switch type {
        case .sphere:
            mdlMesh = MDLMesh(sphereWithExtent: [2, 2, 2], segments: [60, 60], inwardNormals: false, geometryType: .triangles, allocator: allocator)
        case .cube:
            mdlMesh = MDLMesh(boxWithExtent: [2, 2, 2], segments: [1, 1, 1], inwardNormals: false, geometryType: .triangles, allocator: allocator)
        case .custom(let url):
            // Load external 3D model. Falls back to sphere if loading fails.
            let asset = MDLAsset(url: url, vertexDescriptor: vertexDescriptor, bufferAllocator: allocator)
            if let firstMesh = asset.childObjects(of: MDLMesh.self).first as? MDLMesh {
                mdlMesh = firstMesh
            } else {
                mdlMesh = MDLMesh(sphereWithExtent: [2, 2, 2], segments: [60, 60], inwardNormals: false, geometryType: .triangles, allocator: allocator)
            }
        }

        if let mdlMesh = mdlMesh {
            mdlMesh.vertexDescriptor = vertexDescriptor
            do {
                self.mesh = try MTKMesh(mesh: mdlMesh, device: device)
            } catch {
                print("Error creating MTKMesh: \(error)")
            }
        }
    }

    // MARK: - Alpha Blending Configuration

    /// Configures standard alpha blending ("over" composite) on a pipeline
    /// color attachment. This enables fragment shaders to output alpha < 1.0
    /// for transparency effects.
    ///
    /// Result formula:
    ///   RGB   = src.rgb × src.a + dst.rgb × (1 − src.a)
    ///   Alpha = src.a × 1       + dst.a   × (1 − src.a)
    private static func configureAlphaBlending(on attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    // MARK: - Shader Update & Compilation

    /// Called by MetalView.updateNSView() whenever the SwiftUI shader state changes.
    ///
    /// Performs a diff between the old and new shader arrays to determine which
    /// pipelines need recompilation. This avoids recompiling unchanged shaders,
    /// which would cause frame drops during rapid UI updates.
    ///
    /// Diffing strategy:
    /// - Vertex/Fragment: compare the `.code` strings of all vertex/fragment shaders
    /// - Fullscreen: compare both `.id` and `.code` (because layer order matters)
    ///
    /// - Parameters:
    ///   - shaders: The new shader array from SwiftUI state.
    ///   - view: The MTKView, needed for pixel format info during compilation.
    func updateShaders(_ shaders: [ActiveShader], dataFlow: DataFlowConfig, in view: MTKView) {
        let oldShaders = self.activeShaders
        let oldDataFlow = self.dataFlowConfig
        self.activeShaders = shaders
        self.dataFlowConfig = dataFlow

        let dataFlowChanged = dataFlow != oldDataFlow
        let vertexChanged = shaders.filter({ $0.category == .vertex }).map(\.code) != oldShaders.filter({ $0.category == .vertex }).map(\.code)
        let fragmentChanged = shaders.filter({ $0.category == .fragment }).map(\.code) != oldShaders.filter({ $0.category == .fragment }).map(\.code)
        let fullscreenChanged = shaders.filter({ $0.category == .fullscreen }).map({ "\($0.id)\($0.code)" }) != oldShaders.filter({ $0.category == .fullscreen }).map({ "\($0.id)\($0.code)" })

        if canvasMode.is2D {
            if fragmentChanged || dataFlowChanged {
                compileObject2DPipelines()
            }
        } else {
            if vertexChanged || fragmentChanged || dataFlowChanged {
                compileMeshPipeline()
            }
        }
        if fullscreenChanged {
            compileFullscreenPipelines(metalView: view)
        }
    }

    /// Compiles the mesh rendering pipeline using the Data Flow shared header.
    ///
    /// Compilation flow:
    /// 1. Generate the shared MSL header from dataFlowConfig
    /// 2. For vertex: use user code (stripped of struct defs) or auto-generated default
    /// 3. For fragment: use user code (stripped of struct defs) or built-in default
    /// 4. Prepend header to both, compile, and create the pipeline
    func compileMeshPipeline() {
        let vertexShaders = activeShaders.filter { $0.category == .vertex }
        let fragmentShaders = activeShaders.filter { $0.category == .fragment }
        
        let vRawBody: String
        if let userVS = vertexShaders.last?.code {
            vRawBody = ShaderSnippets.stripStructDefinitions(from: userVS)
        } else {
            vRawBody = ShaderSnippets.generateDefaultVertexShader(config: dataFlowConfig)
        }
        
        let fRawBody: String
        if let userFS = fragmentShaders.last?.code {
            fRawBody = ShaderSnippets.stripStructDefinitions(from: userFS)
        } else {
            fRawBody = ShaderSnippets.defaultFragment
        }
        
        // Parse @param directives from all mesh shader sources
        var allParams: [ShaderParam] = []
        var seenNames = Set<String>()
        for shader in vertexShaders + fragmentShaders {
            for param in ShaderSnippets.parseParams(from: shader.code) {
                if seenNames.insert(param.name).inserted { allParams.append(param) }
            }
        }
        meshParams = allParams
        
        let header = ShaderSnippets.generateSharedHeader(config: dataFlowConfig)
        let paramHeader = ShaderSnippets.generateParamHeader(params: allParams)
        
        let vBody = ShaderSnippets.injectParamsBuffer(into: vRawBody, paramCount: allParams.count)
        let fBody = ShaderSnippets.injectParamsBuffer(into: fRawBody, paramCount: allParams.count)
        
        let vSource = header + paramHeader + vBody
        let fSource = header + paramHeader + fBody

        do {
            let vLib = try device.makeLibrary(source: vSource, options: nil)
            let fLib = try device.makeLibrary(source: fSource, options: nil)

            guard let vertexFunc = vLib.makeFunction(name: "vertex_main"),
                  let fragFunc = fLib.makeFunction(name: "fragment_main") else {
                print("Missing vertex_main or fragment_main in mesh shaders")
                return
            }

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            Self.configureAlphaBlending(on: pipelineDescriptor.colorAttachments[0])
            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

            if let mesh = self.mesh {
                pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
            }

            self.meshPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            NotificationCenter.default.post(name: .shaderCompilationResult, object: nil)
        } catch {
            let msg = Self.extractMSLErrors(from: "\(error)")
            NotificationCenter.default.post(name: .shaderCompilationResult, object: msg)
        }
    }
    
    /// Extracts concise MSL error lines from a Metal compilation error string.
    private static func extractMSLErrors(from fullError: String) -> String {
        fullError.components(separatedBy: "\n")
            .filter { $0.contains("error:") }
            .map { line in
                if let range = line.range(of: #"program_source:\d+:\d+: error: .+"#, options: .regularExpression) {
                    return String(line[range])
                }
                return line
            }
            .joined(separator: "\n")
    }

    /// Compiles one pipeline per fullscreen (post-processing) shader layer.
    ///
    /// Each fullscreen shader is a self-contained MSL program with both
    /// `vertex_main` (generates a fullscreen triangle) and `fragment_main`
    /// (applies the post-processing effect by sampling the previous pass texture).
    ///
    /// Pipelines are stored in a dictionary keyed by the shader's UUID,
    /// so they can be looked up during the draw loop.
    ///
    /// - Parameter metalView: The MTKView, needed for pixel format information.
    func compileFullscreenPipelines(metalView: MTKView) {
        var newStates: [UUID: MTLRenderPipelineState] = [:]
        var newParams: [UUID: [ShaderParam]] = [:]
        let fullscreenShaders = activeShaders.filter { $0.category == .fullscreen }

        var hasError = false
        for shader in fullscreenShaders {
            let params = ShaderSnippets.parseParams(from: shader.code)
            newParams[shader.id] = params
            
            var source = shader.code
            if !params.isEmpty {
                let paramHeader = ShaderSnippets.generateParamHeader(params: params)
                let insertionPoint = source.range(of: "using namespace metal;")?.upperBound
                    ?? source.range(of: "#include <metal_stdlib>")?.upperBound
                    ?? source.startIndex
                source.insert(contentsOf: paramHeader, at: insertionPoint)
                source = ShaderSnippets.injectParamsBuffer(into: source, paramCount: params.count)
            }
            
            do {
                let lib = try device.makeLibrary(source: source, options: nil)
                guard let vertexFunc = lib.makeFunction(name: "vertex_main"),
                      let fragFunc = lib.makeFunction(name: "fragment_main") else {
                    print("Missing vertex_main or fragment_main in \(shader.name)")
                    continue
                }
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = vertexFunc
                descriptor.fragmentFunction = fragFunc
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

                let state = try device.makeRenderPipelineState(descriptor: descriptor)
                newStates[shader.id] = state
            } catch {
                hasError = true
                let msg = Self.extractMSLErrors(from: "\(error)")
                NotificationCenter.default.post(name: .shaderCompilationResult, object: "[\(shader.name)] \(msg)")
            }
        }
        if !hasError {
            NotificationCenter.default.post(name: .shaderCompilationResult, object: nil)
        }
        fullscreenPipelineStates = newStates
        fullscreenParams = newParams
    }

    /// Compiles the final blit pipeline that copies the composited result to the screen.
    ///
    /// This pipeline uses the view's native color pixel format (typically .bgra8Unorm_srgb)
    /// and does NOT use depth. It draws a fullscreen triangle that samples the
    /// post-processing output texture.
    ///
    /// - Parameter metalView: The MTKView, needed for its colorPixelFormat.
    func compileBlitPipeline(metalView: MTKView) {
        do {
            let lib = try device.makeLibrary(source: ShaderSnippets.blitShader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = lib.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = lib.makeFunction(name: "fragment_main")
            descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
            self.blitPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Failed to compile blit pipeline: \(error)")
        }
    }

    /// Compiles the background image blit pipeline.
    ///
    /// Similar to the final blit, but targets the offscreen texture format (.bgra8Unorm)
    /// and includes a depth attachment (.depth32Float) because it renders into the
    /// same render pass as the mesh. The background is drawn first (before the mesh)
    /// so the mesh correctly occludes it via depth testing.
    func compileBgBlitPipeline() {
        do {
            let lib = try device.makeLibrary(source: ShaderSnippets.blitShader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = lib.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = lib.makeFunction(name: "fragment_main")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            Self.configureAlphaBlending(on: descriptor.colorAttachments[0])
            descriptor.depthAttachmentPixelFormat = .depth32Float
            self.bgBlitPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Failed to compile bg blit pipeline: \(error)")
        }
    }

    // MARK: - 2D Pipeline Compilation

    /// Compiles the grid background pipeline (2D mode). Called once during init.
    func compileGridPipeline() {
        do {
            let lib = try device.makeLibrary(source: ShaderSnippets.gridShader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = lib.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = lib.makeFunction(name: "fragment_main")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            self.gridPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Failed to compile grid pipeline: \(error)")
        }

        do {
            let lib = try device.makeLibrary(source: ShaderSnippets.blitShader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = lib.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = lib.makeFunction(name: "fragment_main")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            Self.configureAlphaBlending(on: descriptor.colorAttachments[0])
            self.bg2DBlitPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Failed to compile 2D bg blit pipeline: \(error)")
        }
    }

    /// Compiles one pipeline per Object2D.
    /// Each pipeline merges: user distort_main → system vertex_main wrapper →
    /// user fragment_main (renamed) → SDF mask wrapper.  Single-pass alpha-blend.
    func compileObject2DPipelines() {
        var newStates: [UUID: MTLRenderPipelineState] = [:]
        var hasError = false

        for object in objects2D {
            let vsUserCode = object.customVertexCode ?? sharedVertexCode2D
            let fsUserCode = object.customFragmentCode ?? sharedFragmentCode2D
            let shape = object.shapeType

            let header = ShaderSnippets.generateSharedHeader2D(config: dataFlow2DConfig)

            // Merge params from both VS and FS to support @param in distortion shaders
            var allParams: [ShaderParam] = []
            var seenNames = Set<String>()
            for code in [vsUserCode, fsUserCode] {
                for param in ShaderSnippets.parseParams(from: code) {
                    if seenNames.insert(param.name).inserted { allParams.append(param) }
                }
            }
            let paramHeader = ShaderSnippets.generateParamHeader(params: allParams)
            let totalParamCount = allParams.count

            // VS: header + params + user distort_main + system vertex_main wrapper
            let vsStripped = ShaderSnippets.stripStructDefinitions(from: vsUserCode)
            let vsInjected = ShaderSnippets.inject2DVertexParamsBuffer(into: vsStripped, paramCount: totalParamCount)
            let vsWrapper = ShaderSnippets.generate2DVertexWrapper(shape: shape, config: dataFlow2DConfig, hasParams: totalParamCount > 0)
            let vsSource = header + paramHeader + vsInjected + vsWrapper

            // FS: header + params + SDF-wrapped user fragment
            // NOTE: Do NOT call injectParamsBuffer here — wrapFragmentWithSDF
            // handles params injection itself to guarantee correct argument order
            // when both bgTexture and params are present.
            let fsStripped = ShaderSnippets.stripStructDefinitions(from: fsUserCode)
            let fsWrapped = ShaderSnippets.wrapFragmentWithSDF(userCode: fsStripped, shape: shape, hasParams: totalParamCount > 0)
            let fsSource = header + paramHeader + fsWrapped

            do {
                let vLib = try device.makeLibrary(source: vsSource, options: nil)
                let fLib = try device.makeLibrary(source: fsSource, options: nil)
                guard let vFunc = vLib.makeFunction(name: "vertex_main"),
                      let fFunc = fLib.makeFunction(name: "fragment_main") else {
                    print("Missing entry point for 2D object \(object.name)")
                    continue
                }
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = vFunc
                desc.fragmentFunction = fFunc
                desc.colorAttachments[0].pixelFormat = .bgra8Unorm
                Self.configureAlphaBlending(on: desc.colorAttachments[0])
                newStates[object.id] = try device.makeRenderPipelineState(descriptor: desc)
            } catch {
                hasError = true
                let msg = Self.extractMSLErrors(from: "\(error)")
                NotificationCenter.default.post(name: .shaderCompilationResult, object: "[\(object.name)] \(msg)")
            }
        }

        if !hasError {
            NotificationCenter.default.post(name: .shaderCompilationResult, object: nil)
        }
        object2DPipelineStates = newStates
    }

    // MARK: - Background Image Loading

    /// Converts an NSImage into a Metal texture for GPU rendering.
    ///
    /// Uses MTKTextureLoader for the conversion. The resulting texture is stored
    /// in GPU-private memory (.private storage mode) for optimal rendering performance.
    /// SRGB is disabled to preserve the linear color values.
    ///
    /// - Parameter nsImage: The image to upload, or nil to clear the background.
    func loadBackgroundImage(_ nsImage: NSImage?) {
        guard let nsImage = nsImage,
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            backgroundTexture = nil
            return
        }
        let loader = MTKTextureLoader(device: device)
        do {
            backgroundTexture = try loader.newTexture(cgImage: cgImage, options: [
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue,
                .SRGB: false
            ])
        } catch {
            print("Failed to load background texture: \(error)")
            backgroundTexture = nil
        }
    }

    // MARK: - MTKViewDelegate

    /// Called when the view's drawable size changes (window resize, display change).
    /// Recreates all offscreen textures to match the new viewport dimensions.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setupOffscreenTextures(size: size)
    }

    // MARK: - Offscreen Texture Management

    /// Creates or recreates the offscreen render targets to match the given size.
    ///
    /// Three textures are allocated:
    /// - offscreenTextureA: primary render target + ping-pong buffer A
    /// - offscreenTextureB: ping-pong buffer B
    /// - depthTexture: depth buffer for the mesh pass
    ///
    /// All textures use .private storage mode (GPU-only, fastest for rendering).
    /// Color textures need both .renderTarget and .shaderRead usage because they
    /// are written to in one pass and sampled from in the next.
    ///
    /// - Parameter size: The viewport size in pixels (drawableSize, not points).
    func setupOffscreenTextures(size: CGSize) {
        if size.width <= 0 || size.height <= 0 { return }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        offscreenTextureA = device.makeTexture(descriptor: descriptor)
        offscreenTextureB = device.makeTexture(descriptor: descriptor)

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: Int(size.width), height: Int(size.height), mipmapped: false)
        depthDesc.usage = .renderTarget
        depthDesc.storageMode = .private
        depthTexture = device.makeTexture(descriptor: depthDesc)
    }

    // MARK: - Frame Rendering

    /// Called every frame by MTKView. Encodes the full multi-pass rendering pipeline.
    ///
    /// This is the main rendering function and the heart of the Metal backend.
    /// It creates one MTLCommandBuffer per frame and encodes three stages:
    ///
    /// **PASS 1 — Base Mesh Rendering → offscreenTextureA**
    /// - Clears the target to dark gray
    /// - Draws the background image (if any) as a fullscreen quad
    /// - Draws the 3D mesh with the user's vertex/fragment shaders
    /// - Uses depth testing to handle mesh self-occlusion
    /// - Binds Uniforms (MVP matrix + time) at buffer index 1
    ///
    /// **PASS 2..N — Post-Processing (Ping-Pong between A and B)**
    /// - For each fullscreen shader layer (in order):
    ///   - Reads from currentSourceTex (the previous pass output)
    ///   - Writes to currentDestTex
    ///   - Swaps source/dest after each pass
    /// - This chains effects sequentially: bloom → blur → color grade, etc.
    ///
    /// **PASS FINAL — Blit to Screen Drawable**
    /// - Copies the final composited texture to the MTKView's drawable
    /// - Uses the blit pipeline (simple texture sampling)
    ///
    /// - Parameter view: The MTKView requesting a new frame.
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // Read normalised mouse position from the tracking view.
        if let trackingView = view as? TrackingMTKView {
            mousePosition = trackingView.normalizedMousePosition
        }

        // Ensure offscreen textures match the current drawable size.
        let size = view.drawableSize
        if offscreenTextureA == nil || offscreenTextureA!.width != Int(size.width) || offscreenTextureA!.height != Int(size.height) {
            setupOffscreenTextures(size: size)
        }

        guard let texA = offscreenTextureA, let texB = offscreenTextureB, let depthTex = depthTexture else { return }

        // Advance the animation clock (~60fps assumed).
        time += 1.0 / 60.0

        // Tracks which texture holds the base pass result (before PP chain).
        var baseResultTex = texA
        var basePPDest = texB

        if canvasMode.is2D {
            // ─── 2D PASS 1: Grid/Background → Texture A (fullscreen) ────

            let basePassDesc = MTLRenderPassDescriptor()
            basePassDesc.colorAttachments[0].texture = texA
            basePassDesc.colorAttachments[0].loadAction = .clear
            basePassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.118, green: 0.118, blue: 0.137, alpha: 1.0)
            basePassDesc.colorAttachments[0].storeAction = .store

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: basePassDesc) {
                var uniforms2D = Uniforms2D(
                    resolution: simd_float2(Float(size.width), Float(size.height)),
                    time: time,
                    mouseX: mousePosition.x,
                    mouseY: mousePosition.y
                )
                var gridTransform = Transform2D(canvasPan: canvasPan, canvasZoom: canvasZoom)

                if let bgTex = backgroundTexture, let bgPipeline = bg2DBlitPipelineState {
                    encoder.setRenderPipelineState(bgPipeline)
                    encoder.setFragmentTexture(bgTex, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                } else if let gridPipeline = gridPipelineState {
                    encoder.setRenderPipelineState(gridPipeline)
                    encoder.setFragmentBytes(&uniforms2D, length: MemoryLayout<Uniforms2D>.stride, index: 1)
                    encoder.setVertexBytes(&gridTransform, length: MemoryLayout<Transform2D>.stride, index: 3)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                }
                encoder.endEncoding()
            }

            // ─── 2D PASS 2: Per-Object single-pass (VS+FS+SDF) → texA ──
            // Before each object, snapshot texA → texB so the fragment shader
            // can sample the background (grid + previous objects) via bgTexture.

            for object in objects2D {
                guard let pipeline = object2DPipelineStates[object.id] else { continue }

                // Snapshot current canvas state into texB for background sampling.
                if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                    blitEncoder.copy(from: texA, to: texB)
                    blitEncoder.endEncoding()
                }

                let passDesc = MTLRenderPassDescriptor()
                passDesc.colorAttachments[0].texture = texA
                passDesc.colorAttachments[0].loadAction = .load
                passDesc.colorAttachments[0].storeAction = .store

                if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) {
                    encoder.setRenderPipelineState(pipeline)

                    var uniforms2D = Uniforms2D(
                        resolution: simd_float2(Float(size.width), Float(size.height)),
                        time: time,
                        mouseX: mousePosition.x,
                        mouseY: mousePosition.y
                    )
                    encoder.setVertexBytes(&uniforms2D, length: MemoryLayout<Uniforms2D>.stride, index: 1)
                    encoder.setFragmentBytes(&uniforms2D, length: MemoryLayout<Uniforms2D>.stride, index: 1)

                    // Bind background snapshot for optional sampling in fragment shader.
                    encoder.setFragmentTexture(texB, index: 0)

                    var transform = Transform2D(
                        objectOffset: simd_float2(object.posX, object.posY),
                        objectScale: simd_float2(object.scaleW, object.scaleH),
                        canvasPan: canvasPan,
                        canvasZoom: canvasZoom,
                        objectRotation: object.rotation,
                        cornerRadius: object.cornerRadius
                    )
                    encoder.setVertexBytes(&transform, length: MemoryLayout<Transform2D>.stride, index: 3)

                    let vsCode = object.customVertexCode ?? sharedVertexCode2D
                    let fsCode = object.customFragmentCode ?? sharedFragmentCode2D
                    var drawParams: [ShaderParam] = []
                    var drawSeen = Set<String>()
                    for code in [vsCode, fsCode] {
                        for p in ShaderSnippets.parseParams(from: code) {
                            if drawSeen.insert(p.name).inserted { drawParams.append(p) }
                        }
                    }
                    if !drawParams.isEmpty {
                        var paramBuffer = ShaderSnippets.packParamBuffer(params: drawParams, values: paramValues)
                        let bufLen = paramBuffer.count * MemoryLayout<Float>.stride
                        encoder.setVertexBytes(&paramBuffer, length: bufLen, index: 2)
                        encoder.setFragmentBytes(&paramBuffer, length: bufLen, index: 2)
                    }

                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                    encoder.endEncoding()
                }
            }

            baseResultTex = texA
            basePPDest = texB

        } else {
            // ─── 3D PASS 1: Base Mesh Rendering → Texture A ─────────────

            let meshPassDesc = MTLRenderPassDescriptor()
            meshPassDesc.colorAttachments[0].texture = texA
            meshPassDesc.colorAttachments[0].loadAction = .clear
            meshPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
            meshPassDesc.colorAttachments[0].storeAction = .store

            meshPassDesc.depthAttachment.texture = depthTex
            meshPassDesc.depthAttachment.loadAction = .clear
            meshPassDesc.depthAttachment.storeAction = .dontCare
            meshPassDesc.depthAttachment.clearDepth = 1.0

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: meshPassDesc) {
                if let bgTex = backgroundTexture, let bgPipeline = bgBlitPipelineState {
                    encoder.setRenderPipelineState(bgPipeline)
                    encoder.setFragmentTexture(bgTex, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                }

                if let pipeline = meshPipelineState, let mesh = mesh {
                    encoder.setRenderPipelineState(pipeline)
                    encoder.setDepthStencilState(depthStencilState)

                    let aspect = Float(size.width / size.height)
                    let projectionMatrix = matrix_perspective_right_hand(fovyRadians: Float.pi / 3.0, aspectRatio: aspect, nearZ: 0.1, farZ: 100.0)
                    let viewMatrix = matrix_translation(0, 0, -8.0)
                let modelMatrix = matrix_rotation(rotationAngle * Float.pi / 180.0, axis: simd_float3(0, 1, 0))
                    let mvp = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))

                    let normalMatrix = simd_transpose(simd_inverse(modelMatrix))
                    let cameraPosition = simd_float4(0, 0, 8, 0)

                    var uniforms = Uniforms(
                        mvpMatrix: mvp,
                        modelMatrix: modelMatrix,
                        normalMatrix: normalMatrix,
                        cameraPosition: cameraPosition,
                        time: time,
                        mouseX: mousePosition.x,
                        mouseY: mousePosition.y
                    )
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

                    var paramBuffer = ShaderSnippets.packParamBuffer(params: meshParams, values: paramValues)
                    if !paramBuffer.isEmpty {
                        encoder.setVertexBytes(&paramBuffer, length: paramBuffer.count * MemoryLayout<Float>.stride, index: 2)
                        encoder.setFragmentBytes(&paramBuffer, length: paramBuffer.count * MemoryLayout<Float>.stride, index: 2)
                    }

                    for (index, vertexBuffer) in mesh.vertexBuffers.enumerated() {
                        encoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: index)
                    }

                    encoder.setCullMode(.front)
                    for submesh in mesh.submeshes {
                        encoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset)
                    }

                    encoder.setCullMode(.back)
                    for submesh in mesh.submeshes {
                        encoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset)
                    }
                }
                encoder.endEncoding()
            }
        }

        // ─── PASS 2..N: Fullscreen Post-Processing (Ping-Pong) ──────────

        // Ping-pong: alternate between two textures. The base pass result may
        // be in texA (3D) or texB (2D, odd number of fragment layers).
        var currentSourceTex = baseResultTex
        var currentDestTex = basePPDest

        let fullscreenShaders = activeShaders.filter { $0.category == .fullscreen }

        for shader in fullscreenShaders {
            guard let pipeline = fullscreenPipelineStates[shader.id] else { continue }

            let fsPassDesc = MTLRenderPassDescriptor()
            fsPassDesc.colorAttachments[0].texture = currentDestTex
            fsPassDesc.colorAttachments[0].loadAction = .dontCare
            fsPassDesc.colorAttachments[0].storeAction = .store

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: fsPassDesc) {
                encoder.setRenderPipelineState(pipeline)

                // Bind the previous pass output as a texture for the fragment shader.
                encoder.setFragmentTexture(currentSourceTex, index: 0)

                var ppUniforms = PPUniforms(modelViewProjectionMatrix: matrix_identity_float4x4, time: time, mouseX: mousePosition.x, mouseY: mousePosition.y)
                encoder.setVertexBytes(&ppUniforms, length: MemoryLayout<PPUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&ppUniforms, length: MemoryLayout<PPUniforms>.stride, index: 1)
                
                if let shaderParams = fullscreenParams[shader.id], !shaderParams.isEmpty {
                    var ppParamBuffer = ShaderSnippets.packParamBuffer(params: shaderParams, values: paramValues)
                    encoder.setFragmentBytes(&ppParamBuffer, length: ppParamBuffer.count * MemoryLayout<Float>.stride, index: 2)
                }

                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            }

            // Swap ping-pong textures for the next pass.
            let temp = currentSourceTex
            currentSourceTex = currentDestTex
            currentDestTex = temp
        }

        // ─── PASS FINAL: Blit Output to Screen Drawable ─────────────────

        if let finalPassDesc = view.currentRenderPassDescriptor,
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: finalPassDesc) {

            if let blitPipeline = blitPipelineState {
                encoder.setRenderPipelineState(blitPipeline)
                // currentSourceTex holds the final composited image.
                encoder.setFragmentTexture(currentSourceTex, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            encoder.endEncoding()
        }

        // Present the drawable and submit the command buffer to the GPU.
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Matrix Math Helpers

    /// Creates a right-handed perspective projection matrix.
    ///
    /// Maps the view frustum to normalized device coordinates (NDC).
    /// Metal uses a clip space Z range of [0, 1] (not [-1, 1] like OpenGL).
    ///
    /// - Parameters:
    ///   - fovy: Vertical field of view in radians.
    ///   - aspectRatio: Width / height of the viewport.
    ///   - nearZ: Distance to the near clipping plane.
    ///   - farZ: Distance to the far clipping plane.
    /// - Returns: A 4x4 perspective projection matrix.
    func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let ys = 1 / tanf(fovy * 0.5)
        let xs = ys / aspectRatio
        let zs = farZ / (nearZ - farZ)
        return simd_float4x4(columns:(
            simd_float4(xs,  0, 0,   0),
            simd_float4( 0, ys, 0,   0),
            simd_float4( 0,  0, zs, -1),
            simd_float4( 0,  0, nearZ * zs, 0)
        ))
    }

    /// Creates a translation matrix that moves geometry by (x, y, z).
    func matrix_translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        return simd_float4x4(columns:(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(x, y, z, 1)
        ))
    }

    /// Creates a rotation matrix around an arbitrary axis using Rodrigues' formula.
    ///
    /// - Parameters:
    ///   - radians: The rotation angle in radians.
    ///   - axis: The axis of rotation (will be normalized internally).
    /// - Returns: A 4x4 rotation matrix.
    func matrix_rotation(_ radians: Float, axis: simd_float3) -> simd_float4x4 {
        let a = normalize(axis)
        let c = cos(radians)
        let s = sin(radians)
        let mc = 1 - c
        let x = a.x, y = a.y, z = a.z
        return simd_float4x4(columns:(
            simd_float4(c + x*x*mc,     x*y*mc - z*s,   x*z*mc + y*s, 0),
            simd_float4(x*y*mc + z*s,   c + y*y*mc,     y*z*mc - x*s, 0),
            simd_float4(x*z*mc - y*s,   y*z*mc + x*s,   c + z*z*mc,   0),
            simd_float4(0,              0,              0,            1)
        ))
    }

    // MARK: - Snapshot Capture

    /// Captures a compressed JPEG snapshot for the AI Agent's multimodal context.
    ///
    /// Downscales to at most 512x512 to keep token cost reasonable (~85 tokens for
    /// a low-detail JPEG). Returns base64-encoded JPEG data, or nil on failure.
    func captureForAI(maxDimension: Int = 512) -> Data? {
        guard let nsImage = captureSnapshot() else { return nil }
        let origW = nsImage.size.width
        let origH = nsImage.size.height
        guard origW > 0, origH > 0 else { return nil }

        let scale = min(1.0, min(CGFloat(maxDimension) / origW, CGFloat(maxDimension) / origH))
        let newW = Int(origW * scale)
        let newH = Int(origH * scale)

        let resized = NSImage(size: NSSize(width: newW, height: newH))
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        nsImage.draw(in: NSRect(x: 0, y: 0, width: newW, height: newH))
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        else { return nil }
        return jpeg
    }

    /// Captures the current offscreen texture A as an NSImage (for Hub thumbnails).
    func captureSnapshot() -> NSImage? {
        guard let texture = offscreenTextureA else { return nil }
        let w = texture.width
        let h = texture.height
        guard w > 0, h > 0 else { return nil }

        let bytesPerRow = w * 4
        let region = MTLRegion(origin: .init(x: 0, y: 0, z: 0),
                               size: .init(width: w, height: h, depth: 1))

        // Need a managed/shared copy to read from CPU. Private textures
        // require a blit to a readable texture first.
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.storageMode = .managed
        desc.usage = .shaderRead
        guard let readable = device.makeTexture(descriptor: desc),
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let blit = cmdBuf.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, to: readable)
        blit.synchronize(resource: readable)
        blit.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: bytesPerRow * h)
        readable.getBytes(&bytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(width: w, height: h, bitsPerComponent: 8,
                                    bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false,
                                    intent: .defaultIntent)
        else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
    }
}
