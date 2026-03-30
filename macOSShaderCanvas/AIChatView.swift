//
//  AIChatView.swift
//  macOSShaderCanvas
//
//  UI components for the AI-powered chat and tutorial generation features.
//
//  COMPONENTS:
//  ───────────
//  1. AIGlowBorder   — Animated gradient border (Apple Intelligence style)
//  2. AIChatView      — Chat overlay with message history and input
//  3. MessageBubble   — Individual chat message rendering
//  4. AITutorialPromptView — Sheet for entering tutorial generation topics
//
//  The AI chat is displayed as a floating overlay at the bottom of the window.
//  When active, the AIGlowBorder provides a visual cue with a rotating
//  rainbow gradient border around the entire window.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Apple Intelligence Glow Border

/// An animated conic gradient border that rotates continuously around the window edge.
///
/// Implementation strategy:
/// - Renders a static conic gradient on a large circle (diagonal of the window)
/// - Rotates it via GPU transform (zero redraw cost — the gradient is never recalculated)
/// - Masks out the interior rectangle, leaving only a thin border ring visible
/// - Applies a blur for the soft glow effect
/// - Uses `.drawingGroup()` to rasterize the entire effect into a single GPU layer
///
/// The effect is non-interactive (`.allowsHitTesting(false)`) so it doesn't
/// block mouse events on the underlying content.
struct AIGlowBorder: View {
    @State private var rotation: Double = 0

    private let colors: [Color] = [
        Color(red: 0.55, green: 0.80, blue: 1.0),
        Color(red: 0.80, green: 0.60, blue: 1.0),
        Color(red: 1.0, green: 0.55, blue: 0.85),
        Color(red: 1.0, green: 0.75, blue: 0.45),
        Color(red: 1.0, green: 0.95, blue: 0.55),
        Color(red: 0.55, green: 1.0, blue: 0.80),
        Color(red: 0.55, green: 0.80, blue: 1.0),
    ]

