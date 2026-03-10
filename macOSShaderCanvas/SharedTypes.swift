//
//  SharedTypes.swift
//  macOSShaderCanvas
//
//  Shared data models and type definitions used across the entire application.
//
//  This file contains:
//  1. Custom UTType for .shadercanvas file format
//  2. ShaderCategory enum (vertex / fragment / fullscreen)
//  3. MeshType enum (sphere / cube / custom URL) with Codable support
//  4. ActiveShader model (one shader layer in the workspace)
//  5. DataFlowConfig (configurable vertex data fields)
//  6. CanvasDocument model (serializable workspace state)
//  7. NotificationCenter names for menu → view communication
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
struct ActiveShader: Identifiable, Codable {
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

/// Fixed-layout uniform buffer passed to all mesh shaders each frame.
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
    var _pad0: Float = 0
    var _pad1: Float = 0
    var _pad2: Float = 0
}

// MARK: - Canvas Document

/// The top-level serializable workspace state.
///
/// Saved as JSON to .shadercanvas files. Contains the canvas name,
/// mesh type, all shader layers, and the Data Flow configuration.
struct CanvasDocument: Codable {
    var name: String
    var meshType: MeshType
    var shaders: [ActiveShader]
    var dataFlow: DataFlowConfig
    var paramValues: [String: [Float]]
    
    init(name: String, meshType: MeshType, shaders: [ActiveShader], dataFlow: DataFlowConfig = DataFlowConfig(), paramValues: [String: [Float]] = [:]) {
        self.name = name
        self.meshType = meshType
        self.shaders = shaders
        self.dataFlow = dataFlow
        self.paramValues = paramValues
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        meshType = try container.decode(MeshType.self, forKey: .meshType)
        shaders = try container.decode([ActiveShader].self, forKey: .shaders)
        dataFlow = try container.decodeIfPresent(DataFlowConfig.self, forKey: .dataFlow) ?? DataFlowConfig()
        paramValues = try container.decodeIfPresent([String: [Float]].self, forKey: .paramValues) ?? [:]
    }
}

// MARK: - AI Agent Types

/// The type of action the AI Agent can perform on the workspace.
enum AgentActionType: String, Codable {
    case addLayer
    case modifyLayer
}

/// A single action the AI Agent wants to perform on the shader workspace.
///
/// For `addLayer`: creates a new shader layer with the given category, name, and code.
/// For `modifyLayer`: replaces the code of an existing layer identified by `targetLayerName`.
struct AgentAction: Codable {
    let type: AgentActionType
    let category: String
    let name: String
    let code: String
    let targetLayerName: String?

    var shaderCategory: ShaderCategory? {
        switch category.lowercased() {
        case "vertex": return .vertex
        case "fragment": return .fragment
        case "fullscreen": return .fullscreen
        default: return nil
        }
    }

    init(type: AgentActionType, category: String, name: String, code: String, targetLayerName: String? = nil) {
        self.type = type
        self.category = category
        self.name = name
        self.code = code
        self.targetLayerName = targetLayerName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(AgentActionType.self, forKey: .type)
        category = try container.decode(String.self, forKey: .category)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        code = try container.decode(String.self, forKey: .code)
        targetLayerName = try container.decodeIfPresent(String.self, forKey: .targetLayerName)
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

    static func plainText(_ text: String) -> AgentResponse {
        AgentResponse(canFulfill: true, explanation: text, actions: [], barriers: nil)
    }

    init(canFulfill: Bool, explanation: String, actions: [AgentAction], barriers: [String]?) {
        self.canFulfill = canFulfill
        self.explanation = explanation
        self.actions = actions
        self.barriers = barriers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canFulfill = try container.decodeIfPresent(Bool.self, forKey: .canFulfill) ?? true
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        actions = try container.decodeIfPresent([AgentAction].self, forKey: .actions) ?? []
        barriers = try container.decodeIfPresent([String].self, forKey: .barriers)
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
}
