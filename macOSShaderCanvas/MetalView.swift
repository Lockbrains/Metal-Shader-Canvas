//
//  MetalView.swift
//  macOSShaderCanvas
//
//  Bridge between SwiftUI and the Metal rendering pipeline.
//
//  DATA FLOW:
//    ContentView (@State)
//         │
//         ▼
//    MetalView (NSViewRepresentable)
//         │  objects2D, sharedVS/FS, canvasZoom/Pan, activeShaders…
//         ▼
//    MetalRenderer (MTKViewDelegate)
//         │  compiles shaders, builds pipelines, draws frames
//         ▼
//       GPU

import SwiftUI
import MetalKit
import simd

// MARK: - Notifications for canvas interaction (MTKView → SwiftUI)

extension NSNotification.Name {
    static let canvas2DObjectSelected = NSNotification.Name("canvas2DObjectSelected")
    static let canvas2DObjectMoved = NSNotification.Name("canvas2DObjectMoved")
    static let canvas2DZoomChanged = NSNotification.Name("canvas2DZoomChanged")
    static let canvas2DPanChanged = NSNotification.Name("canvas2DPanChanged")
}

// MARK: - TrackingMTKView

/// MTKView subclass that tracks mouse, pinch-zoom, scroll-pan, and object drag.
class TrackingMTKView: MTKView {
    /// Mouse position normalised to [0,1] with (0,0) at top-left (Metal UV convention).
    var normalizedMousePosition: simd_float2 = .zero

    /// Current canvas zoom (read from SwiftUI, mutated by magnify gesture).
    var canvasZoom: Float = 1.0
    /// Current canvas pan (read from SwiftUI, mutated by scroll).
    var canvasPan: simd_float2 = .zero

    /// Objects for hit-testing (set by MetalView.updateNSView).
    var objects2D: [Object2D] = []
    /// ID of the currently selected object (nil = none).
    var selectedObjectID: UUID?
    /// Whether a drag is in progress.
    private(set) var isDragging = false
    var isDraggingNow: Bool { isDragging }

    /// Direct renderer reference for bypassing SwiftUI during drag.
    weak var renderer: MetalRenderer?

