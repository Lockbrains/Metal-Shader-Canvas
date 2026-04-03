//
//  LabAIFlow.swift
//  macOSShaderCanvas
//
//  AI conversation controller for Lab mode. Uses a single unified system prompt
//  with all available actions — the AI decides autonomously what actions to take
//  based on conversation context rather than rigid phase gating.
//

import Foundation

// MARK: - LabAIFlow

enum LabAIFlow {

    /// Sends a message within the Lab workflow. The `phase` parameter is informational
    /// only — the AI always has access to all actions and full workspace context.
    /// Routes implementation-phase requests through agentChat for shader code generation;
    /// all other requests go through sendLabChat for structured JSON responses.
    static func sendMessage(
        text: String,
        phase: LabPhase,
        references: [ReferenceItem],
        projectDocument: ProjectDocument,
        designDoc: DesignDocument,
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
        captured: CapturedAISettings,
        imageData: Data? = nil,
        referenceImages: [Data] = []
    ) async throws -> LabAgentResponse {
        let t0 = CFAbsoluteTimeGetCurrent()
        print("[LAB-AI] sendMessage START")
        let context = buildLabContext(
            references: references, projectDocument: projectDocument,
            designDoc: designDoc,
            activeShaders: activeShaders, canvasMode: canvasMode,
            dataFlowConfig: dataFlowConfig, dataFlow2DConfig: dataFlow2DConfig,
            objects2D: objects2D, sharedVertexCode2D: sharedVertexCode2D,
            sharedFragmentCode2D: sharedFragmentCode2D,
            paramValues: paramValues, meshType: meshType
        )
        print("[LAB-AI] buildLabContext done  +\(Int((CFAbsoluteTimeGetCurrent()-t0)*1000))ms")

        let dfDesc = buildDataFlowDescription(canvasMode: canvasMode, config3D: dataFlowConfig, config2D: dataFlow2DConfig)
        let systemPrompt = buildUnifiedPrompt(
            context: context, canvasMode: canvasMode, dataFlowDescription: dfDesc, phaseHint: phase
        )
        print("[LAB-AI] buildUnifiedPrompt done  +\(Int((CFAbsoluteTimeGetCurrent()-t0)*1000))ms  hint=\(phase)")

        // All phases use the same unified path — the AI decides what actions
        // to take (labActions for docs/params, agentActions for shader code).
        // No phase-gating: the AI can write shader code from any phase.
        print("[LAB-AI] BEFORE await sendLabChat  +\(Int((CFAbsoluteTimeGetCurrent()-t0)*1000))ms")
        let result = try await sendLabChat(
            system: systemPrompt,
            userMessage: text,
            chatHistory: chatHistory,
            captured: captured,
            imageData: imageData,
            referenceImages: referenceImages
        )
        print("[LAB-AI] AFTER await sendLabChat  +\(Int((CFAbsoluteTimeGetCurrent()-t0)*1000))ms")
        return result
    }

    // MARK: - Unified System Prompt

    private static let baseRole = """
    You are an expert shader development collaborator in a Lab environment. \
    You work alongside the human artist/developer to create beautiful and performant shaders. \
    The human provides aesthetic direction and visual references; you provide technical expertise, \
    stability, and performance optimization.
    """

    private static let jsonResponseFormat = """

    RESPONSE FORMAT:
    You MUST respond with ONLY a valid JSON object (no markdown fences, no extra text outside the JSON).
    {
      "explanation": "Your natural language response to the user (markdown allowed here)",
      "labActions": [
        // Zero or more lab actions (doc updates, params, constraints, etc.)
      ],
      "agentActions": [
        // Zero or more shader code actions (addObject2D, setObjectShader2D, addLayer, etc.)
        // ALWAYS include setObjectShader2D with full shader code for every addObject2D
      ]
    }
    The "explanation" field is shown directly to the user as chat — be conversational, collaborative, and thorough.
    The "labActions" array drives document updates, parameter creation, and project state changes.
    The "agentActions" array drives direct shader code modifications (adding/modifying layers).
    If you have nothing to update for either array, use an empty array [].
    """

