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

    /// Result of executing agent actions, including any pending shape lock
    /// requests that require user confirmation before taking effect.
    struct ExecutionResult {
        var firstShaderID: UUID?
        var firstObjectID: UUID?
        var shapeLockRequests: [(objectName: String, explanation: String)] = []
    }

    /// Applies a list of AI-generated agent actions to the mutable canvas state.
    ///
    /// - `requestShapeLock` actions are collected in `shapeLockRequests` for user
    ///   confirmation.
    /// - When `usePreviewClone` is `true` and the action is `setObjectShader2D`
    ///   targeting an existing user object, a non-destructive clone is created
    ///   instead of overwriting the user's code.  Subsequent shader writes to
    ///   the same target reuse the existing clone.
    @discardableResult
    static func executeAgentActions(
        _ actions: [AgentAction],
        activeShaders: inout [ActiveShader],
        objects2D: inout [Object2D],
        sharedVertexCode2D: inout String,
        sharedFragmentCode2D: inout String,
        usePreviewClone: Bool = false,
        approvedShapeLocks: inout Set<String>
    ) -> ExecutionResult {
        var result = ExecutionResult()

        for action in actions {
            switch action.type {
            case .addLayer:
                guard let category = action.shaderCategory else { continue }
                let shader = ActiveShader(category: category, name: action.name, code: action.code)
                activeShaders.append(shader)
                if result.firstShaderID == nil { result.firstShaderID = shader.id }

            case .modifyLayer:
                if let targetName = action.targetLayerName,
                   let index = activeShaders.firstIndex(where: { $0.name == targetName }) {
                    activeShaders[index].code = action.code
                    if !action.name.isEmpty && action.name != "Untitled" {
                        activeShaders[index].name = action.name
                    }
                    if result.firstShaderID == nil { result.firstShaderID = activeShaders[index].id }
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
                if result.firstObjectID == nil { result.firstObjectID = obj.id }

            case .modifyObject2D:
                let targetName = action.targetObjectName ?? action.name
                if let index = objects2D.firstIndex(where: { $0.name == targetName }) {
                    if usePreviewClone && !objects2D[index].isAIPreview {
                        print("[CanvasActions] Blocked modifyObject2D on user object \"\(targetName)\"")
                        continue
                    }
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
                    if result.firstObjectID == nil { result.firstObjectID = objects2D[index].id }
                }

            case .setSharedShader2D:
                if usePreviewClone {
                    print("[CanvasActions] Blocked setSharedShader2D in preview-clone mode")
                    continue
                }
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
                applyObjectShader2D(
                    action: action, targetName: targetName,
                    objects2D: &objects2D, result: &result,
                    usePreviewClone: usePreviewClone,
                    approvedShapeLocks: &approvedShapeLocks
                )

            case .requestShapeLock:
                let targetName = action.targetObjectName ?? action.name
                result.shapeLockRequests.append((objectName: targetName, explanation: action.name))
            }
        }

        sortShadersByCategory(&activeShaders)
        return result
    }

    // MARK: - Preview Clone Logic

    /// Resolves `targetName` to the canonical user object name.
    /// Handles both "Object 1" and "AI: Object 1" / "AI: Object 1 v2" etc.
    private static func canonicalUserObjectName(_ targetName: String) -> String {
        var name = targetName
        if name.hasPrefix("AI: ") { name = String(name.dropFirst(4)) }
        if let range = name.range(of: #" v\d+$"#, options: .regularExpression) {
            name = String(name[name.startIndex..<range.lowerBound])
        }
        return name
    }

    private static func applyObjectShader2D(
        action: AgentAction, targetName: String,
        objects2D: inout [Object2D], result: inout ExecutionResult,
        usePreviewClone: Bool,
        approvedShapeLocks: inout Set<String>
    ) {
        let userObjName = canonicalUserObjectName(targetName)

        guard usePreviewClone else {
            if let idx = objects2D.firstIndex(where: { $0.name == targetName }) {
                applyShaderCode(action: action, to: &objects2D[idx])
                if result.firstObjectID == nil { result.firstObjectID = objects2D[idx].id }
            }
            return
        }

        guard let userIdx = objects2D.firstIndex(where: { $0.name == userObjName && !$0.isAIPreview }) else { return }
        let userObj = objects2D[userIdx]

        let existingPreviews = objects2D.filter {
            $0.isAIPreview && $0.sourceObjectID == userObj.id
        }
        let source = existingPreviews.last ?? userObj

        let version = existingPreviews.count + 1
        let cloneName = version == 1 ? "AI: \(userObjName)" : "AI: \(userObjName) v\(version)"

        let xOffset: Float = source.isAIPreview
            ? 0.02
            : source.scaleW + 0.05
        let shouldLock = approvedShapeLocks.contains(userObjName)

        var clone = Object2D(
            id: UUID(), name: cloneName, shapeType: source.shapeType,
            posX: source.posX + xOffset, posY: source.posY,
            scaleW: source.scaleW, scaleH: source.scaleH,
            rotation: source.rotation, cornerRadius: source.cornerRadius,
            customVertexCode: source.customVertexCode,
            customFragmentCode: source.customFragmentCode,
            shapeLocked: shouldLock || source.shapeLocked,
            isAIPreview: true, sourceObjectID: userObj.id
        )
        if shouldLock { approvedShapeLocks.remove(userObjName) }
        applyShaderCode(action: action, to: &clone)
        objects2D.append(clone)
        if result.firstObjectID == nil { result.firstObjectID = clone.id }
    }

    private static func applyShaderCode(action: AgentAction, to object: inout Object2D) {
        switch action.category.lowercased() {
        case "distortion", "vertex":
            object.customVertexCode = action.code.isEmpty ? nil : action.code
        case "fragment":
            object.customFragmentCode = action.code.isEmpty ? nil : action.code
        default:
            break
        }
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
