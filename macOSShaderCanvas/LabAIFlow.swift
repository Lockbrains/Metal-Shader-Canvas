//
//  LabAIFlow.swift
//  macOSShaderCanvas
//
//  AI conversation controller for Lab mode. Manages phase-specific system prompts
//  and routes Lab interactions through the existing AIService infrastructure.
//
//  Each Lab phase gets a tailored system prompt:
//  - Reference Analysis: multimodal analysis of visual references
//  - Q&A: structured question generation based on analysis
//  - Document Drafting: project spec generation
//  - Implementation: shader code generation (reuses Canvas agent)
//  - Tuning: parameter evaluation with render context
//  - Adversarial: alternative proposals with rationale
//

import Foundation

// MARK: - LabAIFlow

enum LabAIFlow {

    /// Sends a message within the Lab workflow, selecting the appropriate system prompt
    /// based on the current phase and building Lab-specific context.
    static func sendMessage(
        text: String,
        phase: LabPhase,
        references: [ReferenceItem],
        projectDocument: ProjectDocument,
        activeShaders: [ActiveShader],
        canvasMode: CanvasMode,
        dataFlowConfig: DataFlowConfig,
        dataFlow2DConfig: DataFlow2DConfig,
        objects2D: [Object2D],
        sharedVertexCode2D: String,
        sharedFragmentCode2D: String,
        paramValues: [String: [Float]],
        meshType: MeshType,
        chatHistory: [ChatMessage],
        settings: AISettings,
        imageData: Data? = nil
    ) async throws -> AgentResponse {
        let context = buildLabContext(
            phase: phase, references: references, projectDocument: projectDocument,
            activeShaders: activeShaders, canvasMode: canvasMode,
            dataFlowConfig: dataFlowConfig, dataFlow2DConfig: dataFlow2DConfig,
            objects2D: objects2D, sharedVertexCode2D: sharedVertexCode2D,
            sharedFragmentCode2D: sharedFragmentCode2D,
            paramValues: paramValues, meshType: meshType
        )

        let systemPrompt = buildPhasePrompt(phase: phase, context: context)

        switch phase {
        case .implementation:
            return try await AIService.shared.agentChat(
                messages: chatHistory + [ChatMessage(role: .user, content: text)],
                context: context,
                dataFlowDescription: buildDataFlowDescription(canvasMode: canvasMode, config3D: dataFlowConfig, config2D: dataFlow2DConfig),
                canvasMode: canvasMode,
                settings: settings,
                imageData: imageData
            )
        default:
            return try await sendLabChat(
                system: systemPrompt,
                userMessage: text,
                chatHistory: chatHistory,
                settings: settings,
                imageData: imageData
            )
        }
    }

    // MARK: - Phase-Specific Prompts

    private static func buildPhasePrompt(phase: LabPhase, context: String) -> String {
        let baseRole = """
        You are an expert shader development collaborator in a Lab environment. \
        You work alongside the human artist/developer to create beautiful and performant shaders. \
        The human provides aesthetic direction and visual references; you provide technical expertise, \
        stability, and performance optimization.
        """

        switch phase {
        case .referenceInput, .analysis:
            return """
            \(baseRole)

            CURRENT PHASE: Reference Analysis
            Your task is to analyze the visual references and text descriptions provided by the user. \
            Based on your analysis:
            1. Describe what you see in technical shader terms (noise patterns, color gradients, \
               blending modes, temporal behavior, etc.)
            2. Identify the key visual features that need to be reproduced
            3. Ask 2-4 specific technical questions to clarify the user's intent, such as:
               - "Should the edge dissolution use noise-based erosion or SDF-based distance?"
               - "What frame rate / performance target should we aim for?"
               - "Is the color palette fixed or should it be parameterized?"
            4. Suggest an initial technical approach

            Respond in natural language (NOT JSON). Be collaborative and ask questions.

            WORKSPACE CONTEXT:
            \(context)
            """

        case .documentDrafting:
            return """
            \(baseRole)

            CURRENT PHASE: Project Document Drafting
            Based on the discussion so far, help draft or refine the Project Document. \
            The document should cover:
            - Visual Goal: what the shader should look like
            - Technical Approach: algorithms, noise functions, blending techniques
            - Parameter Design: what parameters to expose and their ranges
            - Constraints: performance limits, platform requirements

            If the user asks you to generate a document section, provide it clearly. \
            If the user provides feedback, suggest revisions.

            Respond in natural language (NOT JSON). Be structured and specific.

            WORKSPACE CONTEXT:
            \(context)
            """

        case .implementation:
            return """
            \(baseRole)

            CURRENT PHASE: Implementation
            Write Metal Shading Language (MSL) code based on the Project Document. \
            Expose parameters using // @param directives for real-time tuning.

            \(context)
            """

        case .tuning:
            return """
            \(baseRole)

            CURRENT PHASE: Parameter Tuning (Engineering Haptics)
            You are observing the user's parameter adjustments. Based on the current render state \
            and parameter values:
            1. Identify any visual artifacts or issues
            2. Suggest specific parameter adjustments with rationale
            3. Point out diminishing returns or saturation points
            4. Flag any performance concerns
            5. Note parameter interdependencies

            Think of yourself as providing "tactile feedback" — helping the user feel the effect \
            of each parameter change. Be specific with numbers and directions.

            Respond in natural language (NOT JSON). Be precise and actionable.

            WORKSPACE CONTEXT:
            \(context)
            """

        case .adversarial:
            return """
            \(baseRole)

            CURRENT PHASE: Adversarial Generation
            Your role now shifts to creative challenger. Propose alternative approaches that might \
            improve the shader:
            1. Suggest alternative noise functions, blending modes, or algorithms
            2. Propose parameter value changes with visual rationale
            3. Challenge the current approach if you see potential improvements
            4. Provide A/B comparison reasoning

            Be constructive but bold. The user will accept, reject, or partially adopt your proposals.

            Respond in natural language (NOT JSON). Structure proposals clearly.

            WORKSPACE CONTEXT:
            \(context)
            """
        }
    }

