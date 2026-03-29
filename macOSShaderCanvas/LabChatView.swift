//
//  LabChatView.swift
//  macOSShaderCanvas
//
//  Phase-driven collaborative discussion view for Lab mode.
//  Unlike AIChatView's Direct/Plan modes, LabChatView is organized around
//  the Lab workflow phases: Reference Analysis → Q&A → Document Drafting →
//  Implementation → Tuning → Adversarial Generation.
//
//  Key differences from AIChatView:
//  - Phase indicator at top showing current workflow stage
//  - Reference embedding from the Reference Board
//  - AI messages can contain actionable parameter suggestions
//  - Phase-appropriate input prompts and AI behavior
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - LabChatView

struct LabChatView: View {
    @Binding var messages: [ChatMessage]
    @Binding var labSession: LabSession
    let references: [ReferenceItem]
    @Binding var projectDocument: ProjectDocument
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
    let onAgentActions: ([AgentAction]) -> Void

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var streamingText = ""
    @State private var pendingUserImage: Data?

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().background(Color.white.opacity(0.15))
            messageList
            errorBanner
            Divider().background(Color.white.opacity(0.15))
            inputArea
        }
    }

    // MARK: - Chat Header

    private var chatHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 11))
                .foregroundColor(.purple)

            Text("Collaborative Discussion")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            phaseContextBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var phaseContextBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: labSession.currentPhase.icon)
                .font(.system(size: 8))
            Text(labSession.currentPhase.displayName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(.cyan)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.cyan.opacity(0.12))
        .cornerRadius(4)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { msg in
                        labMessageBubble(msg)
                            .id(msg.id)
                    }

                    if isLoading {
                        loadingIndicator
                    }
                }
                .padding(12)
            }
            .onChange(of: messages.count) {
                withAnimation {
                    if let lastID = messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func labMessageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "sparkle")
                    .font(.system(size: 10))
                    .foregroundColor(.purple)
                    .padding(.top, 3)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if let imageData = message.userImage, let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 160, maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Text(message.content)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .textSelection(.enabled)

                if let actions = message.executedActions, !actions.isEmpty {
                    actionsSummary(actions)
                }
            }
            .padding(10)
            .background(
                message.role == .user
                    ? Color.blue.opacity(0.15)
                    : Color.white.opacity(0.06)
            )
            .cornerRadius(10)
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.blue.opacity(0.6))
                    .padding(.top, 3)
            }
        }
    }

    private func actionsSummary(_ actions: [AgentAction]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(actions.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.green.opacity(0.7))
                    Text("\(actions[i].type.rawValue): \(actions[i].name)")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.top, 4)
    }

    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.6)
            Text(phaseLoadingText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .id("loading")
    }

    private var phaseLoadingText: String {
        switch labSession.currentPhase {
        case .referenceInput, .analysis: return "Analyzing references..."
        case .documentDrafting: return "Drafting document..."
        case .implementation: return "Writing shader..."
        case .tuning: return "Evaluating parameters..."
        case .adversarial: return "Generating alternatives..."
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(error).font(.system(size: 10)).foregroundColor(.orange).lineLimit(2)
                Spacer()
                Button(action: { errorMessage = nil }) {
                    Image(systemName: "xmark.circle").foregroundColor(.white.opacity(0.4))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 6) {
            if pendingUserImage != nil {
                pendingImageStrip
            }

            HStack(spacing: 8) {
                Button(action: attachReference) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Attach reference from board")

                Button(action: captureRender) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Capture current render")

                TextField(inputPlaceholder, text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .onSubmit { handleSubmit() }

                if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button(action: handleSubmit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(canSubmit ? .purple : .white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var pendingImageStrip: some View {
        HStack(spacing: 6) {
            if let imgData = pendingUserImage, let nsImage = NSImage(data: imgData) {
                Image(nsImage: nsImage)
                    .resizable().scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text("Image attached")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Button(action: { pendingUserImage = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.3))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var inputPlaceholder: String {
        switch labSession.currentPhase {
        case .referenceInput:   return "Describe what you want to create..."
        case .analysis:         return "Answer AI's questions or ask your own..."
        case .documentDrafting: return "Review and suggest document changes..."
        case .implementation:   return "Request shader implementation..."
        case .tuning:           return "Describe parameter adjustments..."
        case .adversarial:      return "Respond to AI's proposals..."
        }
    }

    private var canSubmit: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && aiSettings.isConfigured
            && !isLoading
    }

    // MARK: - Actions

    private func handleSubmit() {
        guard canSubmit else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        var userMsg = ChatMessage(role: .user, content: text)
        userMsg.userImage = pendingUserImage
        messages.append(userMsg)
        pendingUserImage = nil

        isLoading = true
        Task {
            do {
                let response = try await LabAIFlow.sendMessage(
                    text: text,
                    phase: labSession.currentPhase,
                    references: references,
                    projectDocument: projectDocument,
                    activeShaders: activeShaders,
                    canvasMode: canvasMode,
                    dataFlowConfig: dataFlowConfig,
                    dataFlow2DConfig: dataFlow2DConfig,
                    objects2D: objects2D,
                    sharedVertexCode2D: sharedVertexCode2D,
                    sharedFragmentCode2D: sharedFragmentCode2D,
                    paramValues: paramValues,
                    meshType: meshType,
                    chatHistory: messages,
                    settings: aiSettings,
                    imageData: userMsg.userImage
                )

                await MainActor.run {
                    var assistantMsg = ChatMessage(role: .assistant, content: response.explanation)
                    if !response.actions.isEmpty {
                        assistantMsg.executedActions = response.actions
                        onAgentActions(response.actions)
                    }
                    messages.append(assistantMsg)
                    isLoading = false

                    updateDocumentFromResponse(response)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func updateDocumentFromResponse(_ response: AgentResponse) {
        guard labSession.currentPhase == .analysis || labSession.currentPhase == .documentDrafting else { return }
        if projectDocument.referenceAnalysis.isEmpty && !response.explanation.isEmpty
            && labSession.currentPhase == .analysis {
            projectDocument.referenceAnalysis = response.explanation
        }
    }

    private func attachReference() {
        guard let firstImage = references.first(where: { $0.type == .image }),
              let data = firstImage.mediaData else { return }
        pendingUserImage = data
    }

    private func captureRender() {
        if let capture = MetalRenderer.current?.captureForAI() {
            pendingUserImage = capture
        }
    }
}