    var body: some View {
        GeometryReader { geo in
            let diagonal = sqrt(geo.size.width * geo.size.width + geo.size.height * geo.size.height)

            ZStack {
                borderLayer(size: geo.size, diagonal: diagonal)
                    .blur(radius: 4)
                    .blendMode(.plusLighter)

                borderLayer(size: geo.size, diagonal: diagonal)
                    .blur(radius: 16)
                    .blendMode(.plusLighter)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func borderLayer(size: CGSize, diagonal: CGFloat) -> some View {
        Circle()
            .fill(AngularGradient(colors: colors, center: .center))
            .frame(width: diagonal, height: diagonal)
            .rotationEffect(.degrees(rotation))
            .frame(width: size.width, height: size.height)
            .mask(
                Rectangle()
                    .overlay(
                        Rectangle()
                            .padding(8)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
            )
    }
}

// MARK: - AI Chat Overlay

/// The main AI chat interface. Displays as a floating overlay at the bottom of the window.
///
/// Features:
/// - Scrollable message history with auto-scroll to latest message
/// - Text input with submit-on-enter
/// - Loading indicator during API calls
/// - Error display with dismissal
/// - Tutorial generation button (opens a sheet)
///
/// The chat sends the user's active shader code as context to the AI,
/// enabling shader-aware assistance.
struct AIChatView: View {
    @Binding var messages: [ChatMessage]
    @Binding var isActive: Bool
    let activeShaders: [ActiveShader]
    let aiSettings: AISettings
    let canvasMode: CanvasMode
    let dataFlowConfig: DataFlowConfig
    let dataFlow2DConfig: DataFlow2DConfig
    let objects2D: [Object2D]
    let sharedVertexCode2D: String
    let sharedFragmentCode2D: String
    let compilationError: String?
    let paramValues: [String: [Float]]
    let meshType: MeshType
    let rotationAngle: Float
    let selectedObjectID: UUID?
    let onGenerateTutorial: ([TutorialStep]) -> Void
    let onAgentActions: ([AgentAction]) -> Void

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showTutorialPrompt = false
    @State private var tutorialTopic = ""
    @State private var isTutorialLoading = false
    @State private var pendingAutoFix = false
    @State private var autoFixAttempts = 0
    @State private var streamingThinking = ""
    @State private var currentPlan: AgentPlan?
    @State private var pendingUserImage: Data?
    private let maxAutoFixAttempts = 3

    var body: some View {
        VStack(spacing: 0) {
            // Header with mode switch
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 14))
                    .foregroundColor(.purple)
                Text("AI Assistant")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.3)) { isActive = false } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().background(Color.white.opacity(0.15))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }
                        // Streaming thinking display
                        if isLoading {
                            if !streamingThinking.isEmpty {
                                StreamingThinkingView(text: streamingThinking)
                                    .padding(.horizontal, 16).id("streaming")
                            } else {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.7)
                                    Text("Thinking...")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.5))
                                }.padding(.horizontal, 16).id("loading")
                            }
                        }
                    }.padding(16)
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        if let lastID = messages.last?.id { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
                .onChange(of: streamingThinking) {
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.system(size: 11)).foregroundColor(.orange).lineLimit(2)
                    Spacer()
                    Button(action: { errorMessage = nil }) {
                        Image(systemName: "xmark.circle").foregroundColor(.white.opacity(0.4))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 16).padding(.vertical, 8).background(Color.orange.opacity(0.1))
            }

            Divider().background(Color.white.opacity(0.15))

            // Pending image preview strip
            if pendingUserImage != nil {
                HStack(spacing: 8) {
                    if let imgData = pendingUserImage, let nsImage = NSImage(data: imgData) {
                        Image(nsImage: nsImage)
                            .resizable().scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2)))
                    }
                    Text("Image attached").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Button(action: { pendingUserImage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.4))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }

            HStack(spacing: 10) {
                Button(action: { showTutorialPrompt = true }) {
                    Image(systemName: "graduationcap.fill").font(.title3).foregroundColor(.yellow)
                }.buttonStyle(.plain).help("AI Tutorial").disabled(!aiSettings.isConfigured || isTutorialLoading)

                Button(action: pickOrPasteImage) {
                    Image(systemName: pendingUserImage != nil ? "photo.fill" : "photo")
                        .font(.title3)
                        .foregroundColor(pendingUserImage != nil ? .green : .white.opacity(0.5))
                }.buttonStyle(.plain).help("Attach image (or ⌘V to paste)")

                TextField("Describe your shader goal...", text: $inputText)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(.white)
                    .onSubmit { handleSubmit() }

                if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button(action: handleSubmit) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                            .foregroundColor(inputText.isEmpty || !aiSettings.isConfigured ? .white.opacity(0.2) : .cyan)
                    }.buttonStyle(.plain).disabled(inputText.isEmpty || !aiSettings.isConfigured || isLoading)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                handleImageDrop(providers)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showTutorialPrompt) {
            AITutorialPromptView(topic: $tutorialTopic, isLoading: $isTutorialLoading, onGenerate: { generateTutorial() })
        }
        .onChange(of: compilationError) { _, newError in
            guard pendingAutoFix else { return }
            if let error = newError, autoFixAttempts < maxAutoFixAttempts {
                pendingAutoFix = false
                autoFixAttempts += 1
                autoFixCompilationError(error)
            } else {
                pendingAutoFix = false
                if compilationError == nil { autoFixAttempts = 0 }
            }
        }
    }

    // MARK: - Compilation Awaiter

    /// Thread-safe guard ensuring a CheckedContinuation is resumed exactly once.
    private final class OnceGuard: @unchecked Sendable {
        private var done = false
        func tryOnce() -> Bool {
            guard !done else { return false }
            done = true
            return true
        }
    }

    // MARK: - Direct SSE Streaming

    /// Performs a streaming HTTP request directly from the UI Task, with zero
    /// actor crossings. Updates `streamingThinking` on every token so the user
    /// sees real-time output. Returns the full accumulated text.
    private func streamDirectSSE(
        systemPrompt: String,
        userContent: String,
        captured: CapturedAISettings,
        imageData: Data?
    ) async -> String {
        var accumulated = ""

        // Diagnostic: if this text never appears, @State updates from Task are broken
        streamingThinking = "⏳ Connecting to \(captured.provider.rawValue)..."

        do {
            let req = try buildStreamingURLRequest(
                systemPrompt: systemPrompt,
                userContent: userContent,
                captured: captured,
                imageData: imageData
            )

            // Use a custom session (URLSession.shared may have sandbox restrictions)
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300
            config.timeoutIntervalForResource = 600
            let session = URLSession(configuration: config)

            streamingThinking = "⏳ Waiting for \(captured.provider.rawValue) response..."

            let (bytes, response) = try await session.bytes(for: req)

            guard let http = response as? HTTPURLResponse else {
                streamingThinking = "❌ No HTTP response received"
                return ""
            }

            guard (200...299).contains(http.statusCode) else {
                var errorBody = ""
                for try await line in bytes.lines { errorBody += line }
                let preview = String(errorBody.prefix(300))
                streamingThinking = "❌ HTTP \(http.statusCode): \(preview)"
                return ""
            }

            streamingThinking = "⏳ Streaming response..."

            var tokenCount = 0
            var rawLineCount = 0
            var firstRawLines: [String] = []

            if captured.provider == .gemini {
                // Gemini sends literal newline bytes (0x0A) inside JSON "text" values
                // instead of the JSON escape sequence \n. This breaks line-based SSE
                // parsing because bytes.lines splits on every 0x0A, fragmenting JSON.
                //
                // Strategy: each SSE event starts with "data: ". When we see a NEW
                // "data:" line, parse the PREVIOUS buffer. All other lines (including
                // empty lines that are really literal newlines) are continuations.
                // Before JSON parsing, we replace literal newlines with the JSON
                // escape \n so JSONSerialization can handle it.
                var geminiBuffer = ""

                for try await line in bytes.lines {
                    rawLineCount += 1
                    if firstRawLines.count < 3 { firstRawLines.append(String(line.prefix(120))) }

                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("data:") {
                        if !geminiBuffer.isEmpty {
                            if let text = parseGeminiChunkSanitized(geminiBuffer) {
                                accumulated += text
                                tokenCount += 1
                                streamingThinking = accumulated
                            }
                        }
                        geminiBuffer = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    } else {
                        if !geminiBuffer.isEmpty {
                            geminiBuffer += "\n" + line
                        }
                    }
                }

                if !geminiBuffer.isEmpty {
                    if let text = parseGeminiChunkSanitized(geminiBuffer) {
                        accumulated += text
                        tokenCount += 1
                        streamingThinking = accumulated
                    }
                }
            } else {
                // Standard SSE parsing for OpenAI / Anthropic
                var parser = SSELineParser()
                for try await line in bytes.lines {
                    rawLineCount += 1
                    if firstRawLines.count < 3 { firstRawLines.append(String(line.prefix(120))) }
                    if let event = parser.feedLine(line) {
                        let text: String?
                        switch captured.provider {
                        case .openai:   text = parseOpenAIDelta(event.data)
                        case .anthropic: text = parseAnthropicDelta(event.data, event: event.event)
                        case .gemini:   text = nil
                        }
                        if let t = text {
                            accumulated += t
                            tokenCount += 1
                            streamingThinking = accumulated
                        }
                    }
                }
                if let event = parser.feedLine("") {
                    let text: String?
                    switch captured.provider {
                    case .openai:   text = parseOpenAIDelta(event.data)
                    case .anthropic: text = parseAnthropicDelta(event.data, event: event.event)
                    case .gemini:   text = nil
                    }
                    if let t = text {
                        accumulated += t
                        tokenCount += 1
                        streamingThinking = accumulated
                    }
                }
            }

            if tokenCount == 0 && accumulated.isEmpty {
                let preview = firstRawLines.joined(separator: "\n")
                streamingThinking = "⚠️ 0 tokens / \(rawLineCount) lines.\n\(preview)"
                return ""
            }

        } catch {
            streamingThinking = "❌ Stream error: \(error.localizedDescription)"
            if accumulated.isEmpty { return "" }
        }

        streamingThinking = ""
        return accumulated
    }

    /// Builds a URLRequest for the SSE streaming endpoint based on the provider.
    private func buildStreamingURLRequest(
        systemPrompt: String,
        userContent: String,
        captured: CapturedAISettings,
        imageData: Data?
    ) throws -> URLRequest {
        switch captured.provider {
        case .openai:
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 300
            req.setValue("Bearer \(captured.apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var userPart: Any = userContent
            if let img = imageData {
                userPart = [
                    ["type": "text", "text": userContent],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(img.base64EncodedString())", "detail": "low"]]
                ] as [[String: Any]]
            }
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": captured.model, "stream": true, "max_tokens": 4096,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPart]
                ]
            ] as [String: Any])
            return req

        case .anthropic:
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 300
            req.setValue(captured.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var userPart: Any = userContent
            if let img = imageData {
                userPart = [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": img.base64EncodedString()]],
                    ["type": "text", "text": userContent]
                ] as [[String: Any]]
            }
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": captured.model, "max_tokens": 4096, "stream": true,
                "system": systemPrompt,
                "messages": [["role": "user", "content": userPart]]
            ] as [String: Any])
            return req

        case .gemini:
            var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(captured.model):streamGenerateContent?alt=sse&key=\(captured.apiKey)")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 300
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var parts: [[String: Any]] = [["text": userContent]]
            if let img = imageData {
                parts.append(["inlineData": ["mimeType": "image/jpeg", "data": img.base64EncodedString()]])
            }
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "contents": [["role": "user", "parts": parts]],
                "systemInstruction": ["parts": [["text": systemPrompt]]]
            ] as [String: Any])
            return req
        }
    }

    /// Applies agent actions and reliably awaits the compilation result.
    ///
    /// The notification listener is installed BEFORE actions are applied, eliminating
    /// the race condition where compilation finishes before we start listening.
    /// After `onAgentActions` modifies state, SwiftUI's next `updateNSView` triggers
    /// `compileObject2DPipelines()` / `compileMeshPipeline()`, which posts the result.
    ///
    /// **Shape-lock gate**: If the actions contain a `requestShapeLock`, the plan
    /// pauses and waits for the user to approve or deny via the system alert.
    /// Only after approval does the plan proceed to the next step where the AI
    /// can generate shader code that references `_sdf_shape()`.
    private func applyActionsAndCheckCompilation(_ actions: [AgentAction]) async -> String? {
        let hasShapeLock = actions.contains { $0.type == .requestShapeLock }

        if hasShapeLock {
            return await waitForShapeLockApproval(actions: actions)
        }

        return await withCheckedContinuation { cont in
            let once = OnceGuard()
            var observer: NSObjectProtocol?

            observer = NotificationCenter.default.addObserver(
                forName: .shaderCompilationResult, object: nil, queue: .main
            ) { notification in
                guard once.tryOnce() else { return }
                if let obs = observer { NotificationCenter.default.removeObserver(obs) }
                cont.resume(returning: notification.object as? String)
            }

            onAgentActions(actions)

            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                guard once.tryOnce() else { return }
                if let obs = observer { NotificationCenter.default.removeObserver(obs) }
                cont.resume(returning: nil)
            }
        }
    }

    /// Waits for the user to approve/deny a shape-lock request before the plan
    /// proceeds. Returns `nil` on approval, an error string on denial/timeout.
    private func waitForShapeLockApproval(actions: [AgentAction]) async -> String? {
        await withCheckedContinuation { cont in
            let once = OnceGuard()
            var observer: NSObjectProtocol?

            observer = NotificationCenter.default.addObserver(
                forName: .shapeLockResolved, object: nil, queue: .main
            ) { notification in
                guard once.tryOnce() else { return }
                if let obs = observer { NotificationCenter.default.removeObserver(obs) }
                let approved = notification.object as? Bool ?? false
                cont.resume(returning: approved ? nil : "SHAPE_LOCK_DENIED")
            }

            onAgentActions(actions)

            DispatchQueue.main.asyncAfter(deadline: .now() + 120.0) {
                guard once.tryOnce() else { return }
                if let obs = observer { NotificationCenter.default.removeObserver(obs) }
                cont.resume(returning: "SHAPE_LOCK_DENIED")
            }
        }
    }

    // MARK: - Image Attachment

    private func pickOrPasteImage() {
        // Try clipboard first
        let pb = NSPasteboard.general
        if let imgType = pb.availableType(from: [.tiff, .png]),
           let data = pb.data(forType: imgType),
           let nsImage = NSImage(data: data),
           let jpeg = compressForAI(nsImage) {
            pendingUserImage = jpeg
            return
        }
        // Fall back to file picker
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let nsImage = NSImage(contentsOf: url),
           let jpeg = compressForAI(nsImage) {
            pendingUserImage = jpeg
        }
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data, let nsImage = NSImage(data: data),
                          let jpeg = compressForAI(nsImage) else { return }
                    DispatchQueue.main.async { pendingUserImage = jpeg }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          let nsImage = NSImage(contentsOf: url),
                          let jpeg = compressForAI(nsImage) else { return }
                    DispatchQueue.main.async { pendingUserImage = jpeg }
                }
                return true
            }
        }
        return false
    }

    /// Downscale and compress an image to JPEG for API submission.
    /// Uses thread-safe CGContext instead of NSImage.lockFocus.
    private func compressForAI(_ image: NSImage, maxDimension: CGFloat = 1024) -> Data? {
        MetalRenderer.resizeAndCompress(image, maxDimension: Int(maxDimension), quality: 0.7)
    }

    private func handleSubmit() {
        sendPlanRequest()
    }

    /// Plan Mode: generates a plan, then executes each step sequentially.
    private func sendPlanRequest() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, aiSettings.isConfigured else { return }
        let userImg = pendingUserImage
        var userMsg = ChatMessage(role: .user, content: text)
        userMsg.userImage = userImg
        messages.append(userMsg)
        let userMsgIdx = messages.count - 1
        inputText = ""; pendingUserImage = nil; isLoading = true; errorMessage = nil; streamingThinking = ""
        let context = buildContext()
        let dataFlowDesc = buildDataFlowDescription()
        let captured = aiSettings.captured
        Task {
            let snapshot = await Task.detached { MetalRenderer.current?.captureForAI() }.value
            messages[userMsgIdx].renderSnapshot = snapshot
            let combinedImage = userImg ?? snapshot
            do {
                // Phase 1: Stream plan generation — direct SSE, no actor crossings
                let accumulated = await streamDirectSSE(
                    systemPrompt: await AIService.shared.buildPlanSystemPrompt(
                        request: text, context: context, dataFlowDescription: dataFlowDesc
                    ),
                    userContent: text,
                    captured: captured,
                    imageData: combinedImage
                )

                let plan: AgentPlan
                if accumulated.isEmpty {
                    streamingThinking = "⏳ Streaming failed, retrying with non-streaming API..."
                    plan = try await AIService.shared.generatePlan(
                        request: text, context: context,
                        dataFlowDescription: dataFlowDesc,
                        canvasMode: canvasMode, settings: aiSettings,
                        imageData: combinedImage
                    )
                    streamingThinking = ""
                } else {
                    streamingThinking = "⏳ Parsing plan..."
                    plan = try await AIService.shared.parsePlanResponse(from: accumulated)
                    streamingThinking = ""
                }

                await MainActor.run {
                    currentPlan = plan
                    var planMsg = ChatMessage(role: .assistant, content: "Plan generated: \(plan.title)")
                    planMsg.plan = plan
                    messages.append(planMsg)
                }
                await executePlan(plan, context: context, dataFlowDesc: dataFlowDesc)
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run { streamingThinking = ""; errorMessage = error.localizedDescription; isLoading = false }
            }
        }
    }

    /// Executes all nodes in a plan sequentially with context handoff.
    private func executePlan(_ plan: AgentPlan, context: String, dataFlowDesc: String) async {
        var mutablePlan = plan
        var handoffSummary: String?
        let maxCompileFixes = 20

        for i in mutablePlan.nodes.indices {
            mutablePlan.nodes[i].status = .running
            mutablePlan.recalculate()
            await MainActor.run { currentPlan = mutablePlan; updatePlanInMessages(mutablePlan) }

            let stepResult = await executePlanStepWithValidation(
                plan: &mutablePlan, stepIndex: i,
                dataFlowDesc: dataFlowDesc,
                handoffSummary: handoffSummary,
                maxCompileFixes: maxCompileFixes
            )

            if stepResult.succeeded {
                handoffSummary = stepResult.handoff
            }

            mutablePlan.recalculate()
            await MainActor.run { currentPlan = mutablePlan; updatePlanInMessages(mutablePlan) }
        }

        // Final summary
        mutablePlan.contextSummary = handoffSummary ?? ""
        mutablePlan.recalculate()
        let failedNodes = mutablePlan.nodes.filter { $0.status == .failed }
        let completedNodes = mutablePlan.nodes.filter { $0.status == .completed }

        await MainActor.run {
            currentPlan = mutablePlan
            updatePlanInMessages(mutablePlan)

            if failedNodes.isEmpty {
                var summaryMsg = ChatMessage(role: .assistant,
                    content: "✓ \(mutablePlan.title) — all \(mutablePlan.totalSteps) steps completed.")
                summaryMsg.plan = mutablePlan
                messages.append(summaryMsg)
            } else {
                var summaryText = "⚠️ \(mutablePlan.title) — \(completedNodes.count)/\(mutablePlan.totalSteps) steps succeeded, \(failedNodes.count) failed.\n"
                summaryText += "\nIf you'd like, you can describe the issue differently or break it into simpler steps and I'll try again."
                var summaryMsg = ChatMessage(role: .assistant, content: summaryText)
                summaryMsg.plan = mutablePlan
                messages.append(summaryMsg)
            }
        }
    }

    /// Updates the plan object in the original plan message for live progress display.
    private func updatePlanInMessages(_ plan: AgentPlan) {
        if let idx = messages.lastIndex(where: { $0.plan?.id == plan.id }) {
            messages[idx].plan = plan
        }
    }

    /// Executes a single plan step with full self-validation:
    /// 1. Generate and apply shader actions
    /// 2. Await shader compilation result
    /// 3. If compilation fails → auto-fix up to N times
    /// 4. After compile success → capture screenshot and verify visual result
    /// 5. Only then mark step as completed
    private struct StepResult {
        let succeeded: Bool
        let handoff: String?
    }

    private func executePlanStepWithValidation(
        plan: inout AgentPlan, stepIndex i: Int,
        dataFlowDesc: String, handoffSummary: String?,
        maxCompileFixes: Int
    ) async -> StepResult {
        let stepTitle = plan.nodes[i].title
        let stepDesc = plan.nodes[i].description

        // Phase 1: Generate shader code (with streaming)
        do {
            let snapshot = await Task.detached { MetalRenderer.current?.captureForAI() }.value
            let freshContext = await MainActor.run { buildContext() }
            let captured = await MainActor.run { aiSettings.captured }

            let stepSystemPrompt = await AIService.shared.buildStepSystemPrompt(
                node: plan.nodes[i], context: freshContext,
                dataFlowDescription: dataFlowDesc,
                canvasMode: canvasMode, handoffSummary: handoffSummary
            )
            let stepUserContent = "Execute plan step: \(plan.nodes[i].title)\n\(plan.nodes[i].description)"

            let accumulated = await streamDirectSSE(
                systemPrompt: stepSystemPrompt,
                userContent: stepUserContent,
                captured: captured,
                imageData: snapshot
            )

            let response: AgentResponse
            if accumulated.isEmpty {
                streamingThinking = "⏳ Retrying step with non-streaming API..."
                response = try await AIService.shared.executePlanStep(
                    node: plan.nodes[i], context: freshContext,
                    dataFlowDescription: dataFlowDesc, canvasMode: canvasMode,
                    settings: aiSettings, handoffSummary: handoffSummary,
                    imageData: snapshot
                )
                streamingThinking = ""
            } else {
                do {
                    response = try await AIService.shared.parseAgentResponse(from: accumulated)
                } catch {
                    response = AgentResponse.plainText(accumulated)
                }
            }

            plan.nodes[i].actions = response.actions.isEmpty ? nil : response.actions
            plan.nodes[i].thinking = response.thinking

            guard !response.actions.isEmpty else {
                await MainActor.run {
                    plan.nodes[i].status = .completed
                    var msg = ChatMessage(role: .assistant, content: "✓ \(stepTitle): \(response.explanation)")
                    msg.thinking = response.thinking
                    messages.append(msg)
                }
                return StepResult(succeeded: true, handoff: nil)
            }

            // Phase 2: Apply actions and await compilation (or shape-lock approval)
            let compError = await applyActionsAndCheckCompilation(response.actions)

            if compError == "SHAPE_LOCK_DENIED" {
                await MainActor.run {
                    plan.nodes[i].status = .failed
                    plan.nodes[i].error = "Shape lock denied by user"
                    messages.append(ChatMessage(role: .assistant,
                        content: "✗ \(stepTitle): Shape lock was denied — edge-aware effects require a locked shape."))
                }
                return StepResult(succeeded: false, handoff: nil)
            }

            if let compError {
                // Phase 3: Compilation failed — auto-fix loop
                let fixResult = await autoFixCompilationLoop(
                    stepTitle: stepTitle, initialError: compError,
                    dataFlowDesc: dataFlowDesc, maxAttempts: maxCompileFixes
                )

                if !fixResult.fixed {
                    let analysis = await analyzeFailure(
                        stepTitle: stepTitle,
                        stepDesc: stepDesc,
                        error: fixResult.lastError,
                        attempts: maxCompileFixes
                    )
                    await MainActor.run {
                        plan.nodes[i].status = .failed
                        plan.nodes[i].error = analysis
                        messages.append(ChatMessage(role: .assistant,
                            content: "✗ \(stepTitle)\n\n\(analysis)"))
                    }
                    return StepResult(succeeded: false, handoff: nil)
                }

                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant,
                        content: "🔧 \(stepTitle): Compilation error auto-fixed."))
                }
            }

            // Phase 4: Compilation succeeded — visual verification
            // In 2D mode with preview clones, capture ONLY the AI preview
            // object so the multimodal model evaluates its own output in
            // isolation rather than guessing which object is the AI's.
            try? await Task.sleep(for: .milliseconds(300))

            let previewTargetName: String? = canvasMode.is2D
                ? response.actions
                    .first(where: { $0.type == .setObjectShader2D })
                    .map { "AI: \($0.targetObjectName ?? $0.name)" }
                : nil

            let previewObjectID: UUID? = previewTargetName.flatMap { name in
                MetalRenderer.current?.objects2D
                    .first(where: { $0.isAIPreview && $0.name == name })?.id
            }

            let verifySnapshot: Data? = await Task.detached {
                if let pid = previewObjectID {
                    return MetalRenderer.current?.capturePreviewObject(pid)
                }
                return MetalRenderer.current?.captureForAI()
            }.value
            var verificationNote = ""

            if let verifyData = verifySnapshot {
                let verifyContext = await MainActor.run { buildContext() }
                let verifyHint = previewObjectID != nil
                    ? "\nThe screenshot shows ONLY the AI-generated preview object rendered in isolation. Evaluate whether it matches the step goal."
                    : ""
                do {
                    let result = try await AIService.shared.verifyStepResult(
                        stepTitle: stepTitle, stepDescription: stepDesc + verifyHint,
                        screenshot: verifyData, context: verifyContext,
                        canvasMode: canvasMode, settings: aiSettings
                    )
                    if !result.passed {
                        verificationNote = "\n⚠️ Visual check: \(result.feedback)"
                        let fixContext = await MainActor.run { buildContext() }
                        let fixHandoff = (handoffSummary ?? "") +
                            "\n\n--- VISUAL VERIFICATION FAILED ---\n\(result.feedback)\nPlease adjust the shader to fix the visual issue.\n"

                        do {
                            let fixResponse = try await AIService.shared.executePlanStep(
                                node: plan.nodes[i], context: fixContext,
                                dataFlowDescription: dataFlowDesc, canvasMode: canvasMode,
                                settings: aiSettings, handoffSummary: fixHandoff,
                                imageData: verifyData
                            )
                            if !fixResponse.actions.isEmpty {
                                let fixCompError = await applyActionsAndCheckCompilation(fixResponse.actions)
                                if fixCompError != nil {
                                    verificationNote += " (visual fix also had compile error)"
                                } else {
                                    verificationNote = "\n✓ Visual issue addressed"
                                }
                            }
                        } catch {
                            verificationNote += " (visual fix attempt failed: \(error.localizedDescription))"
                        }
                    }
                } catch {
                    verificationNote = ""
                }
            }

            // Phase 5: Mark as completed
            await MainActor.run {
                plan.nodes[i].status = .completed
                plan.nodes[i].error = nil
                var msg = ChatMessage(role: .assistant,
                    content: "✓ \(stepTitle): \(response.explanation)\(verificationNote)")
                msg.executedActions = response.actions.isEmpty ? nil : response.actions
                msg.thinking = response.thinking
                msg.renderSnapshot = verifySnapshot
                messages.append(msg)
            }

            let stateChanges = response.actions.map { "\($0.type.rawValue): \($0.name)" }
            let handoff = ContextManager.buildHandoffSummary(
                completedNode: plan.nodes[i], stateChanges: stateChanges
            )
            return StepResult(succeeded: true, handoff: handoff)

        } catch {
            let analysis = await analyzeFailure(
                stepTitle: stepTitle,
                stepDesc: stepDesc,
                error: error.localizedDescription,
                attempts: 0
            )
            await MainActor.run {
                plan.nodes[i].status = .failed
                plan.nodes[i].error = analysis
                messages.append(ChatMessage(role: .assistant,
                    content: "✗ \(stepTitle)\n\n\(analysis)"))
            }
            return StepResult(succeeded: false, handoff: nil)
        }
    }

    /// Asks the AI to analyze a failure and produce a human-readable explanation
    /// with root cause, what was tried, and suggestions for the user.
    private func analyzeFailure(
        stepTitle: String, stepDesc: String,
        error: String, attempts: Int
    ) async -> String {
        let prompt = """
        A shader development step failed. Analyze the error and write a CONCISE explanation
        for the user in their language. Include:
        1. What went wrong (root cause in plain language)
        2. What was attempted (\(attempts) auto-fix attempts if > 0)
        3. A concrete suggestion: what the user could try differently

        Step: "\(stepTitle)"
        Goal: \(stepDesc)
        Error: \(error)

        Respond in plain text (NOT JSON). Keep it under 4 sentences. Use the same language the user used.
        """
        let captured = await MainActor.run { aiSettings.captured }
        do {
            let analysis = try await AIService.shared.agentChat(
                messages: [ChatMessage(role: .user, content: "Analyze this failure")],
                context: prompt, dataFlowDescription: "",
                canvasMode: canvasMode, settings: aiSettings
            )
            return analysis.explanation
        } catch {
            // Fallback: just format the raw error nicely
            var text = "编译失败"
            if attempts > 0 { text += "（已尝试自动修复 \(attempts) 次）" }
            text += "\n\n错误详情:\n\(error)"
            text += "\n\n建议: 尝试简化需求，或将复杂效果拆分为更小的步骤。"
            return text
        }
    }

    /// Attempts to fix compilation errors by sending them back to the AI.
    /// Returns whether the fix succeeded and the last error if it didn't.
    private struct CompileFixResult { let fixed: Bool; let lastError: String }

    /// Escalating fix strategy based on attempt count:
    ///   1-3: targeted fix of the specific error
    ///   4-6: rewrite the problematic function from scratch
    ///   7+:  completely rethink the approach, use a simpler technique
    private static func fixStrategy(attempt: Int) -> (label: String, instruction: String) {
        switch attempt {
        case 1...3:
            return ("fix", "Fix this specific compilation error. Keep the overall approach but correct the syntax/type issue.")
        case 4...6:
            return ("rewrite", "REWRITE the shader from scratch. The previous approach had fundamental issues. Use a simpler, more standard MSL pattern.")
        default:
            return ("simplify", "Use the SIMPLEST possible approach. Strip the effect to its bare minimum — a basic version that definitely compiles. Avoid advanced techniques. Prioritize compilation over visual quality.")
        }
    }

    private func autoFixCompilationLoop(
        stepTitle: String, initialError: String,
        dataFlowDesc: String, maxAttempts: Int
    ) async -> CompileFixResult {
        var currentError = initialError
        var previousErrors: [String] = [initialError]

        for attempt in 1...maxAttempts {
            let (strategyLabel, strategyInstruction) = Self.fixStrategy(attempt: attempt)

            await MainActor.run {
                messages.append(ChatMessage(role: .assistant,
                    content: "🔧 \(stepTitle) — attempt \(attempt) [\(strategyLabel)]:\n\(currentError)"))
            }

            let fixContext = await MainActor.run { buildContext() }
            let snapshot = await Task.detached { MetalRenderer.current?.captureForAI() }.value

            // Include error history so the AI doesn't repeat failed approaches
            let errorHistory = previousErrors.count > 1
                ? "\n\nPREVIOUS FAILED ATTEMPTS (\(previousErrors.count)):\n" +
                  previousErrors.enumerated().map { "  Attempt \($0.offset+1): \($0.element.prefix(150))" }.joined(separator: "\n")
                : ""

            let fixMsg = ChatMessage(role: .user,
                content: """
                Shader compilation error in step "\(stepTitle)" (attempt \(attempt)):
                \(currentError)

                STRATEGY: \(strategyInstruction)
                \(errorHistory)
                """)

            do {
                let response = try await AIService.shared.agentChat(
                    messages: [fixMsg], context: fixContext,
                    dataFlowDescription: dataFlowDesc,
                    canvasMode: canvasMode, settings: aiSettings,
                    imageData: snapshot
                )

                if !response.actions.isEmpty {
                    let newError = await applyActionsAndCheckCompilation(response.actions)

                    if newError == nil {
                        return CompileFixResult(fixed: true, lastError: "")
                    }
                    currentError = newError!
                    previousErrors.append(currentError)
                } else {
                    return CompileFixResult(fixed: false, lastError: "AI could not produce a fix: \(response.explanation)")
                }
            } catch {
                // Network/API errors: don't count as a "real" failure, just retry
                if attempt < maxAttempts {
                    continue
                }
                return CompileFixResult(fixed: false, lastError: "Request failed: \(error.localizedDescription)")
            }
        }

        return CompileFixResult(fixed: false, lastError: currentError)
    }

    /// Requests an AI-generated tutorial and loads it into the tutorial panel.
    private func generateTutorial() {
        guard aiSettings.isConfigured, !tutorialTopic.isEmpty else { return }
        isTutorialLoading = true; showTutorialPrompt = false; errorMessage = nil
        let topic = tutorialTopic
        Task {
            do {
                let steps = try await AIService.shared.generateTutorial(topic: topic, settings: aiSettings)
                await MainActor.run { isTutorialLoading = false; messages.append(ChatMessage(role: .assistant, content: "Tutorial \"\(topic)\" generated (\(steps.count) steps). Loading...")); onGenerateTutorial(steps) }
            } catch {
                await MainActor.run { isTutorialLoading = false; errorMessage = error.localizedDescription }
            }
        }
    }

    /// Automatically sends a fix request when compilation errors are detected
    /// after the AI executes shader actions.
    private func autoFixCompilationError(_ error: String) {
        let strategy = autoFixAttempts >= maxAutoFixAttempts
            ? "REWRITE the shader from scratch (previous fix attempts failed)"
            : "fix the compilation error"
        let errorMsg = "⚠️ Shader Compilation Error (attempt \(autoFixAttempts)/\(maxAutoFixAttempts), strategy: \(strategy)):\n\(error)"
        messages.append(ChatMessage(role: .user, content: errorMsg))
        isLoading = true; errorMessage = nil
        let context = buildContext()
        let dataFlowDesc = buildDataFlowDescription()
        Task {
            let snapshot = await Task.detached { MetalRenderer.current?.captureForAI() }.value
            do {
                let response = try await AIService.shared.agentChat(
                    messages: messages, context: context,
                    dataFlowDescription: dataFlowDesc,
                    canvasMode: canvasMode, settings: aiSettings,
                    imageData: snapshot
                )
                await MainActor.run {
                    if !response.actions.isEmpty {
                        onAgentActions(response.actions)
                        pendingAutoFix = true
                    }
                    var msg = ChatMessage(role: .assistant, content: response.explanation)
                    msg.executedActions = response.actions.isEmpty ? nil : response.actions
                    msg.barriers = response.canFulfill ? nil : response.barriers
                    msg.thinking = response.thinking
                    messages.append(msg)
                    isLoading = false
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
            }
        }
    }

    /// Builds a rich scene state context using ContextManager + ShaderAnalyzer.
    /// Includes the currently selected object's details for engineering touch.
    private func buildContext() -> String {
        ContextManager.buildSceneState(
            canvasMode: canvasMode,
            activeShaders: activeShaders,
            objects2D: objects2D,
            sharedVertexCode2D: sharedVertexCode2D,
            sharedFragmentCode2D: sharedFragmentCode2D,
            dataFlowConfig: dataFlowConfig,
            dataFlow2DConfig: dataFlow2DConfig,
            paramValues: paramValues,
            compilationError: compilationError,
            meshType: meshType,
            rotationAngle: rotationAngle,
            selectedObjectID: selectedObjectID,
            animationTime: MetalRenderer.current?.time
        )
    }

    /// Builds a description of the current Data Flow configuration for the Agent.
    /// Adapts to the active canvas mode.
    private func buildDataFlowDescription() -> String {
        if canvasMode.is2D {
            return buildDataFlowDescription2D()
        } else {
            return buildDataFlowDescription3D()
        }
    }

    private func buildDataFlowDescription3D() -> String {
        var desc = "VertexOut fields available to vertex/fragment shaders: position [[position]]"
        if dataFlowConfig.normalEnabled { desc += ", normalOS (float3)" }
        if dataFlowConfig.uvEnabled { desc += ", uv (float2)" }
        if dataFlowConfig.timeEnabled { desc += ", time (float)" }
        if dataFlowConfig.worldPositionEnabled { desc += ", positionWS (float3)" }
        if dataFlowConfig.worldNormalEnabled { desc += ", normalWS (float3)" }
        if dataFlowConfig.viewDirectionEnabled { desc += ", viewDirWS (float3)" }
        desc += "\nVertexIn fields: positionOS (float3) [[attribute(0)]]"
        if dataFlowConfig.normalEnabled { desc += ", normalOS (float3) [[attribute(1)]]" }
        if dataFlowConfig.uvEnabled { desc += ", uv (float2) [[attribute(2)]]" }
        return desc
    }

    private func buildDataFlowDescription2D() -> String {
        var desc = "2D VertexOut fields: position [[position]], texCoord (float2), shapeAspect (float), cornerRadius (float)"
        if dataFlow2DConfig.timeEnabled { desc += ", time (float)" }
        if dataFlow2DConfig.mouseEnabled { desc += ", mouse (float2)" }
        if dataFlow2DConfig.objectPositionEnabled { desc += ", objectPosition (float2)" }
        if dataFlow2DConfig.screenUVEnabled { desc += ", screenUV (float2)" }
        desc += "\n2D Uniforms: resolution (float2), time (float), mouseX (float), mouseY (float)"
        desc += "\nAvailable shapes: Rectangle, Rounded Rect, Circle, Capsule"
        return desc
    }
}

