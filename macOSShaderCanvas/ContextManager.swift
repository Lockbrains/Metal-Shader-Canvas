//
//  ContextManager.swift
//  macOSShaderCanvas
//
//  Intelligent context assembly and lifecycle management for AI Agent calls.
//
//  Instead of dumping raw code into the prompt and praying the LLM figures it out,
//  ContextManager builds layered, budget-aware context packages:
//
//    L0  System prompt (fixed)
//    L1  Scene state + shader semantics (dynamic, from ShaderAnalyzer)
//    L2  Task-specific context (plan node's contextKeys)
//    L3  Conversation history summary (compressed, not raw chat log)
//
//  After each plan step completes, the manager generates a structured handoff
//  summary — not a naive truncation — so the next step receives precisely
//  the context it needs without blowing the token budget.
//

import Foundation

enum ContextManager {

    // MARK: - Token Budget

    /// Approximate token limits per model family. Conservative estimates
    /// that leave headroom for the response.
    static let modelContextWindows: [String: Int] = [
        "gpt-4.1":       128_000,  "gpt-4.1-mini":  128_000,  "gpt-4.1-nano":  128_000,
        "gpt-5.2":       256_000,  "gpt-5-mini":    256_000,   "gpt-5-nano":    128_000,
        "gpt-4o":        128_000,  "gpt-4o-mini":   128_000,   "o4-mini":       128_000,
        "claude-sonnet-4-6-20260217": 200_000,  "claude-opus-4-6-20260205": 200_000,
        "claude-sonnet-4-20250514":   200_000,  "claude-4-opus-20250514":   200_000,
        "claude-3-5-haiku-20241022":  200_000,
        "gemini-2.5-flash": 1_000_000, "gemini-2.5-pro": 1_000_000,
        "gemini-2.0-flash": 1_000_000, "gemini-3.1-pro-preview": 2_000_000,
        "gemini-3-flash-preview": 1_000_000,
    ]

    /// Reserve this many tokens for the model's response.
    private static let responseReserve = 8_192

    /// Rough chars-per-token ratio (English + code).
    private static let charsPerToken: Double = 3.5

    /// Returns the usable input token budget for a model name.
    static func tokenBudget(for model: String) -> Int {
        let window = modelContextWindows[model] ?? 128_000
        return window - responseReserve
    }