    static func buildUnifiedPrompt(
        context: String,
        canvasMode: CanvasMode = .threeDimensionalLab,
        dataFlowDescription: String = "",
        phaseHint: LabPhase? = nil
    ) -> String {
        var prompt = """
        \(baseRole)

        CAPABILITIES:
        You can perform ANY of these actions at any time based on conversation context:
        - Write shader code directly (add/modify layers, add 2D objects, set object shaders)
        - Write/update the Design Doc (collaborative plan — records design thinking, analysis, decisions)
        - Write/update the Project Doc (final documentation — technical specs for migration/handoff)
        - Add parameters with default values (creates real sliders the user can adjust)
        - Suggest parameter value changes with one-click apply
        - Add constraints, log iteration decisions

        GUIDELINES:
        - When the user wants to see something: write shader code directly via agentActions — do NOT tell them to switch modes
        - For significant design decisions: write the plan in the Design Doc first, then implement
        - Proactively update the Design Doc as the conversation evolves (analysis results, technical approach, decisions made)
        - When implementation is complete, summarize into the Project Doc (final technical documentation)
        - The // @param directives in shader code are what create real UI sliders. addParameter only pre-registers defaults. ALWAYS include // @param in your shader code for every user-adjustable value.
        - You can combine labActions and agentActions in the same response
        - ⚠️ ALWAYS write COMPLETE implementations: every addObject2D MUST have a matching setObjectShader2D with actual shader code in the SAME response. Objects without custom shaders render as plain default gradients and look broken. NEVER split object creation and shader writing across multiple turns.

        AVAILABLE ACTIONS (labActions array):
        1. Update Design Doc (collaborative plan):
           {"type": "updateDesignDoc", "content": "markdown content to append/replace in the design document"}

        2. Update Project Doc (final documentation):
           {"type": "updateProjectDoc", "content": "markdown content to append/replace in the project document"}

        3. Add a parameter (creates a real slider with default value):
           {"type": "addParameter", "paramName": "_name", "paramType": "float|float2|float3|float4|color", "paramPurpose": "what it controls", "paramDefault": [1.0], "paramMin": 0.0, "paramMax": 1.0}

        4. Add a constraint:
           {"type": "addConstraint", "constraint": "description of constraint"}

        5. Suggest parameter value changes:
           {"type": "suggestParamChange", "paramChanges": {"_paramName": [1.0]}, "changeRationale": "why this change helps"}

        6. Log an iteration decision:
           {"type": "logIteration", "iterationDescription": "what changed", "iterationDecision": "decision made", "iterationOutcome": "accepted|rejected|modified"}

        \(shaderActionsPrompt(canvasMode: canvasMode))
        \(shaderCodeRules(canvasMode: canvasMode))

        DATA FLOW CONFIGURATION:
        \(dataFlowDescription)
        \(jsonResponseFormat)

        """

        if let hint = phaseHint {
            prompt += "\nCURRENT WORKFLOW HINT: \(hint.displayName) — the user is currently focused on this area, but you are not restricted to it.\n"
        }

        prompt += "\nWORKSPACE CONTEXT:\n\(context)"

        return prompt
    }

    // MARK: - Shader Action Prompt (mode-aware)