    // MARK: - Lab Context Builder

    private static func buildLabContext(
        phase: LabPhase, references: [ReferenceItem], projectDocument: ProjectDocument,
        activeShaders: [ActiveShader], canvasMode: CanvasMode,
        dataFlowConfig: DataFlowConfig, dataFlow2DConfig: DataFlow2DConfig,
        objects2D: [Object2D], sharedVertexCode2D: String, sharedFragmentCode2D: String,
        paramValues: [String: [Float]], meshType: MeshType
    ) -> String {
        var ctx = "Mode: \(canvasMode.rawValue)\n"

        if !references.isEmpty {
            ctx += "\n--- REFERENCES ---\n"
            for ref in references {
                ctx += "[\(ref.type.rawValue)] "
                if let name = ref.originalFilename { ctx += name + " " }
                if !ref.annotation.isEmpty { ctx += "— \(ref.annotation) " }
                if let text = ref.textContent { ctx += "\"\(text)\" " }
                ctx += "\n"
            }
        }

        if !projectDocument.isEmpty {
            ctx += "\n--- PROJECT DOCUMENT ---\n"
            if !projectDocument.visualGoal.isEmpty { ctx += "Visual Goal: \(projectDocument.visualGoal)\n" }
            if !projectDocument.technicalApproach.isEmpty { ctx += "Technical Approach: \(projectDocument.technicalApproach)\n" }
            if !projectDocument.parameterDesign.isEmpty {
                ctx += "Designed Parameters:\n"
                for p in projectDocument.parameterDesign {
                    ctx += "  - \(p.name) (\(p.type.rawValue)): \(p.purpose)\n"
                }
            }
            if !projectDocument.constraints.isEmpty {
                ctx += "Constraints: \(projectDocument.constraints.joined(separator: ", "))\n"
            }
        }

        if !activeShaders.isEmpty {
            ctx += "\n--- ACTIVE SHADERS ---\n"
            for shader in activeShaders {
                ctx += "[\(shader.category.rawValue)] \(shader.name): \(shader.code.count) chars\n"
                if phase == .tuning || phase == .adversarial || phase == .implementation {
                    ctx += shader.code + "\n"
                }
            }
        }

        if !paramValues.isEmpty && (phase == .tuning || phase == .adversarial) {
            ctx += "\n--- CURRENT PARAMETERS ---\n"
            for (name, values) in paramValues.sorted(by: { $0.key < $1.key }) {
                ctx += "\(name) = \(values.map { String(format: "%.3f", $0) }.joined(separator: ", "))\n"
            }
        }

        if canvasMode.is3D {
            ctx += "\nMesh: \(meshType == .sphere ? "sphere" : meshType == .cube ? "cube" : "custom")\n"
        }

        return ctx
    }

    // MARK: - Data Flow Description

