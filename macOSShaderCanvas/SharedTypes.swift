//
//  SharedTypes.swift
//  macOSShaderCanvas
//
//  Shared data models and type definitions used across the entire application.
//
//  This file contains:
//  1. Custom UTType for .shadercanvas file format
//  2. CanvasMode enum (2D / 3D)
//  3. ShaderCategory enum (vertex / fragment / fullscreen)
//  4. MeshType enum (sphere / cube / custom URL) with Codable support
//  5. ActiveShader model (one shader layer in the workspace)
//  6. DataFlowConfig (configurable vertex data fields)
//  7. CanvasDocument model (serializable workspace state)
//  8. RecentProject model (Hub recent project entries)
//  9. NotificationCenter names for menu → view communication
//

import Foundation
import UniformTypeIdentifiers
import simd

// MARK: - Custom File Type

extension UTType {
    /// The custom Uniform Type Identifier for .shadercanvas workspace files.
    /// Declared as an exported type in Info.plist (com.linghent.shadercanvas).
    /// This enables Finder integration and document-based file associations.
    static let shaderCanvas = UTType(exportedAs: "com.linghent.shadercanvas")
}

// MARK: - Canvas Mode

/// Distinguishes between workspace modes.
/// Canvas modes provide direct shader editing. Lab modes add AI-collaborative
/// workflow with reference analysis, project documents, and engineering haptics.
enum CanvasMode: String, Codable, CaseIterable, Identifiable {
    case twoDimensional = "2D"
    case threeDimensional = "3D"
    case twoDimensionalLab = "2D Lab"
    case threeDimensionalLab = "3D Lab"

    var id: String { rawValue }

    var isLab: Bool { self == .twoDimensionalLab || self == .threeDimensionalLab }
    var is2D: Bool { self == .twoDimensional || self == .twoDimensionalLab }
    var is3D: Bool { self == .threeDimensional || self == .threeDimensionalLab }

    /// The underlying rendering dimension, independent of Lab/Canvas distinction.
    var baseDimension: CanvasMode {
        switch self {
        case .twoDimensional, .twoDimensionalLab: return .twoDimensional
        case .threeDimensional, .threeDimensionalLab: return .threeDimensional
        }
    }
}

// MARK: - 2D Shape Type

/// Built-in 2D shapes for the 2D canvas mode.
/// Analogous to MeshType in 3D mode — the user writes a fragment shader that
/// runs on the selected shape. The shape is rendered centered on the grid canvas
/// with SDF-based anti-aliased edges.
enum Shape2DType: String, CaseIterable, Codable, Identifiable {
    case rectangle = "Rectangle"
    case roundedRectangle = "Rounded Rect"
    case circle = "Circle"
    case capsule = "Capsule"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rectangle:        return "rectangle.fill"
        case .roundedRectangle: return "rectangle.roundedtop.fill"
        case .circle:           return "circle.fill"
        case .capsule:          return "capsule.fill"
        }
    }

    /// Screen-space width/height ratio of the shape quad.
    /// The vertex shader uses this to position a correctly proportioned quad.
    var quadAspect: Float {
        switch self {
        case .rectangle:        return 1.6
        case .roundedRectangle: return 1.6
        case .circle:           return 1.0
        case .capsule:          return 2.5
        }
    }
}

// MARK: - 2D Scene Object