    private static func shaderActionsPrompt(canvasMode: CanvasMode) -> String {
        if canvasMode.is2D {
            return """
            2D RENDERING PIPELINE (critical — understand this before writing any code):
            ┌─────────────────────────────────────────────────────┐
            │ Pass 1: Background (grid or image)                  │
            │ Pass 2: Each Object2D rendered with its SDF + shader│
            │ Pass 3+: Fullscreen post-processing layers ON TOP   │
            └─────────────────────────────────────────────────────┘
            ⚠️ Fullscreen layers render AFTER all objects and overwrite the entire screen.
            A fullscreen layer that does NOT read from inTexture will HIDE all objects!

            WHEN TO USE WHAT:
            - To create visible shapes/elements → addObject2D + setObjectShader2D (PREFERRED)
            - To apply post-processing effects (blur, bloom, vignette, color grading) → addLayer with category "fullscreen"
            - Fullscreen layers MUST sample from inTexture and blend/modify it — NEVER generate opaque procedural content
            - For custom SDF shapes (heart, star, etc.), draw them INSIDE an object's fragment shader using the object's UV space

            ⚠️⚠️⚠️ CRITICAL — ALWAYS PAIR addObject2D WITH setObjectShader2D IN THE SAME RESPONSE:
            An addObject2D WITHOUT a matching setObjectShader2D renders with a PLAIN DEFAULT
            GRADIENT — it will NOT have any custom appearance! The user will see a broken result.
            You MUST include BOTH addObject2D AND setObjectShader2D for EVERY object that needs
            a custom material in the SAME JSON response. NEVER create objects "first" and plan
            to write shaders "later" — that leaves objects looking broken.
            If the scene requires multiple custom objects, write ALL of them in ONE response.
            It is better to write one complete object (addObject2D + setObjectShader2D) than
            to create four empty objects with no custom shaders.

            SHADER CODE ACTIONS (agentActions array):
            Include these in the "agentActions" field of your JSON response.

            1) Add a 2D object to the canvas (PREFERRED for creating visual elements):
            {"type": "addObject2D", "name": "Shape Name", "shapeType": "Rounded Rect",
              "posX": 0.0, "posY": 0.0, "scaleW": 0.5, "scaleH": 0.5, "rotation": 0.0, "cornerRadius": 0.15, "category": "", "code": ""}
            Available shapes: "Rectangle", "Rounded Rect", "Circle", "Capsule"
            Position: normalized coords (-1 to 1), Scale: fraction of viewport (0.1 to 1.0)

            2) Set per-object custom shader (PREFERRED for 2D effects):
            {"type": "setObjectShader2D", "category": "fragment", "targetObjectName": "Shape Name", "code": "shader code", "name": "Shader Description"}
            ⚠️ "targetObjectName" MUST exactly match the "name" from addObject2D. This is how the system finds the object.
            In 2D mode, ONLY write fragment shaders unless the user asks for vertex distortion.

            3) Modify an existing object's properties:
            {"type": "modifyObject2D", "targetObjectName": "Shape Name", "name": "New Name",
              "shapeType": "Circle", "posX": 0.2, "posY": -0.1, "scaleW": 0.3, "scaleH": 0.3, "category": "", "code": ""}

            4) Add fullscreen post-processing layer (only for effects, NOT for creating shapes):
            {"type": "addLayer", "category": "fullscreen", "name": "Effect Name", "code": "complete self-contained MSL"}
            ⚠️ MUST read from inTexture and blend — never replace the entire screen with procedural content.

            5) Modify existing fullscreen layer:
            {"type": "modifyLayer", "category": "fullscreen", "name": "New Name", "code": "...", "targetLayerName": "Existing Layer Name"}

            6) Enable data flow fields (BEFORE any shader that needs them):
            {"type": "enableDataFlow", "name": "Enable DataFlow", "code": "time,mouse,objectPosition,screenUV", "category": ""}
            """
        }

        return """
        SHADER CODE ACTIONS (agentActions array):
        Use these when the user asks you to implement, create, or modify shaders. Include them in the "agentActions" field.

        1) Add a new shader layer:
        {"type": "addLayer", "category": "vertex|fragment|fullscreen", "name": "Layer Name", "code": "MSL code"}

        2) Modify existing shader layer:
        {"type": "modifyLayer", "category": "vertex|fragment|fullscreen", "name": "New Name", "code": "MSL code", "targetLayerName": "existing layer name"}

        3) Enable data flow fields (BEFORE any shader that needs them):
        {"type": "enableDataFlow", "name": "Enable DataFlow", "code": "time,uv,normal,worldPosition,worldNormal,viewDirection", "category": ""}
        Available 3D fields: normal, uv, time, worldPosition, worldNormal, viewDirection
        The VertexOut member names: worldPosition → positionWS, worldNormal → normalWS, viewDirection → viewDirWS
        """
    }

