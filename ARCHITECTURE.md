# macOS Shader Canvas — Architecture Documentation

A detailed technical architecture for the macOS Metal shader editor application.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [File Structure](#2-file-structure)
3. [Two-Layer Architecture](#3-two-layer-architecture)
4. [MetalView Design](#4-metalview-design)
5. [MetalRenderer Design](#5-metalrenderer-design)
6. [Metal API Reference](#6-metal-api-reference)
7. [Rendering Pipeline](#7-rendering-pipeline)
8. [Runtime Shader Compilation](#8-runtime-shader-compilation)
9. [Data Flow](#9-data-flow)
10. [Shader Conventions](#10-shader-conventions)
11. [Matrix Math](#11-matrix-math)
12. [Supporting Systems](#12-supporting-systems)
13. [Requirements](#13-requirements)

---

## 1. Project Overview

**macOS Shader Canvas** is a native macOS application built with SwiftUI and Metal that enables users to compose, edit, and preview Metal shaders in real time on 3D meshes. Key characteristics:

- **Layer-based shader architecture**: Vertex, fragment, and post-processing (fullscreen) shaders
- **Live editing**: MSL source is compiled at runtime; changes appear on the next frame
- **3D mesh preview**: Sphere, cube, or custom USD/OBJ models
- **Multi-pass rendering**: Post-processing chain with ping-pong buffers
- **Optional background image**: User images rendered behind the mesh

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     macOS Shader Canvas                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  SwiftUI UI          │  Metal Rendering                                  │
│  • Sidebar           │  • 3D mesh with user shaders                      │
│  • Code editor       │  • Post-processing chain                          │
│  • Tutorial panel    │  • Real-time preview                              │
│  • AI chat           │                                                   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. File Structure

```
macOSShaderCanvas/
├── macOSShaderCanvasApp.swift    # App entry point, menu commands (NotificationCenter)
├── ContentView.swift             # Main UI: sidebar, editor, tutorial, canvas logic
├── MetalView.swift               # NSViewRepresentable bridge (SwiftUI ↔ MTKView)
├── MetalRenderer.swift           # Metal rendering engine (MTKViewDelegate)
├── SharedTypes.swift             # Data models, UTType, notification names
├── ShaderSnippets.swift          # Shader source: defaults, demos, templates, presets
├── TutorialData.swift            # 9-step tutorial content
├── AIService.swift               # AI chat & tutorial generation (actor)
├── AIChatView.swift              # AI chat UI + glow border
├── AISettings.swift              # AI provider config (Observable, UserDefaults)
├── Info.plist                    # UTType export for .shadercanvas
├── Localizable.xcstrings         # Localization (en, zh-Hans, ja)
└── Assets.xcassets/              # App icon, accent color
```

---

## 3. Two-Layer Architecture

The app is split into two distinct layers with a thin bridge:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        SWIFTUI FRONTEND                                   │
│  • ContentView: sidebar, code editor, tutorial, AI chat                   │
│  • @State: activeShaders, meshType, backgroundImage, canvasName, etc.     │
│  • Menu commands via NotificationCenter                                   │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │  MetalView (NSViewRepresentable)
                                    │  • makeNSView() → create MTKView + MetalRenderer
                                    │  • updateNSView() → push state into renderer
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                        METAL BACKEND                                      │
│  • MetalRenderer: MTKViewDelegate                                         │
│  • All GPU resources: pipelines, textures, meshes                        │
│  • Multi-pass draw(in:) pipeline                                           │
│  • Runtime MSL compilation                                                 │
└──────────────────────────────────────────────────────────────────────────┘
```

| Layer | Responsibility |
|-------|----------------|
| **SwiftUI** | UI, state, user input, file I/O, AI integration |
| **Metal** | GPU rendering, shader compilation, mesh loading |

---

## 4. MetalView Design

`MetalView` is the **bridge** between SwiftUI and Metal. It conforms to `NSViewRepresentable` (macOS uses AppKit, not UIKit).

### 4.1 Why NSViewRepresentable?

SwiftUI cannot directly host an `MTKView`. Apple's solution is to wrap an AppKit `NSView` via `NSViewRepresentable` so SwiftUI can manage its lifecycle. The wrapped view is `MTKView`, which provides a `CAMetalLayer`-backed drawable for GPU rendering.

```
┌─────────────────────────────────────────────────────────────────┐
│  SwiftUI View Hierarchy                                           │
│                                                                   │
│    ContentView                                                    │
│         │                                                         │
│         └── MetalView (NSViewRepresentable)                        │
│                   │                                               │
│                   └── MTKView (AppKit)                            │
│                             │                                     │
│                             └── CAMetalLayer (drawable)           │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Input Properties

| Property | Type | Purpose |
|----------|------|---------|
| `activeShaders` | `[ActiveShader]` | Shader layer configuration; changes trigger recompilation |
| `meshType` | `MeshType` | 3D mesh to render (sphere, cube, custom) |
| `backgroundImage` | `NSImage?` | Optional background texture |

### 4.3 Lifecycle Methods

```
┌─────────────────────────────────────────────────────────────────────────┐
│  makeCoordinator()                                                       │
│      │  Called once before makeNSView                                    │
│      │  Creates Coordinator (stores renderer, lastBackgroundImage)       │
│      ▼                                                                   │
│  makeNSView(context:)                                                     │
│      │  Called ONCE when view first appears                               │
│      │  • Create MTKView                                                  │
│      │  • mtkView.device = MTLCreateSystemDefaultDevice()                 │
│      │  • MetalRenderer(metalView:) → context.coordinator.renderer        │
│      │  • Return MTKView                                                  │
│      ▼                                                                   │
│  updateNSView(nsView, context:)                                          │
│      │  Called on EVERY SwiftUI state change                              │
│      │  • renderer.currentMeshType = meshType                             │
│      │  • renderer.updateShaders(activeShaders, in: nsView)               │
│      │  • if lastBackgroundImage !== backgroundImage: loadBackgroundImage│
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.4 Coordinator Pattern

The `Coordinator` holds **mutable state** that persists across SwiftUI view updates. SwiftUI may recreate the `MetalView` struct on every state change, but the Coordinator is created once and reused.

| Coordinator Property | Purpose |
|----------------------|---------|
| `renderer` | `MetalRenderer` instance (created once, reused for app lifetime) |
| `lastBackgroundImage` | Identity check (`===`) to avoid redundant GPU texture uploads |

---

## 5. MetalRenderer Design

`MetalRenderer` is the **Metal rendering engine**. It owns all GPU resources and implements the multi-pass pipeline. It conforms to `MTKViewDelegate` to receive frame callbacks and resize notifications.

### 5.1 Resource Categories

```
┌─────────────────────────────────────────────────────────────────────────┐
│  MetalRenderer GPU Resources                                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. PIPELINES (MTLRenderPipelineState)                                   │
│     ┌──────────────────────────────────────────────────────────────┐    │
│     │ meshPipelineState        │ User vertex + fragment shader     │    │
│     │ fullscreenPipelineStates │ One per post-processing layer      │    │
│     │ blitPipelineState        │ Final copy to screen drawable      │    │
│     │ bgBlitPipelineState      │ Background image rendering         │    │
│     └──────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  2. TEXTURES (MTLTexture)                                                 │
│     ┌──────────────────────────────────────────────────────────────┐    │
│     │ offscreenTextureA/B  │ Ping-pong buffers (.bgra8Unorm)        │    │
│     │ depthTexture        │ Depth buffer (.depth32Float)            │    │
│     │ backgroundTexture   │ User-uploaded image                     │    │
│     └──────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  3. MESH (MTKMesh via ModelIO)                                           │
│     ┌──────────────────────────────────────────────────────────────┐    │
│     │ Vertex layout: position(float3) + normal(float3) + texCoord  │    │
│     │ Stride: 32 bytes                                              │    │
│     │ Supports: sphere, cube, custom USD/OBJ                        │    │
│     └──────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  4. UNIFORMS (CPU → GPU per frame)                                       │
│     ┌──────────────────────────────────────────────────────────────┐    │
│     │ struct Uniforms {                                              │    │
│     │     modelViewProjectionMatrix: simd_float4x4                   │    │
│     │     time: Float                                                │    │
│     │ }                                                              │    │
│     │ Always at buffer index 1                                       │    │
│     └──────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Vertex Layout (Mesh)

| Attribute | Format | Buffer Index | Offset |
|-----------|--------|--------------|--------|
| position | float3 | 0 | 0 |
| normal | float3 | 0 | 12 |
| texCoord | float2 | 0 | 24 |
| **(stride)** | | | **32** |

### 5.3 Offscreen Texture Configuration

| Texture | Format | Usage | Storage |
|---------|--------|-------|---------|
| offscreenTextureA | .bgra8Unorm | .renderTarget + .shaderRead | .private |
| offscreenTextureB | .bgra8Unorm | .renderTarget + .shaderRead | .private |
| depthTexture | .depth32Float | .renderTarget | .private |

Color textures need both `.renderTarget` (write) and `.shaderRead` (sample in next pass).

### 5.4 Initialization Sequence

```
init?(metalView: MTKView)
    │
    ├── Capture device from metalView.device
    ├── metalView.delegate = self
    ├── metalView.clearColor = dark gray
    ├── metalView.depthStencilPixelFormat = .invalid (depth in offscreen pass)
    ├── metalView.framebufferOnly = true
    ├── commandQueue = device.makeCommandQueue()
    ├── depthStencilState = .less, depth write enabled
    ├── setupMesh(type: .sphere)
    ├── compileMeshPipeline()
    ├── compileBlitPipeline(metalView:)
    └── compileBgBlitPipeline()
```

### 5.5 Shader Update Diffing

`updateShaders(_:in:)` performs a diff to avoid unnecessary recompilation:

| Change Type | Action |
|-------------|--------|
| Vertex code changed | `compileMeshPipeline()` |
| Fragment code changed | `compileMeshPipeline()` |
| Fullscreen shaders changed (id or code) | `compileFullscreenPipelines(metalView:)` |

---

## 6. Metal API Reference

| API | Purpose |
|-----|---------|
| `MTLDevice` | GPU device handle; all Metal resources created through it |
| `MTLCommandQueue` | Serializes command buffers; one per renderer |
| `MTLCommandBuffer` | Per-frame GPU command batch |
| `MTLRenderCommandEncoder` | Encodes draw calls within a render pass |
| `MTLRenderPipelineState` | Compiled vertex + fragment shader pair |
| `MTLDepthStencilState` | Depth testing configuration (.less, write enabled) |
| `MTLLibrary` | Compiled MSL source (runtime via `makeLibrary(source:options:)`) |
| `MTLFunction` | Named shader entry point (`makeFunction(name:)`) |
| `MTLTexture` | Render targets, background, ping-pong buffers |
| `MTKTextureLoader` | NSImage/CGImage → GPU texture |
| `MTKMesh` / `MDLMesh` | 3D geometry from ModelIO |
| `MTKView` | CAMetalLayer-backed drawable |
| `MTLRenderPassDescriptor` | Defines render target, load/store actions |
| `MTLTextureDescriptor` | Texture allocation parameters |

### 6.1 Metal Object Hierarchy

```
MTLDevice
    │
    ├── makeCommandQueue() ──────────────► MTLCommandQueue
    │                                          │
    │                                          └── makeCommandBuffer() ─► MTLCommandBuffer
    │                                                                         │
    │                                                                         ├── makeRenderCommandEncoder(descriptor:)
    │                                                                         │       └── setRenderPipelineState, setVertexBytes, drawPrimitives...
    │                                                                         │
    │                                                                         ├── present(drawable)
    │                                                                         └── commit()
    │
    ├── makeLibrary(source:options:) ────► MTLLibrary
    │                                          └── makeFunction(name:) ─► MTLFunction
    │
    ├── makeRenderPipelineState(descriptor:) ─► MTLRenderPipelineState
    │
    ├── makeDepthStencilState(descriptor:) ─► MTLDepthStencilState
    │
    ├── makeTexture(descriptor:) ───────────► MTLTexture
    │
    └── (MTKTextureLoader uses device) ─────► MTLTexture
```

---

## 7. Rendering Pipeline

The `draw(in:)` method encodes the full multi-pass pipeline every frame.

### 7.1 Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PASS 1: Base Mesh → offscreenTextureA                                       │
│  ─────────────────────────────────────                                     │
│  1. Clear color to dark gray (0.15, 0.15, 0.15)                             │
│  2. Clear depth to 1.0                                                       │
│  3. Draw background image (fullscreen triangle) if loaded                    │
│  4. Draw 3D mesh with user vertex + fragment shaders                        │
│     • MVP matrix + time at buffer(1)                                         │
│     • Depth testing enabled                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  PASS 2..N: Post-Processing (Ping-Pong A ↔ B)                               │
│  ────────────────────────────────────────────                               │
│  For each fullscreen shader layer (in order):                                │
│    • Read from currentSourceTex [[texture(0)]]                               │
│    • Write to currentDestTex                                                 │
│    • Bind Uniforms (time) at buffer(1)                                      │
│    • Draw fullscreen triangle (3 vertices)                                   │
│    • Swap source ↔ dest                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  PASS FINAL: Blit to Screen                                                  │
│  ─────────────────────────────                                               │
│  • Copy currentSourceTex → view.currentDrawable                              │
│  • Simple texture sampling, no effects                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Ping-Pong Buffer Flow

```
PASS 1:  [Mesh + BG] ──────────────────► texA
                                              │
PASS 2:  texA (read) ──► [Shader 1] ──► texB  │
                                              │
PASS 3:  texB (read) ──► [Shader 2] ──► texA  │
                                              │
PASS 4:  texA (read) ──► [Shader 3] ──► texB  │
                                              │
FINAL:   currentSourceTex ──► [Blit] ──► drawable
```

### 7.3 Fullscreen Triangle Technique

Instead of a quad (4 vertices, 2 triangles), a **single oversized triangle** covers the entire screen. The GPU clips the excess. This reduces vertex count and simplifies the vertex shader.

```
         Clip space positions:
         
              (-1, 3) ●
                     /|
                    / |
                   /  |
                  /   |
                 /    |
                /     |
               /      |
    (-1,-1) ●─────────● (3,-1)
              
    One triangle covers NDC [-1,1] × [-1,1]
    Positions: (-1,-1), (3,-1), (-1,3)
```

In MSL:
```metal
float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
```

---

## 8. Runtime Shader Compilation

Unlike typical Metal apps that pre-compile shaders into `.metallib` bundles, this app compiles MSL source strings at runtime.

### 8.1 Compilation Flow

```
User types code
      │
      ▼
device.makeLibrary(source: mslString, options: nil)
      │
      ▼
MTLLibrary
      │
      ▼
library.makeFunction(name: "vertex_main")   library.makeFunction(name: "fragment_main")
      │                                              │
      └──────────────────────┬───────────────────────┘
                             ▼
              MTLRenderPipelineDescriptor
              • vertexFunction
              • fragmentFunction
              • colorAttachments[0].pixelFormat
              • (optional) depthAttachmentPixelFormat
              • (optional) vertexDescriptor
                             │
                             ▼
              device.makeRenderPipelineState(descriptor:)
                             │
                             ▼
              MTLRenderPipelineState (immutable, GPU-optimized)
```

### 8.2 When Compilation Occurs

| Trigger | Pipelines Recompiled |
|---------|----------------------|
| Vertex shader code change | meshPipelineState |
| Fragment shader code change | meshPipelineState |
| Fullscreen shader add/remove/change | fullscreenPipelineStates |
| Mesh type change | meshPipelineState (vertex descriptor) |
| View resize | blitPipelineState (pixel format) — typically once at init |

---

## 9. Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ContentView (@State)                                                        │
│  • activeShaders: [ActiveShader]                                             │
│  • meshType: MeshType                                                        │
│  • backgroundImage: NSImage?                                                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │  Passed as view parameters
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  MetalView (NSViewRepresentable)                                             │
│  updateNSView() pushes:                                                      │
│  • renderer.currentMeshType = meshType                                       │
│  • renderer.updateShaders(activeShaders, in: view)                           │
│  • renderer.loadBackgroundImage(backgroundImage)                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  MetalRenderer (MTKViewDelegate)                                              │
│  • Diffs shaders → recompiles only changed pipelines                         │
│  • Rebuilds mesh when meshType changes                                        │
│  • Uploads background texture when image changes                              │
│  • draw(in:) runs every frame → GPU                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 9.1 Menu Communication

Menu bar commands cannot directly reference SwiftUI view state. The app uses `NotificationCenter`:

```
macOSShaderCanvasApp (menu handler)
    │
    └── NotificationCenter.post(canvasNew / canvasSave / canvasOpen / ...)
              │
              ▼
ContentView.onReceive(Notification)
    │
    └── Updates @State, presents file dialogs, etc.
```

---

## 10. Shader Conventions

### 10.1 Entry Points

All shaders must define:

| Function | Purpose |
|----------|---------|
| `vertex_main` | Vertex shader entry point |
| `fragment_main` | Fragment shader entry point |

### 10.2 Buffer and Texture Indices

| Index | Content |
|-------|---------|
| buffer(1) | `Uniforms` struct (MVP matrix, time) |
| texture(0) | Input texture (for fullscreen/blit: previous pass output) |
| attribute(0) | position |
| attribute(1) | normal |
| attribute(2) | texCoord |

### 10.3 Uniforms Struct (CPU/GPU Contract)

```metal
struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float time;
};
```

Must match the Swift `Uniforms` struct in `MetalRenderer.swift`.

### 10.4 Shader Categories and Pipeline Stage

| Category | Pipeline Stage | Input | Output |
|----------|----------------|-------|--------|
| Vertex | Mesh pass | Vertex attributes | Clip-space position, varyings |
| Fragment | Mesh pass | Varyings, uniforms | Offscreen color texture |
| Fullscreen | Post-processing | Previous pass texture, uniforms | Next ping-pong buffer |

---

## 11. Matrix Math

### 11.1 Perspective Projection

Right-handed, Metal NDC Z range [0, 1] (not OpenGL's [-1, 1]):

```
matrix_perspective_right_hand(fovy, aspect, nearZ, farZ)
```

### 11.2 Transform Composition

```
MVP = Projection × View × Model  (right-to-left multiplication)
```

- **Projection**: 60° FOV, aspect from viewport
- **View**: Camera at (0, 0, -8)
- **Model**: Y-axis rotation driven by `time * 0.3`

### 11.3 Rodrigues Rotation

`matrix_rotation(radians, axis)` — rotation around an arbitrary axis using Rodrigues' formula.

---

## 12. Supporting Systems

### 12.1 Canvas Persistence

- **Format**: JSON (`.shadercanvas`)
- **UTType**: `com.linghent.shadercanvas`
- **Codable**: `CanvasDocument` (name, meshType, shaders)

### 12.2 AI Integration

- **AIService** (actor): Thread-safe API calls
- **Providers**: OpenAI, Anthropic, Gemini
- **Features**: Chat with shader context, tutorial generation (JSON → TutorialStep)

### 12.3 Tutorial System

9 progressive lessons:

1. Solid color  
2. Normals  
3. Lambert  
4. Blinn-Phong  
5. Time animation  
6. Vertex displacement  
7. Fresnel  
8. Post-processing  
9. Final challenge  

---

## 13. Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 26+ |
| Xcode | 26+ |
| GPU | Metal-capable |
| Frameworks | SwiftUI, Metal, MetalKit, ModelIO, simd |

---

*This document describes the architecture of macOS Shader Canvas as of the current codebase.*