/// A single object on the 2D canvas.  Each object has its own shape, transform,
/// and optionally overridden VS/FS code.  When `customVertexCode` or
/// `customFragmentCode` is nil the object uses the scene-wide shared shader.
struct Object2D: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var shapeType: Shape2DType
    var posX: Float
    var posY: Float
    var scaleW: Float
    var scaleH: Float
    var rotation: Float
    var cornerRadius: Float
    var customVertexCode: String?
    var customFragmentCode: String?
    /// When true, the shape type is locked and `_sdf_shape()` is available
    /// inside this object's custom fragment shader.
    var shapeLocked: Bool

    /// AI-preview objects are non-destructive clones created by the AI instead
    /// of modifying the user's original.  The user reviews them and explicitly
    /// accepts (replace original) or rejects (discard clone).
    var isAIPreview: Bool
    /// UUID of the original object this preview was cloned from.
    var sourceObjectID: UUID?

    init(id: UUID = UUID(), name: String = "Object", shapeType: Shape2DType = .roundedRectangle,
         posX: Float = 0, posY: Float = 0, scaleW: Float = 0.5, scaleH: Float = 0.5,
         rotation: Float = 0, cornerRadius: Float = 0.15,
         customVertexCode: String? = nil, customFragmentCode: String? = nil,
         shapeLocked: Bool = false,
         isAIPreview: Bool = false, sourceObjectID: UUID? = nil) {
        self.id = id
        self.name = name
        self.shapeType = shapeType
        self.posX = posX
        self.posY = posY
        self.scaleW = scaleW
        self.scaleH = scaleH
        self.rotation = rotation
        self.cornerRadius = cornerRadius
        self.customVertexCode = customVertexCode
        self.customFragmentCode = customFragmentCode
        self.shapeLocked = shapeLocked
        self.isAIPreview = isAIPreview
        self.sourceObjectID = sourceObjectID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        shapeType = try container.decode(Shape2DType.self, forKey: .shapeType)
        posX = try container.decode(Float.self, forKey: .posX)
        posY = try container.decode(Float.self, forKey: .posY)
        scaleW = try container.decode(Float.self, forKey: .scaleW)
        scaleH = try container.decode(Float.self, forKey: .scaleH)
        rotation = try container.decode(Float.self, forKey: .rotation)
        cornerRadius = try container.decodeIfPresent(Float.self, forKey: .cornerRadius) ?? 0.15
        customVertexCode = try container.decodeIfPresent(String.self, forKey: .customVertexCode)
        customFragmentCode = try container.decodeIfPresent(String.self, forKey: .customFragmentCode)
        shapeLocked = try container.decodeIfPresent(Bool.self, forKey: .shapeLocked) ?? false
        isAIPreview = try container.decodeIfPresent(Bool.self, forKey: .isAIPreview) ?? false
        sourceObjectID = try container.decodeIfPresent(UUID.self, forKey: .sourceObjectID)
    }
}

// MARK: - 2D Transform (GPU)

/// Per-object transform + canvas camera state passed to the vertex shader via buffer(3).
/// Memory layout must match the MSL `Transform2D` struct exactly.
struct Transform2D {
    var objectOffset: simd_float2 = .zero
    var objectScale: simd_float2 = .init(1, 1)
    var canvasPan: simd_float2 = .zero
    var canvasZoom: Float = 1.0
    var objectRotation: Float = 0
    var cornerRadius: Float = 0.15
}

// MARK: - Shader Category

/// Represents the three types of shader layers supported by the rendering pipeline.
///
/// The rendering pipeline processes these in a fixed order:
/// 1. **Vertex** — transforms mesh vertex positions (geometry deformation)
/// 2. **Fragment** — computes per-pixel color on the mesh surface (lighting, materials)
/// 3. **Fullscreen** — post-processing effects applied to the entire rendered image
///
/// Each category maps to a different stage in the Metal rendering pipeline.
enum ShaderCategory: String, CaseIterable, Identifiable, Codable {
    case vertex = "Vertex"
    case fragment = "Fragment"
    case fullscreen = "Fullscreen"

    var id: String { self.rawValue }

    /// SF Symbol icon name for the sidebar layer list.
    var icon: String {
        switch self {
        case .vertex: return "move.3d"
        case .fragment: return "paintbrush.fill"
        case .fullscreen: return "display"
        }
    }
}

// MARK: - Mesh Type