    // MARK: - Shader Code Rules (mode-aware, shared with Canvas prompt)

    private static func shaderCodeRules(canvasMode: CanvasMode) -> String {
        let paramRules = """
        USER PARAMETERS — ALWAYS EXPOSE ADJUSTABLE VALUES:
        You MUST add // @param directives for key adjustable values in every shader you write.
        This gives users real-time UI controls (sliders, color pickers) without editing code.
        Parameter names MUST start with underscore. Types: float, float2, float3, float4, color.
        Syntax: // @param _name type default_values [min max]
        Examples:
          // @param _intensity float 0.5 0.0 1.0     → slider (0.0 to 1.0, default 0.5)
          // @param _tint color 1.0 0.5 0.2           → color picker (RGB defaults)
          // @param _offset float2 0.0 0.0            → XY input
        The system auto-generates #define macros from @param directives.
        DO NOT manually define a Params struct. Just add // @param directives and reference names directly.
        BEST PRACTICE: For every shader, identify 2-5 key artistic parameters and expose them.
        Always provide sensible min/max ranges for float params so the slider is immediately useful.
        """

        if canvasMode.is2D {
            return """
            METAL SHADER CODE RULES (2D MODE):

            ═══ PER-OBJECT FRAGMENT SHADERS (setObjectShader2D) — MOST IMPORTANT ═══
            - Struct definitions are AUTO-GENERATED. DO NOT include them.
            - DO NOT include #include <metal_stdlib>, using namespace metal, or struct definitions.
            - Write ONLY the fragment_main function.
            - Signature: fragment float4 fragment_main(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]])
            - SDF edge clipping is applied automatically by the system — just output the color.
            - Available VertexOut fields:
              • in.texCoord (float2) — shape-local UV [0,1]
              • in.shapeAspect (float) — combined screen-space aspect ratio of the object (accounts for shape preset, object scale, AND viewport aspect)
              • in.cornerRadius (float) — corner radius for rounded shapes
            - Available uniforms: .resolution (float2), .time (float), .mouseX/.mouseY (float)

            CUSTOM SDF SHAPES INSIDE OBJECT FRAGMENT SHADERS:
            You can draw ANY SDF shape inside an object's fragment shader using its texCoord space.
            The object's base shape provides clipping; your shader paints whatever you want inside.

            ⚠️ ASPECT RATIO CORRECTION — CRITICAL FOR ALL SDF SHAPES:
            in.texCoord is [0,1] in both axes regardless of the object's actual screen proportions.
            You MUST use in.shapeAspect to correct for the object's screen-space aspect ratio,
            otherwise circles become ovals and rounded rects get stretched.
            Correct pattern:  float2 p = (in.texCoord - 0.5) * float2(in.shapeAspect, 1.0);
            WRONG pattern:    float2 p = in.texCoord * 2.0 - 1.0;  // IGNORES aspect → shapes stretch!

            Example — heart SDF inside a Circle object:
              fragment float4 fragment_main(VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]]) {
                  float2 p = (in.texCoord - 0.5) * float2(in.shapeAspect, 1.0);
                  // Heart SDF (Inigo Quilez) — works correctly at any viewport size
                  p.x = abs(p.x);
                  float d = length(p - float2(0.25, -0.3)) < ... ;  // your SDF math
                  float3 col = mix(float3(0.1), float3(1, 0.2, 0.3), smoothstep(0.01, -0.01, d));
                  return float4(col, 1.0);
              }
            This works for ANY SDF: heart, star, polygon, bezier, gear, arrow, cross, etc.
            Reference: https://iquilezles.org/articles/distfunctions2d/

            BACKGROUND TEXTURE (bgTexture) — for glass, blur, refraction effects:
            - Add "texture2d<float> bgTexture [[texture(0)]]" as a fragment parameter:
              fragment float4 fragment_main(VertexOut in [[stage_in]],
                                            constant Uniforms &uniforms [[buffer(1)]],
                                            texture2d<float> bgTexture [[texture(0)]]) { ... }
            - Use SCREEN-SPACE UV for sampling: float2 screenUV = float2(in.position.xy) / uniforms.resolution;
            - For blur: sample bgTexture at multiple offsets around screenUV and average.

            Distortion (vertex) shaders:
            - DO NOT include #include <metal_stdlib>, using namespace metal, or struct definitions.
            - Write ONLY the distort_main function.
            - Signature: float2 distort_main(float2 position, float2 uv, Uniforms uniforms)
            - Return the distorted position.

            ═══ FULLSCREEN POST-PROCESSING SHADERS (addLayer with "fullscreen") ═══
            - MUST be self-contained: include #include <metal_stdlib>, using namespace metal, ALL structs.
            - MUST define BOTH vertex_main (fullscreen triangle from vertex_id) AND fragment_main.
            - MUST sample from inTexture and modify/blend it — NEVER output opaque procedural content that hides objects.
            - Reads previous pass via: texture2d<float> inTexture [[texture(0)]]
            - VertexOut must have: position [[position]], texCoord (float2), time (float).
            - Uniforms: { float4x4 modelViewProjectionMatrix; float time; }
            ⚠️ Fullscreen shaders that do NOT read inTexture will render a blank canvas hiding all objects!

            \(paramRules)
            """
        }

        return """
        METAL SHADER CODE RULES (3D MODE):

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

        CUSTOM SDF SHAPES IN FULLSCREEN SHADERS:
        In fullscreen shaders you have full freedom — define any SDF primitive directly:
        - Heart, star, polygon, bezier, cross, arrow — any 2D SDF from IQ's reference.
        - Compose complex scenes with smooth min/max (smin, smax) for organic blending.
        You can build entire 2D scenes and animated shapes inside fullscreen post-processing layers.

        \(paramRules)

        STRICTLY FORBIDDEN:
        ✗ DO NOT hardcode background images, textures, or pixel data.
        ✗ DO NOT hardcode viewport dimensions or assume a fixed resolution.
        ✗ DO NOT embed base64 data, bitmap patterns, or lookup tables.
        Shaders MUST be generic and portable — use normalized coordinates and relative values.
        """
    }

