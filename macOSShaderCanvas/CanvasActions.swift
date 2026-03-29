//
//  CanvasActions.swift
//  macOSShaderCanvas
//
//  Shared utility functions for canvas operations used by both ContentView
//  (Canvas mode) and LabView (Lab mode). Extracts core logic so the two
//  editors don't duplicate shader management, agent action execution,
//  or document persistence code.
//

import Foundation

// MARK: - Agent Action Execution

enum CanvasActions {

    /// Applies a list of AI-generated agent actions to the mutable canvas state.
    ///
    /// Returns the IDs of the first affected shader layer and first affected 2D object
    /// so the caller can update selection/editor state accordingly.
    @discardableResult
    static func executeAgentActions(
        _ actions: [AgentAction],
        activeShaders: inout [ActiveShader],
        objects2D: inout [Object2D],
        sharedVertexCode2D: inout String,
        sharedFragmentCode2D: inout String
    ) -> (firstShaderID: UUID?, firstObjectID: UUID?) {
        var firstAffectedShaderID: UUID?
        var firstAffectedObjectID: UUID?

        for action in actions {
            switch action.type {
            case .addLayer:
                guard let category = action.shaderCategory else { continue }
                let shader = ActiveShader(category: category, name: action.name, code: action.code)
                activeShaders.append(shader)
                if firstAffectedShaderID == nil { firstAffectedShaderID = shader.id }

            case .modifyLayer:
                if let targetName = action.targetLayerName,
                   let index = activeShaders.firstIndex(where: { $0.name == targetName }) {
                    activeShaders[index].code = action.code
                    if !action.name.isEmpty && action.name != "Untitled" {
                        activeShaders[index].name = action.name
                    }
                    if firstAffectedShaderID == nil { firstAffectedShaderID = activeShaders[index].id }
                }

            case .addObject2D:
                let obj = Object2D(
                    name: action.name,
                    shapeType: action.shape2DType ?? .roundedRectangle,
                    posX: action.posX ?? 0,
                    posY: action.posY ?? 0,
                    scaleW: action.scaleW ?? 0.5,
                    scaleH: action.scaleH ?? 0.5,
                    rotation: action.rotation ?? 0,
                    cornerRadius: action.cornerRadius ?? 0.15
                )
                objects2D.append(obj)
                if firstAffectedObjectID == nil { firstAffectedObjectID = obj.id }

            case .modifyObject2D:
                let targetName = action.targetObjectName ?? action.name
                if let index = objects2D.firstIndex(where: { $0.name == targetName }) {
                    if !action.name.isEmpty && action.name != "Untitled" {
                        objects2D[index].name = action.name
                    }
                    if let shape = action.shape2DType { objects2D[index].shapeType = shape }
                    if let x = action.posX { objects2D[index].posX = x }
                    if let y = action.posY { objects2D[index].posY = y }
                    if let w = action.scaleW { objects2D[index].scaleW = w }
                    if let h = action.scaleH { objects2D[index].scaleH = h }
                    if let r = action.rotation { objects2D[index].rotation = r }
                    if let cr = action.cornerRadius { objects2D[index].cornerRadius = cr }
                    if firstAffectedObjectID == nil { firstAffectedObjectID = objects2D[index].id }
                }

            case .setSharedShader2D:
                switch action.category.lowercased() {
                case "distortion", "vertex":
                    sharedVertexCode2D = action.code
                case "fragment":
                    sharedFragmentCode2D = action.code
                default:
                    break
                }

            case .setObjectShader2D:
                let targetName = action.targetObjectName ?? action.name
                if let index = objects2D.firstIndex(where: { $0.name == targetName }) {
                    switch action.category.lowercased() {
                    case "distortion", "vertex":
                        objects2D[index].customVertexCode = action.code.isEmpty ? nil : action.code
                    case "fragment":
                        objects2D[index].customFragmentCode = action.code.isEmpty ? nil : action.code
                    default:
                        break
                    }
                    if firstAffectedObjectID == nil { firstAffectedObjectID = objects2D[index].id }
                }
            }
        }

        sortShadersByCategory(&activeShaders)
        return (firstAffectedShaderID, firstAffectedObjectID)
    }

    // MARK: - Shader Sorting

    static func sortShadersByCategory(_ shaders: inout [ActiveShader]) {
        let order: [ShaderCategory: Int] = [.vertex: 0, .fragment: 1, .fullscreen: 2]
        shaders.sort { s1, s2 in order[s1.category]! < order[s2.category]! }
    }

    // MARK: - Document Persistence

    static func buildDocument(
        name: String, mode: CanvasMode, meshType: MeshType, shape2DType: Shape2DType,
        shaders: [ActiveShader], dataFlow: DataFlowConfig, dataFlow2D: DataFlow2DConfig,
        paramValues: [String: [Float]], objects2D: [Object2D],
        sharedVertexCode2D: String, sharedFragmentCode2D: String,
        labSession: LabSession? = nil, references: [ReferenceItem]? = nil,
        projectDocument: ProjectDocument? = nil
    ) -> CanvasDocument {
        CanvasDocument(
            name: name, mode: mode, meshType: meshType, shape2DType: shape2DType,
            shaders: shaders, dataFlow: dataFlow, dataFlow2D: dataFlow2D,
            paramValues: paramValues,
            objects2D: objects2D.isEmpty ? nil : objects2D,
            sharedVertexCode2D: sharedVertexCode2D,
            sharedFragmentCode2D: sharedFragmentCode2D,
            labSession: labSession,
            references: references,
            projectDocument: projectDocument
        )
    }

    static func saveDocument(_ doc: CanvasDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        try data.write(to: url, options: .atomic)
    }

    static func loadDocument(from url: URL) throws -> CanvasDocument {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CanvasDocument.self, from: data)
    }

    // MARK: - Default Shader Code

    static func defaultShaderCode(for category: ShaderCategory, is2D: Bool, dataFlowConfig: DataFlowConfig) -> String {
        if is2D {
            switch category {
            case .vertex: return ShaderSnippets.generateVertexDemo(config: dataFlowConfig)
            case .fragment: return ShaderSnippets.fragment2DDemo
            case .fullscreen: return ShaderSnippets.fullscreenDemo
            }
        } else {
            switch category {
            case .vertex: return ShaderSnippets.generateVertexDemo(config: dataFlowConfig)
            case .fragment: return ShaderSnippets.fragmentDemo
            case .fullscreen: return ShaderSnippets.fullscreenDemo
            }
        }
    }
}