/// Defines the 3D mesh geometry to render.
///
/// Built-in meshes (sphere, cube) are generated via ModelIO's parametric constructors.
/// Custom meshes are loaded from user-provided USD/OBJ files.
///
/// Custom Codable implementation handles URL serialization gracefully:
/// - On encode: stores the file path as a string
/// - On decode: validates that the file still exists; falls back to .sphere if not
enum MeshType: Equatable, Codable {
    case sphere
    case cube
    case custom(URL)

    private enum CodingKeys: String, CodingKey {
        case type, path
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sphere:
            try container.encode("sphere", forKey: .type)
        case .cube:
            try container.encode("cube", forKey: .type)
        case .custom(let url):
            try container.encode("custom", forKey: .type)
            try container.encode(url.path, forKey: .path)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "cube":
            self = .cube
        case "custom":
            let path = try container.decode(String.self, forKey: .path)
            let url = URL(fileURLWithPath: path)
            // Graceful fallback: if the custom model file was moved or deleted,
            // revert to the default sphere rather than crashing.
            if FileManager.default.fileExists(atPath: path) {
                self = .custom(url)
            } else {
                self = .sphere
            }
        default:
            self = .sphere
        }
    }
}

// MARK: - Active Shader

/// Represents a single shader layer in the workspace.
///
/// Each ActiveShader holds:
/// - A unique identifier (UUID) for SwiftUI list diffing and pipeline lookup
/// - A category determining which pipeline stage it belongs to
/// - A user-editable name displayed in the sidebar
/// - The MSL source code, compiled at runtime by MetalRenderer
///
/// Conforms to Codable for canvas file persistence (save/load).
struct ActiveShader: Identifiable, Codable, Equatable {
    let id: UUID
    let category: ShaderCategory
    var name: String
    var code: String

    init(id: UUID = UUID(), category: ShaderCategory, name: String, code: String) {
        self.id = id
        self.category = category
        self.name = name
        self.code = code
    }
}

// MARK: - Data Flow Configuration

/// Configurable vertex data fields shared across all mesh shaders.
///
/// The Data Flow panel lets users toggle which vertex attributes are available
/// in their shaders. The system auto-generates VertexIn, VertexOut, and Uniforms
/// struct definitions in MSL based on this configuration.
///
/// Field dependencies:
/// - World Normal requires Normal
/// - View Direction requires World Position
struct DataFlowConfig: Codable, Equatable {
    var normalEnabled: Bool = true
    var uvEnabled: Bool = true
    var timeEnabled: Bool = true
    var worldPositionEnabled: Bool = false
    var worldNormalEnabled: Bool = false
    var viewDirectionEnabled: Bool = false
    
    /// Resolves field dependencies: enabling a field auto-enables its prerequisites,
    /// disabling a field auto-disables its dependents.
    mutating func resolveDependencies() {
        if worldNormalEnabled && !normalEnabled { normalEnabled = true }
        if viewDirectionEnabled && !worldPositionEnabled { worldPositionEnabled = true }
        if !normalEnabled { worldNormalEnabled = false }
        if !worldPositionEnabled { viewDirectionEnabled = false }
    }
}

// MARK: - 2D Data Flow Configuration

/// Configurable vertex data fields for 2D canvas shaders.
///
/// Controls which interpolated fields appear in the 2D VertexOut struct.
/// System fields (position, texCoord, shapeAspect, cornerRadius) are always
/// present for SDF masking and are not toggled here.
struct DataFlow2DConfig: Codable, Equatable {
    var timeEnabled: Bool = true
    var mouseEnabled: Bool = false
    var objectPositionEnabled: Bool = false
    var screenUVEnabled: Bool = false
}

// MARK: - Shader Parameters (Houdini ch/chramp style)

/// The type of a user-declared shader parameter.
/// Determines the UI control and the number of float slots in the param buffer.
enum ParamType: String, Codable {
    case float = "float"
    case float2 = "float2"
    case float3 = "float3"
    case float4 = "float4"
    case color = "color"
    