    // MARK: - Lab Context Builder (always full context, no phase-gating)

    static func buildLabContext(
        references: [ReferenceItem], projectDocument: ProjectDocument,
        designDoc: DesignDocument,
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

        if !designDoc.markdown.isEmpty {
            ctx += "\n--- DESIGN DOCUMENT ---\n"
            ctx += designDoc.markdown + "\n"
        }

        if !projectDocument.markdown.isEmpty {
            ctx += "\n--- PROJECT DOCUMENT ---\n"
            ctx += projectDocument.markdown + "\n"
        }

        if !activeShaders.isEmpty {
            ctx += "\n--- ACTIVE SHADERS ---\n"
            for shader in activeShaders {
                ctx += "[\(shader.category.rawValue)] \(shader.name):\n"
                ctx += shader.code + "\n"
            }
        }

        if !paramValues.isEmpty {
            ctx += "\n--- CURRENT PARAMETERS ---\n"
            for (name, values) in paramValues.sorted(by: { $0.key < $1.key }) {
                ctx += "\(name) = \(values.map { String(format: "%.3f", $0) }.joined(separator: ", "))\n"
            }
        }

        if canvasMode.is3D {
            ctx += "\nMesh: \(meshType == .sphere ? "sphere" : meshType == .cube ? "cube" : "custom")\n"
        }

        if canvasMode.is2D && !objects2D.isEmpty {
            ctx += "\n--- 2D OBJECTS ---\n"
            for obj in objects2D {
                ctx += "\(obj.name) [\(obj.shapeType.rawValue)] pos=(\(obj.posX),\(obj.posY)) scale=(\(obj.scaleW),\(obj.scaleH))"
                if obj.shapeLocked { ctx += " [SHAPE LOCKED — SDF access enabled]" }
                if obj.isAIPreview { ctx += " [AI preview]" }
                ctx += "\n"
            }
        }

        if canvasMode.is2D {
            if !sharedVertexCode2D.isEmpty {
                ctx += "\n--- SHARED VERTEX (2D) ---\n\(sharedVertexCode2D)\n"
            }
            if !sharedFragmentCode2D.isEmpty {
                ctx += "\n--- SHARED FRAGMENT (2D) ---\n\(sharedFragmentCode2D)\n"
            }
        }

        return ctx
    }

