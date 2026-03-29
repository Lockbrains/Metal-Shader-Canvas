//
//  AIService.swift
//  macOSShaderCanvas
//
//  Async networking layer for AI-powered features: shader assistance chat
//  and automated tutorial generation.
//
//  SUPPORTED PROVIDERS:
//  ────────────────────
//  • OpenAI    — GPT-4o, GPT-4.1, etc. via /v1/chat/completions
//  • Anthropic — Claude Sonnet/Opus via /v1/messages
//  • Gemini    — Gemini 2.5 Flash/Pro via generateContent
//
//  ARCHITECTURE:
//  ─────────────
//  AIService is an `actor` (not a class) for built-in thread safety.
//  All methods can be called from any thread without data races.
//  The singleton `shared` instance is used throughout the app.
//
//  Two main entry points:
//  1. chat()             — multi-turn conversation with workspace context
//  2. generateTutorial() — produces structured TutorialStep JSON
//
//  ERROR HANDLING:
//  ───────────────
//  All API errors are wrapped in the AIError enum with user-friendly messages.
//  Network errors, invalid responses, and missing API keys are handled gracefully.
//

import Foundation

/// Thread-safe AI service that handles communication with LLM APIs.
///
/// Uses Swift's `actor` model to guarantee all internal state is accessed
/// serially, eliminating data races without manual locking.
actor AIService {

    /// Singleton instance. Use `await AIService.shared.chat(...)`.
    static let shared = AIService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// Sends a chat message as an intelligent Agent that can analyze the request,
    /// decide whether it can be fulfilled by adding/modifying shader layers, and
    /// return structured actions alongside an explanation.
    ///
    /// The Agent receives the full workspace context (active shaders, data flow config)
    /// and responds with a structured `AgentResponse` containing:
    /// - An explanation in the user's language
    /// - Concrete layer operations (add/modify) if the request is achievable
    /// - Technical barriers if the request cannot be fulfilled
    ///
    /// Falls back to plain text if the model's response cannot be parsed as JSON.
    func agentChat(messages: [ChatMessage], context: String, dataFlowDescription: String, canvasMode: CanvasMode = .threeDimensional, settings: AISettings, imageData: Data? = nil) async throws -> AgentResponse {
        let systemPrompt = canvasMode.is2D
            ? build2DSystemPrompt(context: context, dataFlowDescription: dataFlowDescription)
            : build3DSystemPrompt(context: context, dataFlowDescription: dataFlowDescription)
        let rawResponse: String
        switch settings.selectedProvider {
        case .openai:   rawResponse = try await callOpenAI(system: systemPrompt, messages: messages, settings: settings, imageData: imageData)
        case .anthropic: rawResponse = try await callAnthropic(system: systemPrompt, messages: messages, settings: settings, imageData: imageData)
        case .gemini:   rawResponse = try await callGemini(system: systemPrompt, messages: messages, settings: settings, imageData: imageData)
        }
        do {
            return try parseAgentResponse(from: rawResponse)
        } catch {
            return AgentResponse.plainText(rawResponse)
        }
    }

    // MARK: - Plan Mode

    /// Generates a structured execution plan for a complex shader task.
    ///
    /// Phase 1 of Plan Mode: the AI analyzes the request and produces a task tree
    /// (as JSON) that can be reviewed before execution. Each node specifies what
    /// context it needs and what it will produce.
    func generatePlan(request: String, context: String, dataFlowDescription: String, canvasMode: CanvasMode, settings: AISettings, imageData: Data? = nil) async throws -> AgentPlan {
        let (prompt, userMsg) = buildPlanPrompt(request: request, context: context, dataFlowDescription: dataFlowDescription)
        let rawResponse: String
        switch settings.selectedProvider {
        case .openai:   rawResponse = try await callOpenAI(system: prompt, messages: [userMsg], settings: settings, imageData: imageData)
        case .anthropic: rawResponse = try await callAnthropic(system: prompt, messages: [userMsg], settings: settings, imageData: imageData)
        case .gemini:   rawResponse = try await callGemini(system: prompt, messages: [userMsg], settings: settings, imageData: imageData)
        }
        return try parsePlanResponse(from: rawResponse)
    }

    /// Streams plan generation, returning chunks as they arrive.
    func streamGeneratePlan(
        request: String, context: String, dataFlowDescription: String,
        canvasMode: CanvasMode, captured: CapturedAISettings, imageData: Data? = nil
    ) -> AsyncStream<StreamChunk> {
        let (prompt, userMsg) = buildPlanPrompt(request: request, context: context, dataFlowDescription: dataFlowDescription)
        switch captured.provider {
        case .openai:   return streamOpenAI(system: prompt, messages: [userMsg], captured: captured, imageData: imageData)
        case .anthropic: return streamAnthropic(system: prompt, messages: [userMsg], captured: captured, imageData: imageData)
        case .gemini:   return streamGemini(system: prompt, messages: [userMsg], captured: captured, imageData: imageData)
        }
    }

    /// Returns the system prompt for plan generation (used by direct SSE streaming in the view layer).
    func buildPlanSystemPrompt(request: String, context: String, dataFlowDescription: String) -> String {
        buildPlanPrompt(request: request, context: context, dataFlowDescription: dataFlowDescription).systemPrompt
    }

    /// Returns the system prompt for a plan step (used by direct SSE streaming in the view layer).
    func buildStepSystemPrompt(
        node: PlanNode, context: String, dataFlowDescription: String,
        canvasMode: CanvasMode, handoffSummary: String?
    ) -> String {
        buildPlanStepPrompt(node: node, context: context, dataFlowDescription: dataFlowDescription,
                            canvasMode: canvasMode, handoffSummary: handoffSummary).systemPrompt
    }

    private func buildPlanPrompt(request: String, context: String, dataFlowDescription: String) -> (systemPrompt: String, userMessage: ChatMessage) {
        let prompt = """
        You are a shader development planning assistant. Analyze the user's request and break it down
        into a structured execution plan.

        Output ONLY a valid JSON object with this schema:
        {
          "title": "Plan title",
          "nodes": [
            {
              "title": "Step title",
              "description": "What this step does",
              "contextKeys": ["sceneState", "shaderCode"],
              "children": []
            }
          ]
        }

        Rules:
        - Break complex requests into 2-5 atomic steps
        - Each step should be independently executable
        - Order steps by dependency (earlier steps first)
        - Children represent sub-steps that can potentially run in parallel
        - contextKeys indicate what information each step needs:
          "sceneState" = current canvas state
          "shaderCode" = specific shader layer code
          "compilationResult" = result of previous compilation
          "paramValues" = current parameter values

        CURRENT WORKSPACE:
        \(context)

        DATA FLOW:
        \(dataFlowDescription)
        """
        return (prompt, ChatMessage(role: .user, content: request))
    }

    /// Executes a single plan node, producing an AgentResponse with actions.
    func executePlanStep(node: PlanNode, context: String, dataFlowDescription: String, canvasMode: CanvasMode, settings: AISettings, handoffSummary: String? = nil, imageData: Data? = nil) async throws -> AgentResponse {
        let (prompt, userMsg) = buildPlanStepPrompt(
            node: node, context: context,
            dataFlowDescription: dataFlowDescription,
            canvasMode: canvasMode, handoffSummary: handoffSummary
        )
        let rawResponse: String
        switch settings.selectedProvider {
        case .openai:   rawResponse = try await callOpenAI(system: prompt, messages: [userMsg], settings: settings, imageData: imageData)
        case .anthropic: rawResponse = try await callAnthropic(system: prompt, messages: [userMsg], settings: settings, imageData: imageData)
        case .gemini:   rawResponse = try await callGemini(system: prompt, messages: [userMsg], settings: settings, imageData: imageData)
        }
        do {
            return try parseAgentResponse(from: rawResponse)
        } catch {
            return AgentResponse.plainText(rawResponse)
        }
    }

    /// Streams a plan step execution, returning an AsyncStream of chunks.
    func streamPlanStep(
        node: PlanNode, context: String, dataFlowDescription: String,
        canvasMode: CanvasMode, captured: CapturedAISettings,
        handoffSummary: String? = nil, imageData: Data? = nil
    ) -> AsyncStream<StreamChunk> {
        let (prompt, userMsg) = buildPlanStepPrompt(
            node: node, context: context,
            dataFlowDescription: dataFlowDescription,
            canvasMode: canvasMode, handoffSummary: handoffSummary
        )
        switch captured.provider {
        case .openai:   return streamOpenAI(system: prompt, messages: [userMsg], captured: captured, imageData: imageData)
        case .anthropic: return streamAnthropic(system: prompt, messages: [userMsg], captured: captured, imageData: imageData)
        case .gemini:   return streamGemini(system: prompt, messages: [userMsg], captured: captured, imageData: imageData)
        }
    }

    private func buildPlanStepPrompt(
        node: PlanNode, context: String, dataFlowDescription: String,
        canvasMode: CanvasMode, handoffSummary: String?
    ) -> (systemPrompt: String, userMessage: ChatMessage) {
        var stepContext = context
        if let handoff = handoffSummary {
            stepContext += "\n\n--- PREVIOUS STEP HANDOFF ---\n\(handoff)"
        }
        let base = canvasMode.is2D
            ? build2DSystemPrompt(context: stepContext, dataFlowDescription: dataFlowDescription)
            : build3DSystemPrompt(context: stepContext, dataFlowDescription: dataFlowDescription)
        let prompt = """
        \(base)

        PLAN STEP EXECUTION:
        You are executing step "\(node.title)" of a multi-step plan.
        Step description: \(node.description)
        Focus ONLY on this specific step. Do not try to accomplish the entire plan.
        """
        let msg = ChatMessage(role: .user, content: "Execute plan step: \(node.title)\n\(node.description)")
        return (prompt, msg)
    }

    /// Verifies a plan step's visual result by sending the screenshot back to the AI.
    /// Returns (passed, feedback) — if passed is false, feedback contains what's wrong.
    func verifyStepResult(
        stepTitle: String, stepDescription: String,
        screenshot: Data, context: String,
        canvasMode: CanvasMode, settings: AISettings
    ) async throws -> (passed: Bool, feedback: String) {
        let verifyPrompt = """
        You are reviewing the visual output of a shader step: "\(stepTitle)"
        Step goal: \(stepDescription)

        A screenshot of the current render is attached. Evaluate:
        1. Does the render look like what this step should produce?
        2. Are there obvious artifacts: entirely black/white screen, missing geometry, broken colors, visual glitches?
        3. A subtle imperfection is OK — only flag clear failures.

        Respond ONLY with JSON (no markdown fences):
        { "passed": true, "feedback": "Looks correct, showing XYZ effect" }
        or
        { "passed": false, "feedback": "Description of what's wrong" }

        CONTEXT:
        \(context)
        """
        let msg = ChatMessage(role: .user, content: "Verify step: \(stepTitle)")
        let rawResponse: String
        switch settings.selectedProvider {
        case .openai:   rawResponse = try await callOpenAI(system: verifyPrompt, messages: [msg], settings: settings, imageData: screenshot)
        case .anthropic: rawResponse = try await callAnthropic(system: verifyPrompt, messages: [msg], settings: settings, imageData: screenshot)
        case .gemini:   rawResponse = try await callGemini(system: verifyPrompt, messages: [msg], settings: settings, imageData: screenshot)
        }
        // Parse the JSON response
        let cleaned = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let passed = json["passed"] as? Bool {
            return (passed, json["feedback"] as? String ?? "")
        }
        // If we can't parse, treat as passed (don't block on parsing failures)
        return (true, rawResponse)
    }

    /// Parses a plan generation response into an AgentPlan.
    func parsePlanResponse(from text: String) throws -> AgentPlan {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let fencePattern = #"```(?:json)?\s*([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) {
            cleaned = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let startIdx = cleaned.firstIndex(of: "{") else {
            throw AIError.invalidResponse("No JSON object found in plan response")
        }
        var depth = 0; var inString = false; var escaped = false; var endIdx = cleaned.endIndex
        for i in cleaned.indices[startIdx...] {
            let c = cleaned[i]
            if escaped { escaped = false; continue }
            if c == "\\" && inString { escaped = true; continue }
            if c == "\"" { inString.toggle(); continue }
            if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" { depth -= 1; if depth == 0 { endIdx = cleaned.index(after: i); break } }
            }
        }

        let jsonString = String(cleaned[startIdx..<endIdx])
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AIError.invalidResponse("Failed to parse plan JSON") }

        let title = json["title"] as? String ?? "Untitled Plan"
        let rawNodes = json["nodes"] as? [[String: Any]] ?? []
        let nodes = rawNodes.map { parsePlanNode($0) }

        var plan = AgentPlan(title: title, nodes: nodes)
        plan.recalculate()
        return plan
    }

    private func parsePlanNode(_ dict: [String: Any]) -> PlanNode {
        let title = dict["title"] as? String ?? "Untitled"
        let description = dict["description"] as? String ?? ""
        let contextKeys = dict["contextKeys"] as? [String] ?? []
        let rawChildren = dict["children"] as? [[String: Any]] ?? []
        let children = rawChildren.map { parsePlanNode($0) }
        return PlanNode(title: title, description: description, children: children, contextKeys: contextKeys)
    }

    /// Generates a structured tutorial from a topic description.
    ///
    /// The AI is instructed to output a raw JSON array of tutorial steps.
    /// Each step includes starter code (with TODO markers) and a complete solution.
    /// The response is parsed into `[TutorialStep]` and loaded into the tutorial panel.
    ///
    /// - Parameters:
    ///   - topic: A natural-language description of what to teach (e.g. "Build a PBR shader").
    ///   - settings: The current AI provider configuration.
    /// - Returns: An array of `TutorialStep` objects ready for the tutorial panel.
    /// - Throws: `AIError` if the API call fails or the response cannot be parsed.
    func generateTutorial(topic: String, settings: AISettings) async throws -> [TutorialStep] {
        let systemPrompt = """
        You are a Metal Shading Language expert educator. Generate a step-by-step shader tutorial.
        Output ONLY a valid JSON array (no markdown). Each element:
        { "title","subtitle","instructions","goal","hint","category":"fragment|vertex|fullscreen","starterCode","solutionCode" }
        All shaders must compile. Include #include <metal_stdlib> and using namespace metal.
        Vertex: entry vertex_main, VertexIn attrs 0/1/2, Uniforms buffer(1). Fragment: entry fragment_main, VertexOut.
        Fullscreen: both vertex_main (fullscreen triangle) + fragment_main with inTexture [[texture(0)]].
        starterCode should have // TODO comments. Generate 3-6 progressive steps.
        """
        let userMsg = ChatMessage(role: .user, content: "Create a tutorial about: \(topic)")
        let response: String
        switch settings.selectedProvider {
        case .openai:   response = try await callOpenAI(system: systemPrompt, messages: [userMsg], settings: settings)
        case .anthropic: response = try await callAnthropic(system: systemPrompt, messages: [userMsg], settings: settings)
        case .gemini:   response = try await callGemini(system: systemPrompt, messages: [userMsg], settings: settings)
        }
        return try parseTutorialSteps(from: response)
    }

    // MARK: - System Prompt Builders

    func build3DSystemPrompt(context: String, dataFlowDescription: String) -> String {
        """
        You are a Metal Shading Language (MSL) expert assistant embedded in a real-time 3D shader editor app.
        You are an intelligent Agent that can directly add new shader layers or modify existing ones in the user's workspace.

        RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object. No markdown fences, no extra text.
        {
          "canFulfill": true/false,
          "explanation": "Your explanation to the user (same language as user)",
          "actions": [
            {
              "type": "addLayer",
              "category": "vertex|fragment|fullscreen",
              "name": "Descriptive Layer Name",
              "code": "complete compilable MSL code"
            }
          ],
          "barriers": ["technical barrier 1", "barrier 2"]
        }
        Set "barriers" to null when canFulfill is true. Set "actions" to [] when no layer changes are needed.
        For modifying existing layers, use type "modifyLayer" with additional field "targetLayerName" (exact name of the existing layer).

        CURRENT WORKSPACE (3D Mode):
        \(context)

        DATA FLOW CONFIGURATION:
        \(dataFlowDescription)

        SHADER CODE RULES:

        Vertex & Fragment shaders (mesh shaders):
        - Struct definitions (VertexIn, VertexOut, Uniforms) are AUTO-GENERATED by the Data Flow system.
        - DO NOT include #include <metal_stdlib>, using namespace metal, or struct definitions.
        - Only write the shader function(s).
        - Vertex entry: vertex VertexOut vertex_main(VertexIn in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]])
        - Fragment entry: fragment float4 fragment_main(VertexOut in [[stage_in]])
        - Available Uniforms fields: mvpMatrix (float4x4), modelMatrix (float4x4), normalMatrix (float4x4), cameraPosition (float4, xyz=world pos), time (float), mouseX (float), mouseY (float)

        Fullscreen (post-processing) shaders:
        - MUST be self-contained: include #include <metal_stdlib>, using namespace metal, and ALL struct definitions.
        - MUST define BOTH vertex_main (fullscreen triangle from vertex_id) AND fragment_main.
        - Reads previous pass via: texture2d<float> inTexture [[texture(0)]]
        - VertexOut must have: position [[position]], texCoord (float2), time (float).
        - Uniforms: { float4x4 modelViewProjectionMatrix; float time; }

        USER PARAMETERS — ALWAYS EXPOSE ADJUSTABLE VALUES:
        You MUST add // @param directives for key adjustable values in every shader you write.
        This gives users real-time UI controls (sliders, color pickers) without editing code.
        Parameter names MUST start with underscore. Types: float, float2, float3, float4, color.
        Syntax: // @param _name type default_values [min max]
        Examples:
          // @param _intensity float 0.5 0.0 1.0     → slider (0.0 to 1.0, default 0.5)
          // @param _tint color 1.0 0.5 0.2           → color picker (RGB defaults)
          // @param _offset float2 0.0 0.0            → XY input
          // @param _direction float3 0.0 1.0 0.0     → XYZ input
        The system auto-generates #define macros from @param directives.
        DO NOT manually define a Params struct. Just add // @param directives and reference names directly.
        BEST PRACTICE: For every shader, identify 2-5 key artistic parameters and expose them.
        Good candidates: intensity/strength, color/tint, frequency/scale, speed, threshold, radius, offset.
        Always provide sensible min/max ranges for float params so the slider is immediately useful.

        CAPABILITIES (canFulfill = true):
        ✓ Any shading model (Lambert, Phong, Blinn-Phong, Toon/Cel, PBR approximation, Gooch, Fresnel, etc.)
        ✓ Vertex deformations (wave, twist, inflate, morph, noise-based displacement, etc.)
        ✓ Post-processing effects (blur, bloom, vignette, color grading, edge detection, distortion, etc.)
        ✓ Chaining multiple fullscreen passes for complex effect pipelines
        ✓ Time-animated effects using uniforms.time
        ✓ Mouse-interactive effects using uniforms.mouseX/mouseY (normalized [0,1])
        ✓ Combining vertex + fragment + fullscreen layers for complete visual effects
        ✓ User-controllable parameters via @param directives (ALWAYS use these)

        LIMITATIONS (canFulfill = false, explain barriers):
        ✗ Shadow mapping — requires a separate depth-only render pass
        ✗ Screen-space reflections (SSR) — requires depth buffer texture input
        ✗ Ray tracing / path tracing — requires compute shaders or RT API
        ✗ External texture sampling — only inTexture (from previous pass) available in fullscreen
        ✗ Geometry / tessellation shaders — not available in this pipeline
        ✗ Multiple render targets (MRT) — single color attachment only
        ✗ Stencil buffer operations — not exposed in current pipeline
        ✗ Compute shaders — not in current rendering pipeline

        VISUAL FEEDBACK:
        An image may be attached. It could be an auto-captured render snapshot OR a user-provided reference image.
        For render snapshots: compare the visual result with what the shader code should produce.
        For user reference images: analyze the desired visual effect and translate it into shader techniques.
        The scene context includes AnimClock (current time in seconds) and Temporal analysis describing
        how the shader changes over time — use these to reason about dynamic behavior beyond the static frame.

        STRICTLY FORBIDDEN — NEVER HARDCODE:
        ✗ DO NOT hardcode background images, textures, or pixel data. The canvas content is dynamic.
        ✗ DO NOT hardcode specific UI element shapes, sizes, or positions in shader code.
        ✗ DO NOT hardcode viewport dimensions or assume a fixed resolution.
        ✗ DO NOT embed base64 data, bitmap patterns, or lookup tables that represent specific images.
        ✗ DO NOT write shader code that only works for one specific object shape or position.
        Shaders MUST be generic and portable — they must produce correct results on ANY shape,
        ANY size, ANY position. Use normalized coordinates (UV, screenUV) and relative values.
        The purpose of this shader canvas is prototyping effects that will be applied to arbitrary
        geometry later. If the user asks for something that seems to require hardcoding (e.g. "make it
        look like the background"), use procedural generation, bgTexture sampling, or mathematical
        approximation — NEVER pixel-level reproduction.

        IMPORTANT:
        - All generated shader code MUST compile. Verify mentally before outputting.
        - Answer in the SAME LANGUAGE the user writes in.
        - Be concise in explanations.
        - Give layers descriptive names reflecting their purpose.
        - If the request needs multiple layers, add all needed layers.
        - In conversation history, your previous responses appear as plain text (the JSON was already processed). Always respond with JSON format regardless.
        """
    }

    func build2DSystemPrompt(context: String, dataFlowDescription: String) -> String {
        """
        You are a Metal Shading Language (MSL) expert assistant embedded in a real-time 2D shader canvas app.
        You are an intelligent Agent that can add/modify 2D objects on the canvas and write/edit their shaders.

        RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object. No markdown fences, no extra text.
        {
          "canFulfill": true/false,
          "explanation": "Your explanation to the user (same language as user)",
          "actions": [
            ... action objects (see ACTION TYPES below) ...
          ],
          "barriers": ["technical barrier 1", "barrier 2"]
        }
        Set "barriers" to null when canFulfill is true. Set "actions" to [] when no changes are needed.

        ACTION TYPES:

        1) Add fullscreen post-processing layer (same as 3D):
        { "type": "addLayer", "category": "fullscreen", "name": "Effect Name", "code": "complete self-contained MSL" }

        2) Modify existing fullscreen layer:
        { "type": "modifyLayer", "category": "fullscreen", "name": "New Name", "code": "...", "targetLayerName": "Existing Layer Name" }

        3) Add a 2D object to the canvas:
        { "type": "addObject2D", "name": "Button", "shapeType": "Rounded Rect",
          "posX": 0.0, "posY": 0.0, "scaleW": 0.5, "scaleH": 0.5, "rotation": 0.0, "cornerRadius": 0.15 }
        Available shapes: "Rectangle", "Rounded Rect", "Circle", "Capsule"
        Position: normalized coords (-1 to 1), Scale: fraction of viewport (0.1 to 1.0)

        4) Modify an existing 2D object's properties:
        { "type": "modifyObject2D", "targetObjectName": "Button", "name": "New Name",
          "shapeType": "Circle", "posX": 0.2, "posY": -0.1, "scaleW": 0.3, "scaleH": 0.3, "cornerRadius": 0.1 }
        Only include fields you want to change.

        5) Set the shared distortion (vertex) or fragment shader:
        { "type": "setSharedShader2D", "category": "distortion|fragment", "code": "shader code" }

        6) Set per-object custom shader:
        { "type": "setObjectShader2D", "category": "distortion|fragment", "targetObjectName": "Button", "code": "shader code" }

        CURRENT WORKSPACE (2D Mode):
        \(context)

        DATA FLOW CONFIGURATION:
        \(dataFlowDescription)

        2D SHADER CODE RULES:

        Distortion (vertex) shaders:
        - Struct definitions (VertexOut, Uniforms, Transform2D) are AUTO-GENERATED.
        - DO NOT include #include <metal_stdlib>, using namespace metal, or struct definitions.
        - Write ONLY the distort_main function.
        - Signature: float2 distort_main(float2 position, float2 uv, Uniforms uniforms)
        - position: shape-local coords (~[-0.5, 0.5]), uv: texture coords [0,1]
        - Return the distorted position. The system applies object transform + camera automatically.
        - Available uniforms: .time (float), .resolution (float2), .mouseX/.mouseY (float, normalized [0,1])

        Fragment shaders:
        - Struct definitions are AUTO-GENERATED. DO NOT include them.
        - Write ONLY the fragment_main function.
        - Base signature: fragment float4 fragment_main(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]])
        - SDF edge clipping is applied automatically — just output the color.
        - Available VertexOut fields: in.texCoord (float2, shape-local UV [0,1])
        - Available uniforms: .resolution (float2), .time (float), .mouseX/.mouseY (float)

        BACKGROUND TEXTURE (bgTexture) — for glass, blur, refraction effects:
        - To read the canvas behind this object (grid + previously drawn objects),
          add "texture2d<float> bgTexture [[texture(0)]]" as a parameter:
          fragment float4 fragment_main(VertexOut in [[stage_in]],
                                        constant Uniforms &uniforms [[buffer(1)]],
                                        texture2d<float> bgTexture [[texture(0)]]) { ... }
        - Use SCREEN-SPACE UV for correct sampling (not in.texCoord which is shape-local):
          float2 screenUV = float2(in.position.xy) / uniforms.resolution;
          constexpr sampler s(filter::linear);
          float4 bg = bgTexture.sample(s, screenUV);
        - For blur: sample bgTexture at multiple offsets around screenUV and average them.
        - bgTexture contains the full canvas at the object's render order. Later objects see earlier objects.

        Fullscreen (post-processing) shaders:
        - MUST be self-contained: include #include <metal_stdlib>, using namespace metal, ALL structs.
        - MUST define BOTH vertex_main (fullscreen triangle from vertex_id) AND fragment_main.
        - Reads previous pass via: texture2d<float> inTexture [[texture(0)]]

        USER PARAMETERS — ALWAYS EXPOSE ADJUSTABLE VALUES:
        You MUST add // @param directives for key adjustable values in every shader you write.
        This gives users real-time UI controls (sliders, color pickers) without editing code.
        Works in BOTH fragment AND vertex (distortion) shaders in 2D mode.
        Parameter names MUST start with underscore. Types: float, float2, float3, float4, color.
        Syntax: // @param _name type default_values [min max]
        Examples:
          // @param _speed float 2.0 0.0 10.0
          // @param _baseColor color 0.2 0.5 1.0
          // @param _glowRadius float 0.1 0.0 0.5
        The system auto-generates #define macros from @param directives.
        DO NOT manually define a Params struct. Just add // @param directives and reference names directly.
        BEST PRACTICE: For every shader, identify 2-5 key artistic parameters and expose them.
        Good candidates: color/tint, intensity/strength, scale/frequency, speed, radius, threshold, offset.
        Always provide sensible min/max ranges for float params so the slider is immediately useful.

        CAPABILITIES (canFulfill = true):
        ✓ UI element shapes: buttons, cards, badges, panels, icons via SDF shapes
        ✓ Fragment effects: gradients, noise, patterns, animations, glow, shimmer, liquid
        ✓ Vertex distortions: wave, wobble, pulse, breathing, elastic, morph
        ✓ Post-processing: blur, bloom, vignette, color grading, edge detection, CRT, glitch
        ✓ Scene composition: multiple objects with different shapes, positions, shaders
        ✓ Per-object shader overrides for unique appearance on individual objects
        ✓ Time-animated and mouse-interactive effects
        ✓ User-controllable parameters via @param directives (ALWAYS use these)
        ✓ Background pixel sampling via bgTexture — frosted glass, blur, refraction, distortion, see-through effects

        LIMITATIONS (canFulfill = false, explain barriers):
        ✗ External texture / image sampling (only bgTexture for the canvas background is available)
        ✗ 3D perspective transforms (use 3D mode instead)
        ✗ Physics simulation / collision
        ✗ Compute shaders
        ✗ Text rendering

        VISUAL FEEDBACK:
        An image may be attached. It could be an auto-captured render snapshot OR a user-provided reference image.
        For render snapshots: compare the visual result with what the shader code should produce.
        For user reference images: analyze the desired visual effect and translate it into shader techniques.
        The scene context includes AnimClock (current time in seconds) and Temporal analysis describing
        how the shader changes over time — use these to reason about dynamic behavior beyond the static frame.

        STRICTLY FORBIDDEN — NEVER HARDCODE:
        ✗ DO NOT hardcode background images, textures, or pixel data. Use bgTexture to sample the actual canvas.
        ✗ DO NOT hardcode specific UI element shapes, control outlines, or button appearances in shader code.
        ✗ DO NOT hardcode viewport dimensions or assume a fixed resolution. Use uniforms.resolution.
        ✗ DO NOT embed base64 data, bitmap patterns, or lookup tables that represent specific images.
        ✗ DO NOT write shader code that only works for one specific object shape or screen position.
        ✗ DO NOT attempt to recreate/reproduce a background grid, image, or UI element by drawing it in the shader.
        Shaders MUST be generic and portable — they must produce correct results on ANY shape,
        ANY size, ANY position. Use normalized coordinates (UV, screenUV) and relative values.
        The purpose of this shader canvas is prototyping effects that apply to arbitrary geometry.
        If the user wants to see the background through an object, use bgTexture with screenUV sampling.
        If the user wants edge effects, use the object's SDF/UV boundaries — not hardcoded coordinates.

        IMPORTANT:
        - All generated shader code MUST compile. Verify mentally before outputting.
        - Answer in the SAME LANGUAGE the user writes in.
        - Be concise in explanations.
        - For addObject2D, always pick reasonable default positions and scales.
        - When creating UI-like compositions, use multiple addObject2D actions.
        - In conversation history, your previous responses appear as plain text. Always respond with JSON format regardless.
        """
    }

    // MARK: - Provider Implementations

    /// Calls the OpenAI Chat Completions API with optional vision support.
    func callOpenAI(system: String, messages: [ChatMessage], settings: AISettings, imageData: Data? = nil) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(settings.openAIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        for (i, m) in messages.enumerated() {
            let role = m.role == .user ? "user" : "assistant"
            let isLastUser = (m.role == .user && i == messages.count - 1)
            if isLastUser, let img = imageData {
                let b64 = img.base64EncodedString()
                let contentArray: [[String: Any]] = [
                    ["type": "text", "text": m.content],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)", "detail": "low"]]
                ]
                msgs.append(["role": role, "content": contentArray])
            } else {
                msgs.append(["role": role, "content": m.content])
            }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": settings.openAIModel, "messages": msgs, "max_tokens": 4096] as [String: Any])
        let (data, resp) = try await session.data(for: req)
        try check(resp, data: data, provider: "OpenAI")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]], let msg = choices.first?["message"] as? [String: Any], let content = msg["content"] as? String else { throw AIError.invalidResponse("OpenAI") }
        return content
    }

    /// Calls the Anthropic Messages API with optional vision support.
    func callAnthropic(system: String, messages: [ChatMessage], settings: AISettings, imageData: Data? = nil) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(settings.anthropicKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var msgs: [[String: Any]] = []
        for (i, m) in messages.enumerated() {
            let role = m.role == .user ? "user" : "assistant"
            let isLastUser = (m.role == .user && i == messages.count - 1)
            if isLastUser, let img = imageData {
                let b64 = img.base64EncodedString()
                let contentArray: [[String: Any]] = [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]],
                    ["type": "text", "text": m.content]
                ]
                msgs.append(["role": role, "content": contentArray])
            } else {
                msgs.append(["role": role, "content": m.content])
            }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": settings.anthropicModel, "max_tokens": 4096, "system": system, "messages": msgs] as [String: Any])
        let (data, resp) = try await session.data(for: req)
        try check(resp, data: data, provider: "Anthropic")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]], let text = content.first?["text"] as? String else { throw AIError.invalidResponse("Anthropic") }
        return text
    }

    /// Calls the Google Gemini generateContent API with optional vision support.
    func callGemini(system: String, messages: [ChatMessage], settings: AISettings, imageData: Data? = nil) async throws -> String {
        let model = settings.geminiModel
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(settings.geminiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var contents: [[String: Any]] = []
        for (i, m) in messages.enumerated() {
            let role = m.role == .user ? "user" : "model"
            let isLastUser = (m.role == .user && i == messages.count - 1)
            if isLastUser, let img = imageData {
                let b64 = img.base64EncodedString()
                let parts: [[String: Any]] = [
                    ["text": m.content],
                    ["inlineData": ["mimeType": "image/jpeg", "data": b64]]
                ]
                contents.append(["role": role, "parts": parts])
            } else {
                contents.append(["role": role, "parts": [["text": m.content]]])
            }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["contents": contents, "systemInstruction": ["parts": [["text": system]]]] as [String: Any])
        let (data, resp) = try await session.data(for: req)
        try check(resp, data: data, provider: "Gemini")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let cands = json?["candidates"] as? [[String: Any]], let co = cands.first?["content"] as? [String: Any], let parts = co["parts"] as? [[String: Any]], let text = parts.first?["text"] as? String else { throw AIError.invalidResponse("Gemini") }
        return text
    }

    // MARK: - Helpers

    /// Validates the HTTP response status code. Throws on non-2xx responses.
    private func check(_ response: URLResponse, data: Data, provider: String) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError(provider: provider, status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: body)
        }
    }

    /// Parses a JSON array string from the AI response into TutorialStep objects.
    ///
    /// Handles common AI response quirks:
    /// - Strips markdown code fences if present
    /// - Extracts the JSON array from surrounding text
    /// - Validates all required fields are present
    func parseTutorialSteps(from text: String) throws -> [TutorialStep] {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = s.range(of: "["), let b = s.range(of: "]", options: .backwards) { s = String(s[a.lowerBound...b.upperBound]) }
        guard let data = s.data(using: .utf8), let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw AIError.invalidResponse("parse") }
        var steps: [TutorialStep] = []
        for (i, item) in arr.enumerated() {
            guard let title = item["title"] as? String, let sub = item["subtitle"] as? String, let inst = item["instructions"] as? String, let goal = item["goal"] as? String, let hint = item["hint"] as? String, let catStr = item["category"] as? String, let starter = item["starterCode"] as? String, let solution = item["solutionCode"] as? String else { continue }
            let cat: ShaderCategory = catStr.lowercased() == "vertex" ? .vertex : catStr.lowercased() == "fullscreen" ? .fullscreen : .fragment
            steps.append(TutorialStep(id: i, title: title, subtitle: sub, instructions: inst, goal: goal, hint: hint, category: cat, starterCode: starter, solutionCode: solution))
        }
        guard !steps.isEmpty else { throw AIError.invalidResponse("0 steps") }
        return steps
    }

    /// Parses a structured AgentResponse from the AI's raw text output.
    ///
    /// Handles common formatting quirks:
    /// - Strips markdown code fences (```json ... ```) if present
    /// - Finds the outermost JSON object using brace-depth counting
    ///   (correctly handles nested braces inside string values like shader code)
    /// - Falls back with a thrown error if no valid JSON object can be extracted
    func parseAgentResponse(from text: String) throws -> AgentResponse {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        let fencePattern = #"```(?:json)?\s*([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) {
            cleaned = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find outermost JSON object via brace-depth counting
        guard let startIdx = cleaned.firstIndex(of: "{") else {
            throw AIError.invalidResponse("No JSON object found in agent response")
        }
        var depth = 0
        var inString = false
        var escaped = false
        var endIdx = cleaned.endIndex

        for i in cleaned.indices[startIdx...] {
            let c = cleaned[i]
            if escaped { escaped = false; continue }
            if c == "\\" && inString { escaped = true; continue }
            if c == "\"" { inString.toggle(); continue }
            if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { endIdx = cleaned.index(after: i); break }
                }
            }
        }

        let jsonString = String(cleaned[startIdx..<endIdx])
        guard let data = jsonString.data(using: .utf8) else {
            throw AIError.invalidResponse("Failed to encode agent JSON to data")
        }
        return try JSONDecoder().decode(AgentResponse.self, from: data)
    }
}

// MARK: - AI Error Types

/// Errors that can occur during AI API interactions.
enum AIError: LocalizedError {
    /// No API key has been configured for the selected provider.
    case notConfigured

    /// The API returned a non-2xx HTTP status code.
    case apiError(provider: String, status: Int, message: String)

    /// The API response could not be parsed into the expected format.
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No API key configured."
        case .apiError(let p, let s, let m): return "\(p) error (\(s)): \(String(m.prefix(200)))"
        case .invalidResponse(let d): return "Invalid AI response: \(d)"
        }
    }
}