    var componentCount: Int {
        switch self {
        case .float: return 1
        case .float2: return 2
        case .float3, .color: return 3
        case .float4: return 4
        }
    }
}

/// A user-declared shader parameter parsed from `// @param` directives.
///
/// Usage in shader code:
/// ```metal
/// // @param speed float 1.0 0.0 10.0
/// // @param baseColor color 1.0 0.5 0.2
/// // @param offset float2 0.0 0.0
/// ```
/// Parameters become available as variables in the shader (via #define).
struct ShaderParam: Equatable, Codable {
    var name: String
    var type: ParamType
    var defaultValue: [Float]
    var minValue: Float?
    var maxValue: Float?
}

// MARK: - Uniforms (CPU ↔ GPU)

/// Fixed-layout uniform buffer passed to all 3D mesh shaders each frame.
///
/// All fields are always present regardless of DataFlowConfig to avoid
/// dynamic struct layout and alignment headaches. Shaders simply ignore
/// fields they don't need.
///
/// Memory layout must match the MSL `Uniforms` struct exactly.
struct Uniforms {
    var mvpMatrix: simd_float4x4
    var modelMatrix: simd_float4x4
    var normalMatrix: simd_float4x4
    var cameraPosition: simd_float4   // xyz = world position, w unused
    var time: Float
    var mouseX: Float = 0             // normalised cursor X [0,1]
    var mouseY: Float = 0             // normalised cursor Y [0,1]
    var _pad2: Float = 0
}

/// Lightweight uniform buffer for 2D canvas mode (fullscreen quad shaders).
/// Omits 3D matrices; provides resolution, time, and mouse position.
struct Uniforms2D {
    var resolution: simd_float2 = .zero
    var time: Float = 0
    var mouseX: Float = 0
    var mouseY: Float = 0
    var _pad: Float = 0
}

// MARK: - Canvas Document

/// The top-level serializable workspace state.
///
/// Saved as JSON to .shadercanvas files. Contains the canvas name,
/// canvas mode (2D/3D), mesh type, all shader layers, and the Data Flow configuration.
struct CanvasDocument: Codable {
    var name: String
    var mode: CanvasMode
    var meshType: MeshType
    var shape2DType: Shape2DType
    var shaders: [ActiveShader]
    var dataFlow: DataFlowConfig
    var dataFlow2D: DataFlow2DConfig
    var paramValues: [String: [Float]]

    // 2D scene data (nil in 3D mode or legacy files)
    var objects2D: [Object2D]?
    var sharedVertexCode2D: String?
    var sharedFragmentCode2D: String?

    // Lab mode data (nil in Canvas mode or legacy files)
    var labSession: LabSession?
    var references: [ReferenceItem]?
    var projectDocument: ProjectDocument?
    