    // MARK: - Data Flow Description

    private static func buildDataFlowDescription(canvasMode: CanvasMode, config3D: DataFlowConfig, config2D: DataFlow2DConfig) -> String {
        if canvasMode.is2D {
            return "2D DataFlow: time=\(config2D.timeEnabled ? "ON" : "OFF") mouse=\(config2D.mouseEnabled ? "ON" : "OFF") objectPosition=\(config2D.objectPositionEnabled ? "ON" : "OFF") screenUV=\(config2D.screenUVEnabled ? "ON" : "OFF")"
        }
        return "3D DataFlow: normal=\(config3D.normalEnabled ? "ON" : "OFF") uv=\(config3D.uvEnabled ? "ON" : "OFF") time=\(config3D.timeEnabled ? "ON" : "OFF") worldPosition=\(config3D.worldPositionEnabled ? "ON" : "OFF") worldNormal=\(config3D.worldNormalEnabled ? "ON" : "OFF") viewDirection=\(config3D.viewDirectionEnabled ? "ON" : "OFF")"
    }

    // MARK: - Generic Lab Chat (non-implementation phases)

    private static func sendLabChat(
        system: String, userMessage: String,
        chatHistory: [ChatMessage], captured: CapturedAISettings,
        imageData: Data?,
        referenceImages: [Data] = []
    ) async throws -> LabAgentResponse {
        let messages = chatHistory + [ChatMessage(role: .user, content: userMessage)]
        let rawResponse: String = try await AIService.onBackground {
            switch captured.provider {
            case .openai:
                return try await AIService.shared.callOpenAI(
                    system: system, messages: messages, captured: captured,
                    imageData: imageData, additionalImages: referenceImages)
            case .anthropic:
                return try await AIService.shared.callAnthropic(
                    system: system, messages: messages, captured: captured,
                    imageData: imageData, additionalImages: referenceImages)
            case .gemini:
                return try await AIService.shared.callGemini(
                    system: system, messages: messages, captured: captured,
                    imageData: imageData, additionalImages: referenceImages)
            }
        }
        return parseLabAgentResponse(from: rawResponse)
    }

    // MARK: - Streaming Lab Chat

    /// Returns an AsyncStream of text deltas for the Lab chat. The caller should accumulate
    /// the full text and parse it as LabAgentResponse JSON when the stream finishes.
    static func streamLabMessage(
        system: String,
        userMessage: String,
        chatHistory: [ChatMessage],
        captured: CapturedAISettings,
        imageData: Data?,
        referenceImages: [Data] = []
    ) -> AsyncStream<StreamChunk> {
        let messages = chatHistory + [ChatMessage(role: .user, content: userMessage)]
        return AIService.shared.streamLabChat(
            system: system, messages: messages, captured: captured,
            imageData: imageData, additionalImages: referenceImages
        )
    }