// MARK: - Message Bubble

/// Renders a single chat message with role-appropriate styling.
///
/// - User messages: blue background, right-aligned, default font
/// - Assistant messages: dark background, left-aligned, monospaced font, sparkle icon
///   - Shows executed Agent actions (add/modify layer) as green confirmation badges
///   - Shows technical barriers as orange warning blocks when the request can't be fulfilled
struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "sparkle").font(.system(size: 14)).foregroundColor(.purple).frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let snapshot = message.renderSnapshot {
                    SnapshotThumbnail(imageData: snapshot)
                }
                if let userImg = message.userImage {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.fill").font(.system(size: 9)).foregroundColor(.green)
                        Text("User reference").font(.system(size: 9)).foregroundColor(.white.opacity(0.5))
                    }
                    SnapshotThumbnail(imageData: userImg)
                }

                Text(verbatim: message.content)
                    .font(.system(size: 12.5, design: message.role == .assistant ? .monospaced : .default))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled).lineSpacing(3)

                // Thinking section (collapsible)
                if let thinking = message.thinking, !thinking.isEmpty {
                    ThinkingSection(text: thinking)
                }

                // Plan tree view
                if let plan = message.plan {
                    AgentPlanView(plan: plan)
                }

                if let actions = message.executedActions, !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                            let isLock = action.type == .requestShapeLock
                            HStack(spacing: 4) {
                                Image(systemName: isLock ? "lock.fill" : (action.type == .addLayer ? "plus.circle.fill" : "pencil.circle.fill"))
                                    .foregroundColor(isLock ? .orange : .green).font(.system(size: 11))
                                Text(actionLabel(action))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(isLock ? .orange.opacity(0.9) : .green.opacity(0.9))
                            }
                        }
                    }
                    .padding(6)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(6)
                }

                if let barriers = message.barriers, !barriers.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange).font(.system(size: 11))
                            Text("Technical Barriers:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        ForEach(barriers, id: \.self) { barrier in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•").foregroundColor(.orange.opacity(0.7)).font(.system(size: 11))
                                Text(barrier).font(.system(size: 11)).foregroundColor(.orange.opacity(0.8))
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(message.role == .user ? Color.blue.opacity(0.25) : Color.white.opacity(0.08))
            .cornerRadius(10)

            if message.role == .user {
                Image(systemName: "person.circle.fill").font(.system(size: 14)).foregroundColor(.blue).frame(width: 20)
            }
        }.frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func actionLabel(_ action: AgentAction) -> String {
        switch action.type {
        case .addLayer:
            return "✓ Added \(action.category.capitalized) Layer: \"\(action.name)\""
        case .modifyLayer:
            return "✓ Modified: \"\(action.targetLayerName ?? action.name)\""
        case .addObject2D:
            return "✓ Added 2D Object: \"\(action.name)\" (\(action.shapeType ?? "Rounded Rect"))"
        case .modifyObject2D:
            return "✓ Modified Object: \"\(action.targetObjectName ?? action.name)\""
        case .setSharedShader2D:
            return "✓ Updated Shared \(action.category.capitalized) Shader"
        case .setObjectShader2D:
            return "✓ Set \(action.category.capitalized) on \"\(action.targetObjectName ?? action.name)\""
        case .requestShapeLock:
            return "🔒 Shape Lock Requested: \"\(action.targetObjectName ?? action.name)\""
        }
    }
}