    init(name: String, mode: CanvasMode = .threeDimensional, meshType: MeshType, shape2DType: Shape2DType = .roundedRectangle, shaders: [ActiveShader], dataFlow: DataFlowConfig = DataFlowConfig(), dataFlow2D: DataFlow2DConfig = DataFlow2DConfig(), paramValues: [String: [Float]] = [:], objects2D: [Object2D]? = nil, sharedVertexCode2D: String? = nil, sharedFragmentCode2D: String? = nil, labSession: LabSession? = nil, references: [ReferenceItem]? = nil, projectDocument: ProjectDocument? = nil) {
        self.name = name
        self.mode = mode
        self.meshType = meshType
        self.shape2DType = shape2DType
        self.shaders = shaders
        self.dataFlow = dataFlow
        self.dataFlow2D = dataFlow2D
        self.paramValues = paramValues
        self.objects2D = objects2D
        self.sharedVertexCode2D = sharedVertexCode2D
        self.sharedFragmentCode2D = sharedFragmentCode2D
        self.labSession = labSession
        self.references = references
        self.projectDocument = projectDocument
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        mode = try container.decodeIfPresent(CanvasMode.self, forKey: .mode) ?? .threeDimensional
        meshType = try container.decode(MeshType.self, forKey: .meshType)
        shape2DType = try container.decodeIfPresent(Shape2DType.self, forKey: .shape2DType) ?? .roundedRectangle
        shaders = try container.decode([ActiveShader].self, forKey: .shaders)
        dataFlow = try container.decodeIfPresent(DataFlowConfig.self, forKey: .dataFlow) ?? DataFlowConfig()
        dataFlow2D = try container.decodeIfPresent(DataFlow2DConfig.self, forKey: .dataFlow2D) ?? DataFlow2DConfig()
        paramValues = try container.decodeIfPresent([String: [Float]].self, forKey: .paramValues) ?? [:]
        objects2D = try container.decodeIfPresent([Object2D].self, forKey: .objects2D)
        sharedVertexCode2D = try container.decodeIfPresent(String.self, forKey: .sharedVertexCode2D)
        sharedFragmentCode2D = try container.decodeIfPresent(String.self, forKey: .sharedFragmentCode2D)
        labSession = try container.decodeIfPresent(LabSession.self, forKey: .labSession)
        references = try container.decodeIfPresent([ReferenceItem].self, forKey: .references)
        projectDocument = try container.decodeIfPresent(ProjectDocument.self, forKey: .projectDocument)
    }
}

// MARK: - Recent Project (Hub)

/// Metadata for a recently-opened project, displayed in the Hub window.
struct RecentProject: Codable, Identifiable, Equatable {
    var id: String { fileURL }
    var name: String
    var fileURL: String
    var mode: CanvasMode
    var lastOpened: Date
    var snapshotPath: String?
}

// MARK: - Plan Node Status

/// Lifecycle state of a single node in an `AgentPlan` task tree.
enum PlanNodeStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case skipped
}

// MARK: - Plan Node

/// A single task in the Agent's execution plan tree.
///
/// The tree mirrors the GDC "paradigm" concept: each node is an atomic task
/// with explicit context dependencies and outputs. Children can run in parallel
/// when they share no data dependencies.
struct PlanNode: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var status: PlanNodeStatus
    var children: [PlanNode]
    var thinking: String?
    var contextKeys: [String]
    var producedContext: [String: String]
    var actions: [AgentAction]?
    var error: String?

    init(id: UUID = UUID(), title: String, description: String, status: PlanNodeStatus = .pending,
         children: [PlanNode] = [], thinking: String? = nil, contextKeys: [String] = [],
         producedContext: [String: String] = [:], actions: [AgentAction]? = nil, error: String? = nil) {
        self.id = id; self.title = title; self.description = description; self.status = status
        self.children = children; self.thinking = thinking; self.contextKeys = contextKeys
        self.producedContext = producedContext; self.actions = actions; self.error = error
    }

    var totalCount: Int { 1 + children.reduce(0) { $0 + $1.totalCount } }
    var completedCount: Int { (status == .completed ? 1 : 0) + children.reduce(0) { $0 + $1.completedCount } }
}

// MARK: - Agent Plan

/// A complete task tree generated by Plan Mode.
///
/// Serializable to JSON so it can be inspected, saved alongside the canvas document,
/// and resumed across sessions.
struct AgentPlan: Identifiable, Codable {
    let id: UUID
    var title: String
    var status: PlanNodeStatus
    var nodes: [PlanNode]
    var contextSummary: String
    var totalSteps: Int
    var completedSteps: Int

    init(id: UUID = UUID(), title: String, status: PlanNodeStatus = .pending, nodes: [PlanNode] = [],
         contextSummary: String = "", totalSteps: Int = 0, completedSteps: Int = 0) {
        self.id = id; self.title = title; self.status = status; self.nodes = nodes
        self.contextSummary = contextSummary; self.totalSteps = totalSteps; self.completedSteps = completedSteps
    }

