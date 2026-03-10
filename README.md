# macOS Shader Canvas

A lightweight Metal shader workbench for macOS — build, edit, and layer shaders in real time on 3D meshes.

> **中文** · [简体中文版 (README_CN.md)](README_CN.md)

<p align="center">
  <img src="macOSShaderCanvas/Assets.xcassets/AppIcon.appiconset/Frame 1.png" width="128" alt="App Icon"/>
</p>

## Overview

macOS Shader Canvas is a native macOS application that lets you compose Metal shaders visually. Think of it as a mini graphics engine: add vertex, fragment, and post-processing shaders as stackable layers, edit them live with syntax highlighting, and see results instantly on a 3D mesh.

### Key Features

- **Real-time shader editing** with Metal syntax highlighting, auto-indent, and snippet insertion
- **Layer-based architecture** — stack any number of vertex, fragment, and fullscreen shaders
- **Multi-pass rendering pipeline** with ping-pong post-processing
- **10 fragment presets** (Lambert, Phong, Blinn-Phong, Fresnel, Cel/Toon, Gooch, etc.)
- **5 post-processing presets** (Bloom, Gaussian Blur, HSV Adjustment, Tone Mapping, Edge Detection)
- **Mesh switching** — sphere, cube, or custom USD/OBJ upload
- **Background images** — load any image as the scene backdrop
- **Canvas persistence** — save/load entire workspaces as `.shadercanvas` files
- **Interactive tutorial** — 9-step guided course to learn Metal shaders from scratch
- **AI-powered chat** — Get shader help from OpenAI, Anthropic, or Gemini
- **AI tutorial generation** — Generate custom shader tutorials on any topic
- **Localization** — English, Simplified Chinese, Japanese

---

## Getting Started

### Requirements

- macOS 26+ (Tahoe)
- Xcode 26+
- Metal-capable GPU

### Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/macOSShaderCanvas.git
   cd macOSShaderCanvas
   ```

2. Open the project in Xcode:
   ```bash
   open macOSShaderCanvas.xcodeproj
   ```

3. Select the **macOSShaderCanvas** scheme and run (⌘R).

4. Try **File → Tutorial** (⇧⌘T) for a guided introduction to Metal shaders.

---

## AI Features

macOS Shader Canvas includes AI-powered tools to help you learn and build shaders faster.

### AI Chat

The built-in chat panel connects to **OpenAI**, **Anthropic**, or **Google Gemini**. It understands your current workspace — active shaders, mesh type, and code — and provides contextual MSL help. Ask questions in your preferred language; the AI responds with valid Metal code using the app’s conventions (`vertex_main`, `fragment_main`, `Uniforms` at buffer index 1, etc.).

Configure your API key in **Settings → AI** before using the chat.

### AI Tutorial Generation

Generate custom step-by-step tutorials on any topic. Describe what you want to learn (e.g. “PBR shader”, “vertex displacement”, “screen-space effects”), and the AI produces a structured tutorial with starter code, solution code, and hints. Generated tutorials load directly into the tutorial panel and follow the same format as the built-in 9-step course.

---

## Project Structure

| File | Description |
|------|-------------|
| `macOSShaderCanvasApp.swift` | App entry point, menu commands (NotificationCenter) |
| `ContentView.swift` | Main UI: sidebar, editor, tutorial, canvas logic |
| `MetalView.swift` | NSViewRepresentable bridge (SwiftUI ↔ MTKView) |
| `MetalRenderer.swift` | Metal rendering engine (MTKViewDelegate) |
| `SharedTypes.swift` | Data models, UTType, notification names |
| `ShaderSnippets.swift` | Shader source: defaults, demos, templates, presets |
| `TutorialData.swift` | 9-step tutorial content |
| `AIService.swift` | AI chat & tutorial generation (actor) |
| `AIChatView.swift` | AI chat UI + tutorial prompt |
| `AISettings.swift` | AI provider config (Observable, UserDefaults) |
| `Localizable.xcstrings` | String catalog (en / zh-Hans / ja) |
| `Info.plist` | UTType export for `.shadercanvas` |
| `Assets.xcassets/` | App icon, accent color |

For deeper technical details, see the architecture docs:

- [Architecture (English)](ARCHITECTURE.md)
- [架构文档 (简体中文)](ARCHITECTURE_CN.md)

---

## Architecture Overview

The app follows a clear two-layer design: a **SwiftUI frontend** for all user interaction, and a **Metal backend** that handles GPU rendering.

```
┌─────────────────────────────────────────────────────────────┐
│                    SwiftUI Frontend                          │
│                                                             │
│  macOSShaderCanvasApp ──(NotificationCenter)──► ContentView │
│                                                    │        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │        │
│  │ Layer Sidebar │  │ Shader Editor│  │ Tutorial │ │        │
│  │  (add/remove) │  │ (code + UI)  │  │  Panel   │ │        │
│  └──────────────┘  └──────────────┘  └──────────┘ │        │
│                                                    │        │
│  @State activeShaders, meshType, backgroundImage   │        │
│                         │                                   │
│                         ▼                                   │
│               MetalView (NSViewRepresentable)               │
│            ┌────────────┴────────────┐                      │
│            │   bridges SwiftUI props │                      │
│            │   to MetalRenderer      │                      │
│            └────────────┬────────────┘                      │
└─────────────────────────┼───────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│                    Metal Backend                             │
│                          ▼                                   │
│               MetalRenderer (MTKViewDelegate)                │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              GPU Pipeline Management                 │    │
│  │                                                     │    │
│  │  meshPipelineState ◄── compileMeshPipeline()        │    │
│  │  fullscreenPipelineStates ◄── compileFullscreen...()│    │
│  │  bgBlitPipelineState ◄── compileBgBlitPipeline()    │    │
│  │  blitPipelineState ◄── compileBlitPipeline()        │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Multi-Pass draw(in:)                    │    │
│  │                                                     │    │
│  │  PASS 1 ─► Background + Mesh ─► offscreenTextureA   │    │
│  │  PASS 2..N ─► Post-Processing (ping-pong A↔B)       │    │
│  │  PASS FINAL ─► Blit to screen drawable               │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ MTLDevice    │  │ MTLTexture   │  │ MTKMesh          │  │
│  │ MTLQueue     │  │ (offscreen)  │  │ (ModelIO)        │  │
│  │ MTLLibrary   │  │ (background) │  │                  │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### 1. SwiftUI → MetalView → MetalRenderer