// MARK: - AI Tutorial Prompt

/// A modal sheet for entering a topic to generate an AI-powered tutorial.
///
/// Provides a text field for custom topics and a list of suggested topics
/// (e.g. "Build a PBR metallic shader from scratch") for quick selection.
struct AITutorialPromptView: View {
    @Binding var topic: String
    @Binding var isLoading: Bool
    var onGenerate: () -> Void
    @Environment(\.dismiss) private var dismiss

    let suggestions = [
        "Build a PBR metallic shader from scratch",
        "Create a water ripple post-processing effect",
        "Animate vertices to simulate wind on grass",
        "Make a hologram / scan-line shader effect",
        "Implement a dissolve/disintegration effect",
    ]

    var body: some View {
        VStack(spacing: 16) {
            HStack { Image(systemName: "graduationcap.fill").foregroundColor(.yellow); Text("AI Tutorial").font(.title3.bold()) }
            Text("Describe what shader technique you want to learn.").font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
            TextField("e.g. Build a cel-shading toon shader", text: $topic).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestions").font(.caption.bold()).foregroundColor(.secondary)
                ForEach(suggestions, id: \.self) { s in
                    Button(action: { topic = s }) {
                        HStack { Image(systemName: "lightbulb").font(.caption).foregroundColor(.yellow); Text(s).font(.system(size: 11)).foregroundColor(.primary).multilineTextAlignment(.leading) }
                    }.buttonStyle(.plain)
                }
            }.padding(10).background(Color.yellow.opacity(0.05)).cornerRadius(8)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: onGenerate) { HStack { Image(systemName: "sparkles"); Text("Generate") } }.keyboardShortcut(.defaultAction).disabled(topic.isEmpty || isLoading)
            }
        }.padding(24).frame(width: 420)
    }
}
