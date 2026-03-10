//
//  MetalView.swift
//  macOSShaderCanvas
//
//  This file implements the bridge between SwiftUI and Metal rendering.
//
//  DESIGN OVERVIEW:
//  ────────────────
//  SwiftUI cannot directly host an MTKView (MetalKit view). Apple's solution
//  is the NSViewRepresentable protocol, which wraps an AppKit NSView so that
//  SwiftUI can manage its lifecycle.
//
//  MetalView acts as a thin, stateless bridge:
//    1. It receives rendering parameters from SwiftUI (@State in ContentView).
//    2. On creation (makeNSView), it instantiates the MTKView and MetalRenderer.
//    3. On every SwiftUI state change (updateNSView), it pushes the new values
//       into the MetalRenderer, which handles all GPU work.
//
//  DATA FLOW:
//  ──────────
//    ContentView (@State)
//         │
//         ▼
//    MetalView (NSViewRepresentable)
//         │  activeShaders, meshType, backgroundImage
//         ▼
//    MetalRenderer (MTKViewDelegate)
//         │  compiles shaders, builds pipelines, draws frames
//         ▼
//       GPU
//
//  WHY NSViewRepresentable (not UIViewRepresentable)?
//  ──────────────────────────────────────────────────
//  This is a macOS app. On macOS, SwiftUI uses AppKit under the hood,
//  so we conform to NSViewRepresentable (not UIViewRepresentable, which
//  is iOS/iPadOS only). The wrapped view is MTKView, a MetalKit view
//  that provides a CAMetalLayer-backed drawable for GPU rendering.
//
//  COORDINATOR PATTERN:
//  ────────────────────
//  The Coordinator class holds long-lived mutable state that must survive
//  across SwiftUI view updates. Here it stores:
//    - renderer: the MetalRenderer instance (created once, reused forever)
//    - lastBackgroundImage: identity check to avoid reloading the same image
//

import SwiftUI
import MetalKit

// MARK: - MetalView

/// A SwiftUI wrapper around MTKView that bridges SwiftUI state into the Metal rendering pipeline.
///
/// This struct is the single connection point between the SwiftUI layer and the GPU.
/// It does NOT perform any rendering itself — all GPU work is delegated to `MetalRenderer`.
///
/// Usage in SwiftUI:
/// ```swift
/// MetalView(activeShaders: shaders, meshType: .sphere, backgroundImage: nil)
/// ```
struct MetalView: NSViewRepresentable {

    // MARK: - Input Properties (from SwiftUI)

    /// The ordered list of active shader layers (vertex, fragment, fullscreen).
    /// Changes to this array trigger shader recompilation in MetalRenderer.
    var activeShaders: [ActiveShader]

    /// The 3D mesh to render. Defaults to a UV sphere.
    /// Switching meshType triggers mesh reconstruction and pipeline recompilation.
    var meshType: MeshType = .sphere

    /// Optional background image displayed behind the 3D mesh.
    /// When set, the image is uploaded to the GPU as a texture and rendered
    /// as a fullscreen quad before the mesh pass.
    var backgroundImage: NSImage? = nil
    
    /// Data Flow configuration controlling which vertex fields are active.
    /// Changes trigger recompilation of all mesh shaders via MetalRenderer.
    var dataFlowConfig: DataFlowConfig = DataFlowConfig()
    
    /// Current user parameter values for all shaders (keyed by param name).
    var paramValues: [String: [Float]] = [:]

    // MARK: - NSViewRepresentable Lifecycle

    /// Called ONCE when the SwiftUI view first appears.
    /// Creates the MTKView, assigns a Metal device, and initializes the MetalRenderer.
    ///
    /// - Parameter context: Provides access to the Coordinator for storing the renderer.
    /// - Returns: A configured MTKView ready for Metal rendering.
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()

        // Obtain the default Metal device (GPU). This is the entry point to all Metal APIs.
        // On Macs with multiple GPUs, this returns the system-preferred one.
        mtkView.device = MTLCreateSystemDefaultDevice()

        // Create the renderer and store it in the coordinator for persistence across updates.
        if let renderer = MetalRenderer(metalView: mtkView) {
            context.coordinator.renderer = renderer
        }

        return mtkView
    }

    /// Called on EVERY SwiftUI state change that affects this view's inputs.
    /// This is the primary mechanism for pushing SwiftUI state into the Metal renderer.
    ///
    /// The method is intentionally lightweight — it only forwards values.
    /// Heavy work (shader compilation, texture loading) happens inside MetalRenderer
    /// only when the values actually differ from the previous frame.
    ///
    /// - Parameters:
    ///   - nsView: The existing MTKView instance.
    ///   - context: Provides access to the Coordinator (and thus the renderer).
    func updateNSView(_ nsView: MTKView, context: Context) {
        if let renderer = context.coordinator.renderer {
            // Forward the current mesh type. MetalRenderer's didSet on currentMeshType
            // will detect changes and rebuild the mesh + pipeline only when needed.
            renderer.currentMeshType = meshType

            // Forward the shader array. MetalRenderer.updateShaders() performs a diff
            // against the previous array and only recompiles shaders whose code changed.
            renderer.updateShaders(activeShaders, dataFlow: dataFlowConfig, paramValues: paramValues, in: nsView)

            // Only reload the background texture if the NSImage instance changed.
            // We use identity comparison (===) via the coordinator to avoid redundant
            // GPU texture uploads on every SwiftUI update cycle.
            if context.coordinator.lastBackgroundImage !== backgroundImage {
                renderer.loadBackgroundImage(backgroundImage)
                context.coordinator.lastBackgroundImage = backgroundImage
            }
        }
    }

    /// Creates the Coordinator instance. Called once before makeNSView.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    /// Holds mutable state that persists across SwiftUI view updates.
    ///
    /// SwiftUI may recreate the MetalView struct on every state change,
    /// but the Coordinator is created once and reused. This makes it the
    /// right place to store the MetalRenderer and any identity-check caches.
    class Coordinator {
        /// The Metal rendering engine. Created once in makeNSView, reused for the app's lifetime.
        var renderer: MetalRenderer?

        /// Tracks the last NSImage passed in, so we can skip redundant GPU texture uploads.
        /// Uses reference identity (===) rather than value equality for efficiency.
        var lastBackgroundImage: NSImage?
    }
}
