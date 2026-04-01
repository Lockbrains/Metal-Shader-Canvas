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
    var chatStore: LabChatStore
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
                    ForEach(chatStore.messages) { msg in
                        labMessageBubble(msg)
                            .id(msg.id)
                    }

                    if isLoading {
                        loadingIndicator
                    }
                }
                .padding(12)
            }
            .onChange(of: chatStore.messages.count) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    if let lastID = chatStore.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
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

                MarkdownTextView(message.content, fontSize: 12, color: .white.opacity(0.85))
                    .equatable()

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
        let t0 = CFAbsoluteTimeGetCurrent()
        print("[LAB-SEND] handleSubmit START")
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        var userMsg = ChatMessage(role: .user, content: text)
        userMsg.userImage = pendingUserImage
        chatStore.messages.append(userMsg)
        print("[LAB-SEND] state mutations done  +\(Int((CFAbsoluteTimeGetCurrent()-t0)*1000))ms")

        let refs = references
        let imageData = pendingUserImage
        pendingUserImage = nil

        isLoading = true
        print("[LAB-SEND] handleSubmit END (Task scheduled)  +\(Int((CFAbsoluteTimeGetCurrent()-t0)*1000))ms")
        Task {
            print("[LAB-SEND] Task body START  +\(Int((CFAbsoluteTimeGetCurrent()-t0)*1000))ms")
            do {
                let refImages = await Task.detached { [refs] in
                    Self.compressReferenceImages(refs)
                }.value

                let response = try await LabAIFlow.sendMessage(
                    text: text,
                    phase: labSession.currentPhase,
                    references: refs,
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
                    chatHistory: chatStore.messages,
                    settings: aiSettings,
                    imageData: imageData,
                    referenceImages: refImages
                )

                await MainActor.run {
                    var assistantMsg = ChatMessage(role: .assistant, content: response.explanation)
                    if !response.actions.isEmpty {
                        assistantMsg.executedActions = response.actions
                        onAgentActions(response.actions)
                    }
                    chatStore.messages.append(assistantMsg)
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
        Task {
            let capture = await Task.detached { MetalRenderer.current?.captureForAI() }.value
            if let data = capture { pendingUserImage = data }
        }
    }

    /// Collects and compresses reference images for the AI API call.
    /// Limited to 4 images to keep request size reasonable.
    /// Static so it can be called from Task.detached without capturing self.
    private static func compressReferenceImages(_ references: [ReferenceItem]) -> [Data] {
        let imageRefs = references.filter { $0.type == .image || $0.type == .gif }
        let maxImages = 4
        var result: [Data] = []
        for ref in imageRefs.prefix(maxImages) {
            guard let raw = ref.mediaData else { continue }
            if let nsImage = NSImage(data: raw),
               let compressed = MetalRenderer.resizeAndCompress(nsImage, maxDimension: 1024, quality: 0.7) {
                result.append(compressed)
            } else {
                result.append(raw)
            }
        }
        return result
    }
}

// MARK: - Markdown Text View

/// Renders Markdown-formatted text with block-level structure and safe inline styling.
///
/// Uses a custom O(n) inline parser for **bold** and `code` instead of
/// `AttributedString(markdown:)` which can hang on pathological inputs
/// (exponential backtracking with many unmatched `*` / `_` characters).
struct MarkdownTextView: View, Equatable {
    let text: String
    let fontSize: CGFloat
    let color: Color

    static func == (lhs: MarkdownTextView, rhs: MarkdownTextView) -> Bool {
        lhs.text == rhs.text && lhs.fontSize == rhs.fontSize
    }

    init(_ text: String, fontSize: CGFloat = 12, color: Color = .white.opacity(0.85)) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
    }

    var body: some View {
        let blocks = Self.parseBlocks(text)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks.indices, id: \.self) { i in
                blockView(blocks[i])
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            Self.inlineText(content, color: color)
                .font(.system(size: headingSize(level), weight: .semibold))
                .padding(.top, level <= 2 ? 4 : 2)

        case .codeBlock(_, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: max(fontSize - 1, 10), design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.35))
            .cornerRadius(6)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items.indices, id: \.self) { j in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                            .foregroundColor(color.opacity(0.5))
                            .font(.system(size: fontSize))
                        Self.inlineText(items[j], color: color)
                            .font(.system(size: fontSize))
                            .lineSpacing(2)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items.indices, id: \.self) { j in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(j + 1).")
                            .foregroundColor(color.opacity(0.5))
                            .font(.system(size: fontSize))
                            .frame(minWidth: 18, alignment: .trailing)
                        Self.inlineText(items[j], color: color)
                            .font(.system(size: fontSize))
                            .lineSpacing(2)
                    }
                }
            }

        case .paragraph(let content):
            Self.inlineText(content, color: color)
                .font(.system(size: fontSize))
                .lineSpacing(3)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize + 6
        case 2: return fontSize + 4
        case 3: return fontSize + 2
        default: return fontSize + 1
        }
    }

    // MARK: - Safe O(n) Inline Parser

    /// Parses **bold** and `code` spans in linear time using simple forward scanning.
    /// Never backtracks — guaranteed to complete in O(n).
    static func inlineText(_ text: String, color: Color) -> Text {
        guard text.contains("**") || text.contains("`") else {
            return Text(text).foregroundColor(color)
        }

        var result = Text("")
        var pos = text.startIndex

        while pos < text.endIndex {
            let rest = text[pos...]

            let nextBold = rest.range(of: "**")?.lowerBound
            let nextCode = rest.firstIndex(of: "`")

            let marker: (idx: String.Index, kind: Character)? = {
                switch (nextBold, nextCode) {
                case let (b?, c?): return b <= c ? (b, "*") : (c, "`")
                case let (b?, nil): return (b, "*")
                case let (nil, c?): return (c, "`")
                case (nil, nil):    return nil
                }
            }()

            guard let (mIdx, mKind) = marker else {
                result = result + Text(text[pos...]).foregroundColor(color)
                break
            }

            if mIdx > pos {
                result = result + Text(text[pos..<mIdx]).foregroundColor(color)
            }

            if mKind == "*" {
                let contentStart = text.index(mIdx, offsetBy: 2)
                if contentStart < text.endIndex,
                   let close = text[contentStart...].range(of: "**") {
                    result = result + Text(text[contentStart..<close.lowerBound])
                        .bold().foregroundColor(color)
                    pos = close.upperBound
                } else {
                    result = result + Text("**").foregroundColor(color)
                    pos = min(contentStart, text.endIndex)
                }
            } else {
                let contentStart = text.index(after: mIdx)
                if contentStart < text.endIndex,
                   let close = text[contentStart...].firstIndex(of: "`") {
                    result = result + Text(text[contentStart..<close])
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                    pos = text.index(after: close)
                } else {
                    result = result + Text("`").foregroundColor(color)
                    pos = min(contentStart, text.endIndex)
                }
            }
        }

        return result
    }

    // MARK: - Block Parser

    enum MDBlock: Equatable {
        case heading(Int, String)
        case codeBlock(String?, String)
        case unorderedList([String])
        case orderedList([String])
        case paragraph(String)
    }

    static func parseBlocks(_ text: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // Code block
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1; break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(lang.isEmpty ? nil : lang, codeLines.joined(separator: "\n")))
                continue
            }

            // Heading (# to ######)
            if let hashEnd = trimmed.firstIndex(where: { $0 != "#" }) {
                let hashes = trimmed[trimmed.startIndex..<hashEnd]
                let level = hashes.count
                if level >= 1 && level <= 6
                    && hashEnd < trimmed.endIndex
                    && trimmed[hashEnd] == " " {
                    let content = String(trimmed[trimmed.index(after: hashEnd)...])
                    blocks.append(.heading(level, content))
                    i += 1; continue
                }
            }

            // Unordered list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("- ") { items.append(String(l.dropFirst(2))); i += 1 }
                    else if l.hasPrefix("* ") { items.append(String(l.dropFirst(2))); i += 1 }
                    else if l.hasPrefix("• ") { items.append(String(l.dropFirst(2))); i += 1 }
                    else { break }
                }
                blocks.append(.unorderedList(items))
                continue
            }

            // Ordered list
            if trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if let range = l.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                        items.append(String(l[range.upperBound...]))
                        i += 1
                    } else { break }
                }
                blocks.append(.orderedList(items))
                continue
            }

            // Paragraph: collect consecutive non-special lines
            var paragraphLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                let lt = l.trimmingCharacters(in: .whitespaces)
                if lt.isEmpty || lt.hasPrefix("```")
                    || (lt.firstIndex(where: { $0 != "#" }).map { idx in
                        let cnt = lt.distance(from: lt.startIndex, to: idx)
                        return cnt >= 1 && cnt <= 6 && idx < lt.endIndex && lt[idx] == " "
                    } ?? false)
                    || lt.hasPrefix("- ") || lt.hasPrefix("* ") || lt.hasPrefix("• ")
                    || lt.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil {
                    break
                }
                paragraphLines.append(l)
                i += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            }
        }

        return blocks
    }
}