    // MARK: Tracking areas

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        updateMousePosition(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        updateMousePosition(with: event)
        let canvasPos = screenToCanvas(event)
        if let hit = hitTest2DObject(at: canvasPos) {
            selectedObjectID = hit
            isDragging = true
            NotificationCenter.default.post(name: .canvas2DObjectSelected, object: hit)
        } else {
            selectedObjectID = nil
            isDragging = false
            NotificationCenter.default.post(name: .canvas2DObjectSelected, object: nil)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        updateMousePosition(with: event)
        guard isDragging, let objID = selectedObjectID else { return }
        let dx = Float(event.deltaX) / Float(max(bounds.width, 1)) * 2.0 / canvasZoom
        let dy = Float(-event.deltaY) / Float(max(bounds.height, 1)) * 2.0 / canvasZoom

        if let idx = objects2D.firstIndex(where: { $0.id == objID }) {
            objects2D[idx].posX += dx
            objects2D[idx].posY += dy
        }
        if let idx = renderer?.objects2D.firstIndex(where: { $0.id == objID }) {
            renderer?.objects2D[idx].posX += dx
            renderer?.objects2D[idx].posY += dy
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging, let objID = selectedObjectID,
           let idx = objects2D.firstIndex(where: { $0.id == objID }) {
            let obj = objects2D[idx]
            NotificationCenter.default.post(
                name: .canvas2DObjectMoved,
                object: [objID, obj.posX, obj.posY] as [Any]
            )
        }
        isDragging = false
    }

    // MARK: Zoom & Pan

    override func magnify(with event: NSEvent) {
        canvasZoom *= 1.0 + Float(event.magnification)
        canvasZoom = max(0.1, min(canvasZoom, 10.0))
        NotificationCenter.default.post(name: .canvas2DZoomChanged, object: canvasZoom)
    }

    override func scrollWheel(with event: NSEvent) {
        // Two-finger scroll → pan
        let dx = Float(event.scrollingDeltaX) / Float(max(bounds.width, 1)) * 2.0 / canvasZoom
        let dy = Float(-event.scrollingDeltaY) / Float(max(bounds.height, 1)) * 2.0 / canvasZoom
        canvasPan.x -= dx
        canvasPan.y -= dy
        NotificationCenter.default.post(name: .canvas2DPanChanged, object: [canvasPan.x, canvasPan.y] as [Float])
    }

    // MARK: Helpers

    private func updateMousePosition(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return }
        normalizedMousePosition = simd_float2(
            Float(loc.x / bounds.width).clamped(to: 0...1),
            Float(1.0 - loc.y / bounds.height).clamped(to: 0...1)
        )
    }

    /// Convert a mouse event to canvas-space coordinates (NDC, accounting for zoom/pan).
    private func screenToCanvas(_ event: NSEvent) -> simd_float2 {
        let loc = convert(event.locationInWindow, from: nil)
        var ndc = simd_float2(
            Float(loc.x / bounds.width) * 2.0 - 1.0,
            Float(loc.y / bounds.height) * 2.0 - 1.0
        )
        ndc = ndc / canvasZoom + canvasPan
        return ndc
    }

    /// Simple AABB hit-test against all 2D objects. Returns the topmost (last) hit.
    private func hitTest2DObject(at canvasPos: simd_float2) -> UUID? {
        for object in objects2D.reversed() {
            let halfW = object.scaleW * object.shapeType.quadAspect * 0.5
            let halfH = object.scaleH * 0.5
            let dx = canvasPos.x - object.posX
            let dy = canvasPos.y - object.posY
            if abs(dx) <= halfW && abs(dy) <= halfH {
                return object.id
            }
        }
        return nil
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - MetalView

/// A SwiftUI wrapper around MTKView that bridges SwiftUI state into the Metal rendering pipeline.
struct MetalView: NSViewRepresentable {

    // MARK: - Input Properties (from SwiftUI)

    var activeShaders: [ActiveShader]
    var meshType: MeshType = .sphere
    var backgroundImage: NSImage? = nil
    var dataFlowConfig: DataFlowConfig = DataFlowConfig()
    var dataFlow2DConfig: DataFlow2DConfig = DataFlow2DConfig()
    var paramValues: [String: [Float]] = [:]
    var rotationAngle: Float = 0
    var canvasMode: CanvasMode = .threeDimensional

    // 2D scene properties
    var objects2D: [Object2D] = []
    var sharedVertexCode2D: String = ShaderSnippets.distortion2DTemplate
    var sharedFragmentCode2D: String = ShaderSnippets.fragment2DDemo
    var canvasZoom: Float = 1.0
    var canvasPan: simd_float2 = .zero

    // Kept for backward compat
    var shape2DType: Shape2DType = .roundedRectangle

    // MARK: - NSViewRepresentable Lifecycle

    func makeNSView(context: Context) -> MTKView {
        let mtkView = TrackingMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()

        if let renderer = MetalRenderer(metalView: mtkView) {
            context.coordinator.renderer = renderer
        }

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        print("[DIAG] MetalView.updateNSView CALLED  \(CFAbsoluteTimeGetCurrent())")
        guard let renderer = context.coordinator.renderer else { return }
        let coord = context.coordinator

        // Lightweight updates — always applied, no recompilation.
        renderer.currentMeshType = meshType
        renderer.rotationAngle = rotationAngle
        renderer.paramValues = paramValues
        renderer.canvasMode = canvasMode
        renderer.shape2DType = shape2DType

        var force2D = false
        if canvasMode.is2D {
            renderer.objects2D = objects2D
            renderer.sharedVertexCode2D = sharedVertexCode2D
            renderer.sharedFragmentCode2D = sharedFragmentCode2D
            renderer.canvasZoom = canvasZoom
            renderer.canvasPan = canvasPan
            renderer.dataFlow2DConfig = dataFlow2DConfig

            if coord.needs2DPipelineUpdate(objects: objects2D, sharedVS: sharedVertexCode2D, sharedFS: sharedFragmentCode2D, dataFlow2D: dataFlow2DConfig) {
                force2D = true
                coord.cache2DState(objects: objects2D, sharedVS: sharedVertexCode2D, sharedFS: sharedFragmentCode2D, dataFlow2D: dataFlow2DConfig)
            }

            if let tv = nsView as? TrackingMTKView {
                if !tv.isDraggingNow {
                    tv.objects2D = objects2D
                }
                tv.canvasZoom = canvasZoom
                tv.canvasPan = canvasPan
                tv.renderer = renderer
            }
        }

        // Heavy update — shader code, data flow, or 2D object state changed.
        // Routes all compilation through updateShaders for epoch coordination.
        if force2D || coord.needsShaderUpdate(shaders: activeShaders, dataFlow: dataFlowConfig) {
            renderer.updateShaders(activeShaders, dataFlow: dataFlowConfig, in: nsView, force2DCompile: force2D)
            coord.cacheShaderState(shaders: activeShaders, dataFlow: dataFlowConfig)
        }

        if coord.lastBackgroundImage !== backgroundImage {
            renderer.loadBackgroundImage(backgroundImage)
            coord.lastBackgroundImage = backgroundImage
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator {
        var renderer: MetalRenderer?
        var lastBackgroundImage: NSImage?

        // 3D shader cache
        private var cachedShaderIDs: [UUID] = []
        private var cachedShaderCodes: [String] = []
        private var cachedDataFlow: DataFlowConfig?

        func needsShaderUpdate(shaders: [ActiveShader], dataFlow: DataFlowConfig) -> Bool {
            if dataFlow != cachedDataFlow { return true }
            if shaders.count != cachedShaderIDs.count { return true }
            for (i, shader) in shaders.enumerated() {
                if shader.id != cachedShaderIDs[i] || shader.code != cachedShaderCodes[i] {
                    return true
                }
            }
            return false
        }

        func cacheShaderState(shaders: [ActiveShader], dataFlow: DataFlowConfig) {
            cachedShaderIDs = shaders.map(\.id)
            cachedShaderCodes = shaders.map(\.code)
            cachedDataFlow = dataFlow
        }

        // 2D pipeline cache
        private var cached2DObjectIDs: [UUID] = []
        private var cached2DObjectShapes: [Shape2DType] = []
        private var cached2DObjectCodes: [String] = []
        private var cached2DObjectLocked: [Bool] = []
        private var cached2DSharedVS: String = ""
        private var cached2DSharedFS: String = ""
        private var cached2DDataFlow: DataFlow2DConfig?

        func needs2DPipelineUpdate(objects: [Object2D], sharedVS: String, sharedFS: String, dataFlow2D: DataFlow2DConfig) -> Bool {
            if dataFlow2D != cached2DDataFlow { return true }
            if sharedVS != cached2DSharedVS || sharedFS != cached2DSharedFS { return true }
            if objects.count != cached2DObjectIDs.count { return true }
            for (i, obj) in objects.enumerated() {
                if obj.id != cached2DObjectIDs[i] { return true }
                if obj.shapeType != cached2DObjectShapes[i] { return true }
                if obj.shapeLocked != cached2DObjectLocked[i] { return true }
                let code = (obj.customVertexCode ?? "") + "|" + (obj.customFragmentCode ?? "")
                if code != cached2DObjectCodes[i] { return true }
            }
            return false
        }

        func cache2DState(objects: [Object2D], sharedVS: String, sharedFS: String, dataFlow2D: DataFlow2DConfig) {
            cached2DObjectIDs = objects.map(\.id)
            cached2DObjectShapes = objects.map(\.shapeType)
            cached2DObjectCodes = objects.map { ($0.customVertexCode ?? "") + "|" + ($0.customFragmentCode ?? "") }
            cached2DObjectLocked = objects.map(\.shapeLocked)
            cached2DSharedVS = sharedVS
            cached2DSharedFS = sharedFS
            cached2DDataFlow = dataFlow2D
        }
    }
}