All rendering state lives as `@State` properties in `ContentView`:

| Property | Type | Purpose |
|----------|------|---------|
| `activeShaders` | `[ActiveShader]` | Ordered list of shader layers |
| `meshType` | `MeshType` | Current mesh (sphere/cube/custom) |
| `backgroundImage` | `NSImage?` | Optional scene backdrop |

These are passed as props to `MetalView`, a `NSViewRepresentable` that wraps `MTKView`. On every SwiftUI state change, `updateNSView` is called:

```swift
func updateNSView(_ nsView: MTKView, context: Context) {
    renderer.currentMeshType = meshType
    renderer.updateShaders(activeShaders, in: nsView)
    renderer.loadBackgroundImage(backgroundImage)
}
```

### 2. Shader Compilation (CPU → GPU)

`MetalRenderer.updateShaders()` diffs the old and new shader arrays. If code changed:

```
activeShaders (SwiftUI state)
       │
       ├── vertex/fragment code changed?
       │       └── compileMeshPipeline()
       │               ├── device.makeLibrary(source:) → MTLLibrary
       │               ├── lib.makeFunction(name: "vertex_main") → MTLFunction
       │               ├── lib.makeFunction(name: "fragment_main") → MTLFunction
       │               └── device.makeRenderPipelineState() → MTLRenderPipelineState
       │
       └── fullscreen code changed?
               └── compileFullscreenPipelines()
                       └── (one pipeline per fullscreen shader, keyed by UUID)
```

Shaders are compiled from source strings at runtime using `MTLDevice.makeLibrary(source:options:)`. This enables the live-editing workflow — the user types MSL code, and it's recompiled on the next frame update.

### 3. Multi-Pass Rendering (GPU)

Every frame, `draw(in:)` executes a multi-pass pipeline:

```
PASS 1: Base Mesh → offscreenTextureA
─────────────────────────────────────
• RenderPassDescriptor clears texA to dark gray
• If backgroundTexture exists:
    → Draw fullscreen triangle with bgBlitPipelineState
    → Background image fills the framebuffer
• If meshPipelineState + mesh exist:
    → Compute MVP matrix (perspective × view × rotation)
    → Bind Uniforms buffer (MVP + time) at index 1
    → Draw mesh submeshes with indexed primitives
    → Depth testing via depthTexture (.depth32Float)

PASS 2..N: Post-Processing (Ping-Pong)
──────────────────────────────────────
• For each fullscreen shader in layer order:
    → Source = currentSourceTex, Destination = currentDestTex
    → Bind source texture at [[texture(0)]]
    → Bind Uniforms (time) at [[buffer(1)]]
    → Draw fullscreen triangle (3 vertices, no mesh)
    → Swap source ↔ destination for next pass
• Ping-pong between offscreenTextureA and offscreenTextureB

PASS FINAL: Blit to Screen
──────────────────────────
• Render currentSourceTex onto view.currentDrawable
• Uses blitPipelineState (simple texture sampler)
• Result displayed on screen
```

### Offscreen Resources

