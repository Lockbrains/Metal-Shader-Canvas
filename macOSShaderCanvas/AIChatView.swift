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
        Color(red: 0.30, green: 0.55, blue: 1.0),
        Color(red: 0.55, green: 0.35, blue: 1.0),
        Color(red: 0.95, green: 0.35, blue: 0.65),
        Color(red: 1.0, green: 0.55, blue: 0.25),
        Color(red: 0.95, green: 0.80, blue: 0.30),
        Color(red: 0.35, green: 0.80, blue: 0.55),
        Color(red: 0.30, green: 0.55, blue: 1.0),
    ]

    var body: some View {
        GeometryReader { geo in
            let diagonal = sqrt(geo.size.width * geo.size.width + geo.size.height * geo.size.height)

            ZStack {
                Circle()
                    .fill(AngularGradient(colors: colors, center: .center))
                    .frame(width: diagonal, height: diagonal)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .mask(
                Rectangle()
                    .overlay(
                        Rectangle()
                            .padding(6)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
            )
            .blur(radius: 12)
            .drawingGroup()
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .allowsHitTesting(false)
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
    let dataFlowConfig: DataFlowConfig
    let onGenerateTutorial: ([TutorialStep]) -> Void
    let onAgentActions: ([AgentAction]) -> Void

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showTutorialPrompt = false
    @State private var tutorialTopic = ""
    @State private var isTutorialLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Message history (scrollable).
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }
                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Thinking...")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }.padding(.horizontal, 16).id("loading")
                        }
                    }.padding(16)
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        if let lastID = messages.last?.id { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }

            // Error banner (shown when API call fails).
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

            Divider().background(Color.white.opacity(0.2))

            // Input bar: tutorial button + text field + send button + close button.
            HStack(spacing: 10) {
                Button(action: { showTutorialPrompt = true }) {
                    Image(systemName: "graduationcap.fill").font(.title3).foregroundColor(.yellow)
                }.buttonStyle(.plain).help("AI Tutorial").disabled(!aiSettings.isConfigured || isTutorialLoading)

                TextField("Ask about your shader...", text: $inputText)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(.white)
                    .onSubmit { sendMessage() }

                if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                            .foregroundColor(inputText.isEmpty || !aiSettings.isConfigured ? .white.opacity(0.2) : .blue)
                    }.buttonStyle(.plain).disabled(inputText.isEmpty || !aiSettings.isConfigured || isLoading)
                }

                Button(action: { withAnimation { isActive = false } }) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.white.opacity(0.4))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.black.opacity(0.35))
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
        .sheet(isPresented: $showTutorialPrompt) {
            AITutorialPromptView(topic: $tutorialTopic, isLoading: $isTutorialLoading, onGenerate: { generateTutorial() })
        }
    }

    /// Sends the user's message to the AI Agent and processes the structured response.
    ///
    /// The Agent analyzes the request, determines if it can be fulfilled by adding/modifying
    /// shader layers, and returns actions + explanation. Actions are executed automatically.
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, aiSettings.isConfigured else { return }
        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""; isLoading = true; errorMessage = nil
        let context = buildContext()
        let dataFlowDesc = buildDataFlowDescription()
        Task {
            do {
                let response = try await AIService.shared.agentChat(
                    messages: messages, context: context,
                    dataFlowDescription: dataFlowDesc, settings: aiSettings
                )
                await MainActor.run {
                    if !response.actions.isEmpty {
                        onAgentActions(response.actions)
                    }
                    var msg = ChatMessage(role: .assistant, content: response.explanation)
                    msg.executedActions = response.actions.isEmpty ? nil : response.actions
                    msg.barriers = response.canFulfill ? nil : response.barriers
                    messages.append(msg)
                    isLoading = false
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
            }
        }
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

    /// Builds a text summary of the user's active shaders for AI context.
    /// Includes shader category, name, and the first 2000 characters of code.
    private func buildContext() -> String {
        if activeShaders.isEmpty { return "Empty canvas, no active shaders." }
        var ctx = "Active shader layers (\(activeShaders.count) total):\n"
        for s in activeShaders {
            ctx += "--- \(s.category.rawValue): \"\(s.name)\" ---\n\(s.code.prefix(2000))\n\n"
        }
        return ctx
    }

    /// Builds a description of the current Data Flow configuration for the Agent.
    private func buildDataFlowDescription() -> String {
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
                Text(verbatim: message.content)
                    .font(.system(size: 12.5, design: message.role == .assistant ? .monospaced : .default))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled).lineSpacing(3)

                if let actions = message.executedActions, !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                            HStack(spacing: 4) {
                                Image(systemName: action.type == .addLayer ? "plus.circle.fill" : "pencil.circle.fill")
                                    .foregroundColor(.green).font(.system(size: 11))
                                Text(actionLabel(action))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green.opacity(0.9))
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
        let cat = action.category.capitalized
        if action.type == .addLayer {
            return "✓ Added \(cat) Layer: \"\(action.name)\""
        } else {
            return "✓ Modified: \"\(action.targetLayerName ?? action.name)\""
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