    private static func buildDataFlowDescription(canvasMode: CanvasMode, config3D: DataFlowConfig, config2D: DataFlow2DConfig) -> String {
        if canvasMode.is2D {
            return "2D DataFlow: time=\(config2D.timeEnabled ? "ON" : "OFF") mouse=\(config2D.mouseEnabled ? "ON" : "OFF")"
        }
        return "3D DataFlow: normal=\(config3D.normalEnabled ? "ON" : "OFF") uv=\(config3D.uvEnabled ? "ON" : "OFF") time=\(config3D.timeEnabled ? "ON" : "OFF")"
    }

    // MARK: - Generic Lab Chat (non-implementation phases)

    private static func sendLabChat(
        system: String, userMessage: String,
        chatHistory: [ChatMessage], settings: AISettings,
        imageData: Data?
    ) async throws -> AgentResponse {
        let messages = chatHistory + [ChatMessage(role: .user, content: userMessage)]
        let rawResponse: String
        switch settings.selectedProvider {
        case .openai:
            rawResponse = try await AIService.shared.callOpenAI(
                system: system, messages: messages, settings: settings, imageData: imageData)
        case .anthropic:
            rawResponse = try await AIService.shared.callAnthropic(
                system: system, messages: messages, settings: settings, imageData: imageData)
        case .gemini:
            rawResponse = try await AIService.shared.callGemini(
                system: system, messages: messages, settings: settings, imageData: imageData)
        }
        return AgentResponse.plainText(rawResponse)
    }

    // MARK: - Reference Analysis

    /// Analyzes reference items by sending image data to a multimodal model.
    static func analyzeReferences(_ references: [ReferenceItem], settings: AISettings) async throws -> String {
        let imageRefs = references.filter { $0.type == .image || $0.type == .gif }
        guard let firstImage = imageRefs.first?.mediaData else {
            return "No image references to analyze."
        }

        let prompt = """
        Analyze this visual reference for shader development. Describe:
        1. The visual techniques used (gradients, noise, particles, etc.)
        2. Color palette and transitions
        3. Motion/temporal behavior if apparent
        4. Suggested MSL implementation approach
        """

        let msg = ChatMessage(role: .user, content: prompt)
        let rawResponse: String
        switch settings.selectedProvider {
        case .openai:
            rawResponse = try await AIService.shared.callOpenAI(
                system: "You are a shader development visual analyst.", messages: [msg],
                settings: settings, imageData: firstImage)
        case .anthropic:
            rawResponse = try await AIService.shared.callAnthropic(
                system: "You are a shader development visual analyst.", messages: [msg],
                settings: settings, imageData: firstImage)
        case .gemini:
            rawResponse = try await AIService.shared.callGemini(
                system: "You are a shader development visual analyst.", messages: [msg],
                settings: settings, imageData: firstImage)
        }
        return rawResponse
    }

    // MARK: - Adversarial Proposal

    /// Generates an adversarial alternative proposal for the current shader state.
    static func proposeAlternative(
        currentCode: String, paramValues: [String: [Float]],
        projectDocument: ProjectDocument, settings: AISettings,
        renderCapture: Data? = nil
    ) async throws -> AdversarialProposal {
        let prompt = """
        You are reviewing a shader implementation. Propose ONE specific alternative that could improve it.

        Current shader code:
        \(currentCode)

        Current parameters:
        \(paramValues.map { "\($0.key) = \($0.value)" }.joined(separator: "\n"))

        Project goal: \(projectDocument.visualGoal)

        Respond with:
        1. DESCRIPTION: What you propose to change
        2. RATIONALE: Why this would be better
        3. PARAM_CHANGES: Suggested parameter value changes (if any)
        """

        let msg = ChatMessage(role: .user, content: prompt)
        let rawResponse: String
        switch settings.selectedProvider {
        case .openai:
            rawResponse = try await AIService.shared.callOpenAI(
                system: "You are an adversarial shader reviewer.", messages: [msg],
                settings: settings, imageData: renderCapture)
        case .anthropic:
            rawResponse = try await AIService.shared.callAnthropic(
                system: "You are an adversarial shader reviewer.", messages: [msg],
                settings: settings, imageData: renderCapture)
        case .gemini:
            rawResponse = try await AIService.shared.callGemini(
                system: "You are an adversarial shader reviewer.", messages: [msg],
                settings: settings, imageData: renderCapture)
        }

        return AdversarialProposal(
            description: rawResponse,
            rationale: "AI-generated alternative proposal"
        )
    }
}