| Resource | Format | Purpose |
|----------|--------|---------|
| `offscreenTextureA` | `.bgra8Unorm` | Primary render target / ping-pong buffer |
| `offscreenTextureB` | `.bgra8Unorm` | Secondary ping-pong buffer |
| `depthTexture` | `.depth32Float` | Depth buffer for mesh pass |
| `backgroundTexture` | `.bgra8Unorm` | User-uploaded background image |

All offscreen textures are recreated on `drawableSizeWillChange` to match the viewport.

---

## Metal API Usage Summary

| Metal API | Where Used | Purpose |
|-----------|-----------|---------|
| `MTLDevice` | MetalRenderer | GPU device handle |
| `MTLCommandQueue` | MetalRenderer | Serializes command buffers |
| `MTLCommandBuffer` | draw() | One per frame, batches all passes |
| `MTLRenderCommandEncoder` | draw() | Encodes draw calls for each pass |
| `MTLRenderPipelineState` | compile*() | Pre-compiled vertex+fragment combo |
| `MTLDepthStencilState` | init | Depth test config (less, write enabled) |
| `MTLLibrary` | compile*() | Compiled MSL source |
| `MTLFunction` | compile*() | Named shader entry point |
| `MTLTexture` | setupOffscreenTextures | Render targets |
| `MTKTextureLoader` | loadBackgroundImage | Image → GPU texture |
| `MTKMesh` / `MDLMesh` | setupMesh | Mesh geometry from ModelIO |

### Shader Entry Points Convention

All shaders in this project use a consistent naming convention:

- **`vertex_main`** — vertex shader entry point (`[[stage_in]]` + `[[buffer(1)]]`)
- **`fragment_main`** — fragment shader entry point (`[[stage_in]]` + optional `[[texture(0)]]`)

The Uniforms struct is always bound at buffer index 1:

```metal
struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float time;
};
```

---

## Data Models (`SharedTypes.swift`)

| Type | Fields | Purpose |
|------|--------|---------|
| `ShaderCategory` | `.vertex` / `.fragment` / `.fullscreen` | Shader type enum |
| `MeshType` | `.sphere` / `.cube` / `.custom(URL)` | Mesh source |
| `ActiveShader` | `id`, `category`, `name`, `code` | One shader layer |
| `CanvasDocument` | `name`, `meshType`, `shaders` | Serializable workspace |

### Menu → View Communication

Menu commands in `macOSShaderCanvasApp` post notifications; `ContentView` subscribes:

```
File Menu ──post──► NSNotification.Name ──onReceive──► ContentView
  New Canvas           .canvasNew                       showNewCanvasConfirm
  Open...              .canvasOpen                      performOpen()
  Save                 .canvasSave                      performSave()
  Save As...           .canvasSaveAs                    performSaveAs()
  Tutorial             .canvasTutorial                  startTutorial()
```

---

## Canvas Persistence

Workspaces are saved as `.shadercanvas` files (JSON via `Codable`):

```json
{
  "name": "My Canvas",
  "meshType": { "type": "sphere" },
  "shaders": [
    {
      "id": "...",
      "category": "Fragment",
      "name": "Fragment Layer 1",
      "code": "#include <metal_stdlib>\n..."
    }
  ]
}
```

The custom UTType `com.linghent.shadercanvas` is declared in `Info.plist`.

---

## Tutorial System

The built-in tutorial (`TutorialData.swift`) provides 9 progressive lessons:

| # | Topic | Shader Type |
|---|-------|-------------|
| 1 | Solid Color Output | Fragment |
| 2 | Normal Visualization | Fragment |
| 3 | Lambert Diffuse Lighting | Fragment |
| 4 | Blinn-Phong Specular | Fragment |
| 5 | Time-Based Animation | Fragment |
| 6 | Vertex Displacement | Vertex |
| 7 | Fresnel Rim Effect | Fragment |
| 8 | Fullscreen Vignette | Fullscreen |
| 9 | Combined Challenge | Fragment |

Each step includes starter code, solution code, instructions, goals, and hints. Accessed via **File → Tutorial** (⇧⌘T).

---

## Contributing

Contributions are welcome. Whether you're fixing a bug, adding a shader preset, improving docs, or localizing strings — every contribution helps.

1. **Fork** the repository and create a branch for your change.
2. **Make your changes** — follow existing code style and conventions.
3. **Test** — ensure the app builds and runs correctly.
4. **Submit a pull request** with a clear description of what you changed and why.

Ideas for contributions:

- New fragment or post-processing presets
- Additional mesh presets or sample models
- Localization (new languages or improvements)
- Documentation improvements
- Bug fixes and performance optimizations

---

## Disclaimer

> **AI-Assisted Development**: Parts of this codebase (including code, comments, and documentation) were generated or refined with the assistance of AI tools. While the code has been reviewed and tested, AI-generated content may contain inaccuracies, suboptimal patterns, or subtle errors. **Please review carefully before using in production or relying on it for learning.** If you find any issues, contributions and corrections are very welcome.

---

## License

This project is for educational purposes.