    /// Builds and returns the unified system prompt for Lab mode.
    /// Phase is used only as an informational hint, not for gating behavior.
    static func systemPromptForPhase(
        phase: LabPhase,
        references: [ReferenceItem],
        projectDocument: ProjectDocument,
        designDoc: DesignDocument,
        activeShaders: [ActiveShader],
        canvasMode: CanvasMode,
        dataFlowConfig: DataFlowConfig,
        dataFlow2DConfig: DataFlow2DConfig,
        objects2D: [Object2D],
        sharedVertexCode2D: String,
        sharedFragmentCode2D: String,
        paramValues: [String: [Float]],
        meshType: MeshType
    ) -> String {
        let context = buildLabContext(
            references: references, projectDocument: projectDocument,
            designDoc: designDoc,
            activeShaders: activeShaders, canvasMode: canvasMode,
            dataFlowConfig: dataFlowConfig, dataFlow2DConfig: dataFlow2DConfig,
            objects2D: objects2D, sharedVertexCode2D: sharedVertexCode2D,
            sharedFragmentCode2D: sharedFragmentCode2D,
            paramValues: paramValues, meshType: meshType
        )
        let dfDesc = buildDataFlowDescription(canvasMode: canvasMode, config3D: dataFlowConfig, config2D: dataFlow2DConfig)
        return buildUnifiedPrompt(context: context, canvasMode: canvasMode, dataFlowDescription: dfDesc, phaseHint: phase)
    }

    // MARK: - Reference Analysis

    /// Analyzes reference items by sending image data to a multimodal model.
    static func analyzeReferences(_ references: [ReferenceItem], captured: CapturedAISettings) async throws -> String {
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
        let rawResponse: String = try await AIService.onBackground {
            switch captured.provider {
            case .openai:
                return try await AIService.shared.callOpenAI(
                    system: "You are a shader development visual analyst.", messages: [msg],
                    captured: captured, imageData: firstImage)
            case .anthropic:
                return try await AIService.shared.callAnthropic(
                    system: "You are a shader development visual analyst.", messages: [msg],
                    captured: captured, imageData: firstImage)
            case .gemini:
                return try await AIService.shared.callGemini(
                    system: "You are a shader development visual analyst.", messages: [msg],
                    captured: captured, imageData: firstImage)
            }
        }
        return rawResponse
    }

    // MARK: - Adversarial Proposal

    /// Generates an adversarial alternative proposal for the current shader state.
    static func proposeAlternative(
        currentCode: String, paramValues: [String: [Float]],
        projectDocument: ProjectDocument, captured: CapturedAISettings,
        renderCapture: Data? = nil
    ) async throws -> AdversarialProposal {
        let prompt = """
        You are reviewing a shader implementation. Propose ONE specific alternative that could improve it.

        Current shader code:
        \(currentCode)

        Current parameters:
        \(paramValues.map { "\($0.key) = \($0.value)" }.joined(separator: "\n"))

        Project goal: \(projectDocument.visualGoal)

        You MUST respond with ONLY a JSON object (no markdown fences, no extra text) in this exact format:
        {
          "description": "What you propose to change",
          "rationale": "Why this would be better",
          "paramChanges": { "paramName": [1.0] },
          "codeChanges": { "layerName": "full MSL code replacement" }
        }
        paramChanges and codeChanges may be null if not applicable.
        """

        let msg = ChatMessage(role: .user, content: prompt)
        let rawResponse: String = try await AIService.onBackground {
            switch captured.provider {
            case .openai:
                return try await AIService.shared.callOpenAI(
                    system: "You are an adversarial shader reviewer. Always respond with valid JSON only.", messages: [msg],
                    captured: captured, imageData: renderCapture)
            case .anthropic:
                return try await AIService.shared.callAnthropic(
                    system: "You are an adversarial shader reviewer. Always respond with valid JSON only.", messages: [msg],
                    captured: captured, imageData: renderCapture)
            case .gemini:
                return try await AIService.shared.callGemini(
                    system: "You are an adversarial shader reviewer. Always respond with valid JSON only.", messages: [msg],
                    captured: captured, imageData: renderCapture)
            }
        }

        if let parsed = parseAdversarialJSON(rawResponse) {
            return parsed
        }
        return AdversarialProposal(
            description: rawResponse,
            rationale: "AI-generated alternative proposal"
        )
    }