    mutating func recalculate() {
        totalSteps = nodes.reduce(0) { $0 + $1.totalCount }
        completedSteps = nodes.reduce(0) { $0 + $1.completedCount }
        if completedSteps == totalSteps && totalSteps > 0 { status = .completed }
        else if nodes.contains(where: { $0.status == .running }) { status = .running }
        else if nodes.contains(where: { $0.status == .failed }) { status = .failed }
    }
}

// MARK: - Shader Semantics (Engineering Touch)

/// Complexity tier for a shader, derived from line count and pattern analysis.
enum ShaderComplexity: String, Codable {
    case simple, moderate, complex
}

/// Structured semantic analysis of a single shader's MSL source code.
///
/// Produced by `ShaderAnalyzer` and injected into the AI context to give
/// the agent "engineering touch" — an understanding of *what* the shader does,
/// not just *what code it contains*.
struct ShaderSemantics: Codable {
    let effectTags: [String]
    let summary: String
    let usedUniforms: [String]
    let sampledSources: [String]
    let complexity: ShaderComplexity
    let lineCount: Int
    let temporalBehavior: String?
}

// MARK: - Stream Chunk (SSE)

/// A single token/fragment delivered via Server-Sent Events during streaming.
struct StreamChunk {
    enum ChunkType { case thinking, content, planJSON }
    let type: ChunkType
    let delta: String
}

// MARK: - AI Agent Types

/// The type of action the AI Agent can perform on the workspace.
///
/// 3D mode actions:
/// - `addLayer` / `modifyLayer`: operate on `ActiveShader` layers (vertex/fragment/fullscreen)
///
/// 2D mode actions:
/// - `addLayer` / `modifyLayer`: operate on fullscreen (post-processing) layers only
/// - `addObject2D`: create a new Object2D on the canvas
/// - `modifyObject2D`: change an existing Object2D's properties (position/scale/shape/etc.)
/// - `setSharedShader2D`: set the shared distortion (vertex) or fragment code
/// - `setObjectShader2D`: set per-object custom distortion or fragment code
/// - `requestShapeLock`: request to lock an object's shape to gain SDF access
enum AgentActionType: String, Codable {
    case addLayer
    case modifyLayer
    case addObject2D
    case modifyObject2D
    case setSharedShader2D
    case setObjectShader2D
    case requestShapeLock
}

/// A single action the AI Agent wants to perform on the shader workspace.
///
/// **3D / fullscreen actions** (`addLayer`, `modifyLayer`):
///   - `category`: "vertex" | "fragment" | "fullscreen"
///   - `code`: complete MSL source for the layer
///   - `targetLayerName`: (modifyLayer only) existing layer name to replace
///
/// **2D object actions** (`addObject2D`, `modifyObject2D`):
///   - `shapeType`: "Rectangle" | "Rounded Rect" | "Circle" | "Capsule"
///   - `posX`, `posY`, `scaleW`, `scaleH`, `rotation`, `cornerRadius`: transforms
///   - `targetObjectName`: (modifyObject2D only) existing object name
///
/// **2D shader actions** (`setSharedShader2D`, `setObjectShader2D`):
///   - `category`: "distortion" (vertex) | "fragment"
///   - `code`: MSL source for the shader
///   - `targetObjectName`: (setObjectShader2D only) target object name
struct AgentAction: Codable {
    let type: AgentActionType
    let category: String
    let name: String
    let code: String
    let targetLayerName: String?

    // 2D-specific fields
    let shapeType: String?
    let posX: Float?
    let posY: Float?
    let scaleW: Float?
    let scaleH: Float?
    let rotation: Float?
    let cornerRadius: Float?
    let targetObjectName: String?

    var shaderCategory: ShaderCategory? {
        switch category.lowercased() {
        case "vertex": return .vertex
        case "fragment": return .fragment
        case "fullscreen": return .fullscreen
        default: return nil
        }
    }