    /// Estimates token count from a string (cheap heuristic, no tokenizer needed).
    static func estimateTokens(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / charsPerToken)))
    }

    // MARK: - Layered Context Assembly

    /// Builds a complete context string within the token budget.
    ///
    /// Priority order (highest first):
    /// 1. System prompt (L0) — always included in full
    /// 2. Scene state + semantics (L1) — critical for engineering touch
    /// 3. Task-specific context (L2) — only present in plan mode
    /// 4. Conversation history (L3) — compressed to fit remaining budget
    ///
    /// Returns the assembled context and estimated token count.
    static func assemble(
        sceneContext: String,
        taskContext: String? = nil,
        conversationSummary: String? = nil,
        model: String
    ) -> (context: String, estimatedTokens: Int) {
        let budget = tokenBudget(for: model)
        var parts = [String]()
        var used = 0

        // L1: Scene state (always included, most important for engineering touch)
        let sceneTokens = estimateTokens(sceneContext)
        parts.append(sceneContext)
        used += sceneTokens

        // L2: Task context (plan mode)
        if let task = taskContext {
            let taskTokens = estimateTokens(task)
            if used + taskTokens < budget {
                parts.append("\n--- TASK CONTEXT ---\n\(task)")
                used += taskTokens
            }
        }

        // L3: History (fill remaining budget)
        if let history = conversationSummary {
            let remaining = budget - used
            let histTokens = estimateTokens(history)
            if histTokens <= remaining {
                parts.append("\n--- CONVERSATION HISTORY ---\n\(history)")
                used += histTokens
            } else {
                let charLimit = Int(Double(remaining) * charsPerToken)
                if charLimit > 100 {
                    let trimmed = String(history.suffix(charLimit))
                    parts.append("\n--- CONVERSATION HISTORY (trimmed) ---\n...\(trimmed)")
                    used += remaining
                }
            }
        }

        let assembled = parts.joined(separator: "\n\n")
        return (assembled, used)
    }

    // MARK: - Conversation Summarization

    /// Compresses a chat history into a compact summary.
    ///
    /// Rather than sending all N messages raw (which explodes the context window),
    /// this extracts the essential thread: what was asked, what was done, and what failed.
    static func summarizeHistory(_ messages: [ChatMessage], maxMessages: Int = 6) -> String {
        guard !messages.isEmpty else { return "" }

        // Keep the last `maxMessages` in full, summarize the rest
        if messages.count <= maxMessages {
            return messages.map { formatMessage($0) }.joined(separator: "\n")
        }

        let oldMessages = Array(messages.prefix(messages.count - maxMessages))
        let recentMessages = Array(messages.suffix(maxMessages))

        var summary = "=== Earlier conversation (\(oldMessages.count) messages) ===\n"
        // Extract key decisions and actions from old messages
        for msg in oldMessages {
            if msg.role == .assistant, let actions = msg.executedActions, !actions.isEmpty {
                let actionNames = actions.map { "\($0.type.rawValue): \($0.name)" }
                summary += "  AI executed: \(actionNames.joined(separator: ", "))\n"
            }
            if msg.role == .assistant, let barriers = msg.barriers, !barriers.isEmpty {
                summary += "  Barriers: \(barriers.joined(separator: "; "))\n"
            }
        }

        summary += "\n=== Recent messages ===\n"
        for msg in recentMessages {
            summary += formatMessage(msg) + "\n"
        }
        return summary
    }

    private static func formatMessage(_ msg: ChatMessage) -> String {
        let role = msg.role == .user ? "User" : "Assistant"
        let content = msg.content.prefix(500)
        return "[\(role)] \(content)"
    }

    // MARK: - Plan Step Context Handoff

    /// Generates a structured handoff summary after a plan step completes.
    ///
    /// This is the key differentiator vs naive context compression:
    /// instead of truncating old context, we explicitly capture
    /// what was done, what changed, and what the next step needs to know.
    static func buildHandoffSummary(
        completedNode: PlanNode,
        stateChanges: [String]
    ) -> String {
        var summary = "=== COMPLETED: \(completedNode.title) ===\n"
        summary += "Status: \(completedNode.status.rawValue)\n"

        if let actions = completedNode.actions, !actions.isEmpty {
            summary += "Actions taken:\n"
            for a in actions {
                summary += "  - \(a.type.rawValue): \(a.name) [\(a.category)]\n"
            }
        }

        if !stateChanges.isEmpty {
            summary += "State changes:\n"
            for change in stateChanges {
                summary += "  - \(change)\n"
            }
        }

        if !completedNode.producedContext.isEmpty {
            summary += "Produced context:\n"
            for (key, value) in completedNode.producedContext {
                summary += "  \(key): \(value.prefix(200))\n"
            }
        }

        if let error = completedNode.error {
            summary += "Error: \(error)\n"
        }

        return summary
    }

    // MARK: - Scene State Builder

    /// Builds a rich scene description integrating shader semantics.
    static func buildSceneState(
        canvasMode: CanvasMode,
        activeShaders: [ActiveShader],
        objects2D: [Object2D],
        sharedVertexCode2D: String,
        sharedFragmentCode2D: String,
        dataFlowConfig: DataFlowConfig,
        dataFlow2DConfig: DataFlow2DConfig,
        paramValues: [String: [Float]],
        compilationError: String?,
        meshType: MeshType? = nil,
        rotationAngle: Float? = nil,
        selectedObjectID: UUID? = nil,
        animationTime: Float? = nil
    ) -> String {
        var ctx = "=== SCENE STATE ===\n"
        ctx += "Mode: \(canvasMode.rawValue)"
        if canvasMode.is3D {
            if let mesh = meshType {
                switch mesh {
                case .sphere: ctx += " | Mesh: Sphere"
                case .cube:   ctx += " | Mesh: Cube"
                case .custom(let url): ctx += " | Mesh: Custom (\(url.lastPathComponent))"
                }
            }
            if let rot = rotationAngle { ctx += " | Rotation: \(String(format: "%.0f", rot))°" }
        }
        if let t = animationTime { ctx += " | AnimClock: \(String(format: "%.2f", t))s" }
        ctx += "\n"

        // Data flow summary
        if canvasMode.is3D {
            ctx += "DataFlow: normal=\(dataFlowConfig.normalEnabled ? "ON" : "OFF")"
            ctx += ", uv=\(dataFlowConfig.uvEnabled ? "ON" : "OFF")"
            ctx += ", time=\(dataFlowConfig.timeEnabled ? "ON" : "OFF")"
            ctx += ", worldPos=\(dataFlowConfig.worldPositionEnabled ? "ON" : "OFF")"
            ctx += ", worldNormal=\(dataFlowConfig.worldNormalEnabled ? "ON" : "OFF")"
            ctx += ", viewDir=\(dataFlowConfig.viewDirectionEnabled ? "ON" : "OFF")\n"
        } else {
            ctx += "DataFlow2D: time=\(dataFlow2DConfig.timeEnabled ? "ON" : "OFF")"
            ctx += ", mouse=\(dataFlow2DConfig.mouseEnabled ? "ON" : "OFF")"
            ctx += ", objPos=\(dataFlow2DConfig.objectPositionEnabled ? "ON" : "OFF")"
            ctx += ", screenUV=\(dataFlow2DConfig.screenUVEnabled ? "ON" : "OFF")\n"
        }

        // Shader layers with semantic analysis
        if canvasMode.is3D {
            if activeShaders.isEmpty {
                ctx += "\nNo active shader layers.\n"
            } else {
                for (i, shader) in activeShaders.enumerated() {
                    let sem = ShaderAnalyzer.analyze(code: shader.code, category: shader.category)
                    ctx += "\n=== LAYER \(i + 1): \(shader.category.rawValue) \"\(shader.name)\" ===\n"
                    ctx += "Semantics: \(sem.summary)\n"
                    ctx += "Complexity: \(sem.complexity.rawValue) (\(sem.lineCount) lines)\n"
                    if let temporal = sem.temporalBehavior {
                        ctx += "Temporal: \(temporal)\n"
                    }
                    if !sem.usedUniforms.isEmpty {
                        ctx += "Uses: \(sem.usedUniforms.joined(separator: ", "))\n"
                    }
                    let paramUniforms = sem.usedUniforms.filter { $0.hasPrefix("param:") }
                    for pu in paramUniforms {
                        let pName = String(pu.dropFirst(6))
                        if let vals = paramValues[pName] {
                            ctx += "  \(pName) = \(vals.map { String(format: "%.2f", $0) }.joined(separator: ", "))\n"
                        }
                    }
                    ctx += "Code:\n\(shader.code)\n"
                }
            }
        } else {
            // 2D mode
            let selectedObj = objects2D.first { $0.id == selectedObjectID }

            if objects2D.isEmpty {
                ctx += "\nNo 2D objects on canvas.\n"
            } else {
                let userObjects = objects2D.filter { !$0.isAIPreview }
                let previewObjects = objects2D.filter { $0.isAIPreview }
                ctx += "\n2D Objects (\(userObjects.count)):\n"
                for obj in userObjects {
                    let isSelected = obj.id == selectedObjectID
                    ctx += "  \(isSelected ? "▸" : "-") \"\(obj.name)\": shape=\(obj.shapeType.rawValue)"
                    if obj.shapeLocked { ctx += " [SHAPE LOCKED — SDF access enabled]" }
                    ctx += ", pos=(\(String(format: "%.2f", obj.posX)), \(String(format: "%.2f", obj.posY)))"
                    ctx += ", scale=(\(String(format: "%.2f", obj.scaleW)), \(String(format: "%.2f", obj.scaleH)))"
                    if obj.rotation != 0 { ctx += ", rot=\(String(format: "%.1f", obj.rotation))°" }
                    if obj.customVertexCode != nil { ctx += " [custom distortion]" }
                    if obj.customFragmentCode != nil { ctx += " [custom fragment]" }
                    if isSelected { ctx += " ★SELECTED" }
                    ctx += "\n"
                }
                if !previewObjects.isEmpty {
                    ctx += "\nAI Previews (pending user review, \(previewObjects.count)):\n"
                    for obj in previewObjects {
                        ctx += "  ⟐ \"\(obj.name)\": YOUR generated preview"
                        ctx += ", shape=\(obj.shapeType.rawValue)"
                        if obj.shapeLocked { ctx += " [LOCKED]" }
                        ctx += "\n"
                    }
                }
            }

            // Prominently show the selected object's full shader details
            if let sel = selectedObj {
                ctx += "\n=== SELECTED OBJECT: \"\(sel.name)\" (user is focused on this) ===\n"
                ctx += "Shape: \(sel.shapeType.rawValue)\(sel.shapeLocked ? " [LOCKED — _sdf_shape() available]" : "")\n"
                ctx += "Position: (\(String(format: "%.2f", sel.posX)), \(String(format: "%.2f", sel.posY)))\n"
                ctx += "Scale: (\(String(format: "%.2f", sel.scaleW)), \(String(format: "%.2f", sel.scaleH)))\n"
                if sel.rotation != 0 { ctx += "Rotation: \(String(format: "%.1f", sel.rotation))°\n" }
                ctx += "Corner Radius: \(String(format: "%.2f", sel.cornerRadius))\n"

                if let vs = sel.customVertexCode {
                    let vsSem = ShaderAnalyzer.analyze(code: vs, category: .vertex)
                    ctx += "\nCustom Distortion Shader:\n"
                    ctx += "Semantics: \(vsSem.summary)\n"
                    if let temporal = vsSem.temporalBehavior { ctx += "Temporal: \(temporal)\n" }
                    ctx += "Code:\n\(vs)\n"
                } else {
                    ctx += "\nDistortion: using shared shader\n"
                }

                if let fs = sel.customFragmentCode {
                    let fsSem = ShaderAnalyzer.analyze(code: fs, category: .fragment)
                    ctx += "\nCustom Fragment Shader:\n"
                    ctx += "Semantics: \(fsSem.summary)\n"
                    if let temporal = fsSem.temporalBehavior { ctx += "Temporal: \(temporal)\n" }
                    ctx += "Code:\n\(fs)\n"
                } else {
                    ctx += "\nFragment: using shared shader\n"
                }
            } else {
                ctx += "\nNo object selected. User requests apply to the shared shader or scene.\n"
            }

            let vSem = ShaderAnalyzer.analyze(code: sharedVertexCode2D, category: .vertex)
            ctx += "\n--- Shared Distortion Shader ---\n"
            ctx += "Semantics: \(vSem.summary)\n"
            if let temporal = vSem.temporalBehavior { ctx += "Temporal: \(temporal)\n" }
            ctx += "Code:\n\(sharedVertexCode2D)\n"

            let fSem = ShaderAnalyzer.analyze(code: sharedFragmentCode2D, category: .fragment)
            ctx += "\n--- Shared Fragment Shader ---\n"
            ctx += "Semantics: \(fSem.summary)\n"
            if let temporal = fSem.temporalBehavior { ctx += "Temporal: \(temporal)\n" }
            ctx += "Code:\n\(sharedFragmentCode2D)\n"

            let ppLayers = activeShaders.filter { $0.category == .fullscreen }
            if !ppLayers.isEmpty {
                ctx += "\nPost-Processing Layers (\(ppLayers.count)):\n"
                for shader in ppLayers {
                    let sem = ShaderAnalyzer.analyze(code: shader.code, category: .fullscreen)
                    ctx += "--- Fullscreen: \"\(shader.name)\" ---\n"
                    ctx += "Semantics: \(sem.summary)\n"
                    if let temporal = sem.temporalBehavior { ctx += "Temporal: \(temporal)\n" }
                    ctx += "Code:\n\(shader.code)\n\n"
                }
            }
        }

        if let error = compilationError {
            ctx += "\n⚠️ ACTIVE SHADER COMPILATION ERROR:\n\(error)\n"
        }

        ctx += "\n=== RENDER SNAPSHOT ATTACHED ===\n"

        return ctx
    }

    // MARK: - Lab Context Builder

    /// Builds an enriched context for Lab mode that includes reference summaries,
    /// project document state, parameter snapshot history, and adversarial proposal history.
    static func buildLabContext(
        phase: LabPhase,
        references: [ReferenceItem],
        projectDocument: ProjectDocument,
        parameterSnapshots: [ParameterSnapshot],
        adversarialProposals: [AdversarialProposal],
        canvasMode: CanvasMode,
        activeShaders: [ActiveShader],
        objects2D: [Object2D],
        sharedVertexCode2D: String,
        sharedFragmentCode2D: String,
        dataFlowConfig: DataFlowConfig,
        dataFlow2DConfig: DataFlow2DConfig,
        paramValues: [String: [Float]],
        compilationError: String?,
        meshType: MeshType? = nil
    ) -> String {
        var ctx = buildSceneState(
            canvasMode: canvasMode, activeShaders: activeShaders,
            objects2D: objects2D, sharedVertexCode2D: sharedVertexCode2D,
            sharedFragmentCode2D: sharedFragmentCode2D,
            dataFlowConfig: dataFlowConfig, dataFlow2DConfig: dataFlow2DConfig,
            paramValues: paramValues, compilationError: compilationError,
            meshType: meshType
        )

        ctx += "\n=== LAB CONTEXT ===\n"
        ctx += "Current Phase: \(phase.displayName)\n"

        if !references.isEmpty {
            ctx += "\nReferences (\(references.count)):\n"
            for ref in references {
                ctx += "  [\(ref.type.rawValue)]"
                if let name = ref.originalFilename { ctx += " \(name)" }
                if !ref.annotation.isEmpty { ctx += " — \(ref.annotation)" }
                if let text = ref.textContent { ctx += " \"\(String(text.prefix(100)))\"" }
                ctx += "\n"
            }
        }

        if !projectDocument.isEmpty {
            ctx += "\nProject Document:\n"
            if !projectDocument.markdown.isEmpty {
                ctx += projectDocument.markdown.prefix(2000) + "\n"
            } else {
                if !projectDocument.visualGoal.isEmpty {
                    ctx += "  Visual Goal: \(projectDocument.visualGoal)\n"
                }
                if !projectDocument.technicalApproach.isEmpty {
                    ctx += "  Technical Approach: \(projectDocument.technicalApproach)\n"
                }
                if !projectDocument.parameterDesign.isEmpty {
                    ctx += "  Parameters: \(projectDocument.parameterDesign.map(\.name).joined(separator: ", "))\n"
                }
            }
        }

        if phase == .tuning || phase == .adversarial {
            let recentSnapshots = parameterSnapshots.suffix(5)
            if !recentSnapshots.isEmpty {
                ctx += "\nRecent Parameter Snapshots (\(recentSnapshots.count)):\n"
                for snap in recentSnapshots {
                    let params = snap.paramValues.map { "\($0.key)=\($0.value.map { String(format: "%.2f", $0) }.joined(separator: ","))" }
                    ctx += "  [\(snap.date.formatted(.dateTime.hour().minute()))] \(params.joined(separator: " | "))\n"
                    if let comment = snap.aiComment { ctx += "    AI: \(comment)\n" }
                }
            }
        }

        if phase == .adversarial && !adversarialProposals.isEmpty {
            let recent = adversarialProposals.suffix(3)
            ctx += "\nRecent Proposals (\(recent.count)):\n"
            for p in recent {
                ctx += "  [\(p.outcome.rawValue)] \(String(p.description.prefix(100)))\n"
            }
        }

        return ctx
    }
}