    // MARK: - Streaming Explanation Extraction

    /// Extracts the "explanation" value from partially streamed JSON for live display.
    /// Falls back to returning the raw text if it's not JSON-shaped.
    static func extractExplanationFromPartialJSON(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return text }

        let marker = "\"explanation\""
        guard let markerRange = trimmed.range(of: marker) else { return "" }
        let afterMarker = trimmed[markerRange.upperBound...]
        guard let colonIdx = afterMarker.firstIndex(of: ":") else { return "" }
        let afterColon = afterMarker[afterMarker.index(after: colonIdx)...].drop(while: { $0.isWhitespace })
        guard afterColon.first == "\"" else { return "" }

        var result = ""
        var escaped = false
        var pos = afterColon.index(after: afterColon.startIndex)
        while pos < afterColon.endIndex {
            let c = afterColon[pos]
            if escaped {
                switch c {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                default: result.append(c)
                }
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "\"" {
                return result
            } else {
                result.append(c)
            }
            pos = afterColon.index(after: pos)
        }
        return result
    }

    // MARK: - Lab Response Parser

    /// Parses a LabAgentResponse from the AI's raw text output.
    /// Handles markdown code fences and uses brace-depth counting for robust JSON extraction.
    /// Falls back to plain text if no valid JSON is found.
    static func parseLabAgentResponse(from text: String) -> LabAgentResponse {
        guard let jsonString = extractJSON(from: text) else {
            return .plainText(text)
        }
        guard let data = jsonString.data(using: .utf8) else {
            return .plainText(text)
        }
        do {
            return try JSONDecoder().decode(LabAgentResponse.self, from: data)
        } catch {
            print("[LAB-AI] parseLabAgentResponse decode failed: \(error)")
            return .plainText(text)
        }
    }

    /// Parses an adversarial proposal JSON from raw response text.
    private static func parseAdversarialJSON(_ text: String) -> AdversarialProposal? {
        guard let jsonString = extractJSON(from: text),
              let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let description = dict["description"] as? String,
              let rationale = dict["rationale"] as? String else {
            return nil
        }
        var paramChanges: [String: [Float]]?
        if let pc = dict["paramChanges"] as? [String: [Any]] {
            var result: [String: [Float]] = [:]
            for (k, v) in pc { result[k] = v.compactMap { ($0 as? NSNumber)?.floatValue } }
            if !result.isEmpty { paramChanges = result }
        }
        let codeChanges = dict["codeChanges"] as? [String: String]
        return AdversarialProposal(
            description: description, rationale: rationale,
            codeChanges: codeChanges, paramChanges: paramChanges
        )
    }

    /// Extracts the outermost JSON object from text, stripping markdown fences.
    /// Uses brace-depth counting to handle nested braces in string values (e.g. shader code).
    static func extractJSON(from text: String) -> String? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let fencePattern = #"```(?:json)?\s*([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) {
            cleaned = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let startIdx = cleaned.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false

        for i in cleaned.indices[startIdx...] {
            let c = cleaned[i]
            if escaped { escaped = false; continue }
            if c == "\\" && inString { escaped = true; continue }
            if c == "\"" { inString.toggle(); continue }
            if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(cleaned[startIdx...i])
                    }
                }
            }
        }
        return nil
    }
}