    var shape2DType: Shape2DType? {
        Shape2DType.allCases.first { $0.rawValue.lowercased() == (shapeType ?? "").lowercased() }
    }

    init(type: AgentActionType, category: String, name: String, code: String,
         targetLayerName: String? = nil, shapeType: String? = nil,
         posX: Float? = nil, posY: Float? = nil,
         scaleW: Float? = nil, scaleH: Float? = nil,
         rotation: Float? = nil, cornerRadius: Float? = nil,
         targetObjectName: String? = nil) {
        self.type = type
        self.category = category
        self.name = name
        self.code = code
        self.targetLayerName = targetLayerName
        self.shapeType = shapeType
        self.posX = posX
        self.posY = posY
        self.scaleW = scaleW
        self.scaleH = scaleH
        self.rotation = rotation
        self.cornerRadius = cornerRadius
        self.targetObjectName = targetObjectName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(AgentActionType.self, forKey: .type)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        targetLayerName = try container.decodeIfPresent(String.self, forKey: .targetLayerName)
        shapeType = try container.decodeIfPresent(String.self, forKey: .shapeType)
        posX = try container.decodeIfPresent(Float.self, forKey: .posX)
        posY = try container.decodeIfPresent(Float.self, forKey: .posY)
        scaleW = try container.decodeIfPresent(Float.self, forKey: .scaleW)
        scaleH = try container.decodeIfPresent(Float.self, forKey: .scaleH)
        rotation = try container.decodeIfPresent(Float.self, forKey: .rotation)
        cornerRadius = try container.decodeIfPresent(Float.self, forKey: .cornerRadius)
        targetObjectName = try container.decodeIfPresent(String.self, forKey: .targetObjectName)
    }
}

/// Structured response from the AI Agent containing its decision, explanation, and actions.
///
/// The Agent evaluates the user's request and returns:
/// - `canFulfill`: whether the request can be achieved within the current pipeline
/// - `explanation`: natural language explanation for the user
/// - `actions`: concrete layer operations to execute (add/modify)
/// - `barriers`: technical limitations preventing fulfillment (when canFulfill is false)
struct AgentResponse: Codable {
    let canFulfill: Bool
    let explanation: String
    let actions: [AgentAction]
    let barriers: [String]?
    let thinking: String?

    static func plainText(_ text: String) -> AgentResponse {
        AgentResponse(canFulfill: true, explanation: text, actions: [], barriers: nil, thinking: nil)
    }

    init(canFulfill: Bool, explanation: String, actions: [AgentAction], barriers: [String]?, thinking: String? = nil) {
        self.canFulfill = canFulfill
        self.explanation = explanation
        self.actions = actions
        self.barriers = barriers
        self.thinking = thinking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canFulfill = try container.decodeIfPresent(Bool.self, forKey: .canFulfill) ?? true
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        actions = try container.decodeIfPresent([AgentAction].self, forKey: .actions) ?? []
        barriers = try container.decodeIfPresent([String].self, forKey: .barriers)
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking)
    }
}

// MARK: - Menu Command Notifications

/// Notification names used for communication between the menu bar (macOSShaderCanvasApp)
/// and the main view (ContentView). This decoupled pattern is necessary because
/// SwiftUI menu commands cannot directly reference view state.
extension NSNotification.Name {
    static let canvasNew = NSNotification.Name("canvasNew")
    static let canvasSave = NSNotification.Name("canvasSave")
    static let canvasSaveAs = NSNotification.Name("canvasSaveAs")
    static let canvasOpen = NSNotification.Name("canvasOpen")
    static let canvasTutorial = NSNotification.Name("canvasTutorial")
    static let aiSettings = NSNotification.Name("aiSettings")
    static let aiChat = NSNotification.Name("aiChat")
    static let backToHub = NSNotification.Name("backToHub")
}
