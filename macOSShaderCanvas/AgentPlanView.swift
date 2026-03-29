//
//  AgentPlanView.swift
//  macOSShaderCanvas
//
//  Visual representation of an AgentPlan task tree.
//  Used both as an embedded component inside chat message bubbles
//  and as a standalone panel for monitoring plan execution.
//

import SwiftUI

// MARK: - Plan Tree View

/// Renders a complete AgentPlan as an interactive tree with progress tracking.
struct AgentPlanView: View {
    let plan: AgentPlan
    @State private var expandedNodes: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: plan.status == .failed ? "exclamationmark.triangle.fill" : "list.bullet.indent")
                    .foregroundColor(plan.status == .failed ? .red : .cyan)
                    .font(.system(size: 12))
                Text(plan.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                if failedCount > 0 {
                    Text("\(failedCount) failed")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.trailing, 4)
                }
                Text("\(plan.completedSteps)/\(plan.totalSteps)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 4)

            // Node tree
            ForEach(plan.nodes) { node in
                PlanNodeRow(node: node, depth: 0, expandedNodes: $expandedNodes)
            }
        }
        .padding(10)
        .background(Color.cyan.opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.cyan.opacity(0.15), lineWidth: 1)
        )
    }

    private var failedCount: Int {
        plan.nodes.reduce(0) { $0 + ($1.status == .failed ? 1 : 0) + $1.children.filter { $0.status == .failed }.count }
    }

    private var progress: CGFloat {
        guard plan.totalSteps > 0 else { return 0 }
        return CGFloat(plan.completedSteps) / CGFloat(plan.totalSteps)
    }

    private var progressColor: Color {
        switch plan.status {
        case .completed: return .green
        case .failed:    return .red
        case .running:   return .cyan
        default:         return .white.opacity(0.3)
        }
    }
}

// MARK: - Plan Node Row

/// A single node in the plan tree, with expand/collapse for children.
struct PlanNodeRow: View {
    let node: PlanNode
    let depth: Int
    @Binding var expandedNodes: Set<UUID>

    private var isExpanded: Bool { expandedNodes.contains(node.id) }
    private var hasChildren: Bool { !node.children.isEmpty }
    private var hasExpandableContent: Bool {
        hasChildren
        || (node.thinking != nil && !(node.thinking?.isEmpty ?? true))
        || node.error != nil
        || !node.description.isEmpty
        || (node.actions != nil && !(node.actions?.isEmpty ?? true))
    }
    /// Failed and running nodes auto-expand so the user sees details immediately.
    private var shouldAutoExpand: Bool {
        node.status == .failed || node.status == .running
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if hasExpandableContent {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 10)
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { toggleExpand() } }
                } else {
                    Spacer().frame(width: 10)
                }

                statusIcon.font(.system(size: 10))

                Text(node.title)
                    .font(.system(size: 11, weight: node.status == .running ? .semibold : .regular))
                    .foregroundColor(titleColor)
                    .lineLimit(1)

                Spacer()

                if let actions = node.actions, !actions.isEmpty {
                    Text("\(actions.count) action\(actions.count == 1 ? "" : "s")")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.leading, CGFloat(depth) * 16)

            if isExpanded || shouldAutoExpand {
                let indent = CGFloat(depth) * 16 + 26

                // Step description
                if !node.description.isEmpty {
                    Text(node.description)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.leading, indent)
                }

                // Thinking section
                if let thinking = node.thinking, !thinking.isEmpty {
                    ThinkingSection(text: thinking)
                        .padding(.leading, indent)
                }

                // Executed actions summary
                if let actions = node.actions, !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(actions, id: \.name) { action in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.green.opacity(0.7))
                                Text("\(action.type.rawValue): \(action.name)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.leading, indent)
                }

                // Error detail — prominent, always visible for failed nodes
                if let error = node.error {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                            Text("Failed")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.red)
                        }
                        Text(error)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                            .textSelection(.enabled)
                            .lineSpacing(2)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.2), lineWidth: 1))
                    .padding(.leading, indent)
                }

                ForEach(node.children) { child in
                    PlanNodeRow(node: child, depth: depth + 1, expandedNodes: $expandedNodes)
                }
            }
        }
        .onAppear {
            if shouldAutoExpand { expandedNodes.insert(node.id) }
        }
        .onChange(of: node.status) { _, newStatus in
            if newStatus == .failed || newStatus == .running {
                expandedNodes.insert(node.id)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch node.status {
        case .pending:
            Image(systemName: "circle").foregroundColor(.white.opacity(0.3))
        case .running:
            ProgressView().scaleEffect(0.4)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case .skipped:
            Image(systemName: "minus.circle").foregroundColor(.white.opacity(0.3))
        }
    }

    private var titleColor: Color {
        switch node.status {
        case .running:   return .white
        case .completed: return .white.opacity(0.6)
        case .failed:    return .red.opacity(0.8)
        case .skipped:   return .white.opacity(0.3)
        default:         return .white.opacity(0.7)
        }
    }

    private func toggleExpand() {
        if isExpanded { expandedNodes.remove(node.id) }
        else { expandedNodes.insert(node.id) }
    }
}

// MARK: - Thinking Section

/// Collapsible display of AI reasoning in small monospace text.
/// Mimics the thinking display style of Cursor/Claude Code.
struct ThinkingSection: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                    Text("Thinking")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.35))
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - Streaming Thinking View

/// Real-time display of AI output as tokens arrive via SSE.
/// Extracts readable text from the JSON response and shows it in a scrollable view.
struct StreamingThinkingView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.5)
                Text("Generating...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.cyan.opacity(0.7))
                Spacer()
                Text("\(text.count) chars")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            if !text.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(readableContent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("bottom")
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: text) {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.04))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.15), lineWidth: 1))
            }
        }
    }

    /// Extracts human-readable content from the streaming JSON output.
    /// The AI returns `{ "explanation": "...", "actions": [...] }`, so we
    /// try to pull out the explanation text. Falls back to showing everything.
    private var readableContent: String {
        // Try to extract the "explanation" value as it streams in
        if let range = text.range(of: #""explanation"\s*:\s*""#, options: .regularExpression) {
            let afterKey = text[range.upperBound...]
            // Find the end of the string value (unescaped quote)
            var result = ""
            var escaped = false
            for ch in afterKey {
                if escaped { result.append(ch); escaped = false; continue }
                if ch == "\\" { escaped = true; continue }
                if ch == "\"" { break }
                result.append(ch)
            }
            if !result.isEmpty { return result }
        }
        // Fallback: strip JSON noise for readability
        return text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
    }
}

// MARK: - Render Snapshot Thumbnail

/// Small clickable thumbnail of a render snapshot attached to a chat message.
struct SnapshotThumbnail: View {
    let imageData: Data
    @State private var showFullSize = false

    var body: some View {
        if let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 120, maxHeight: 80)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 1))
                .onTapGesture { showFullSize = true }
                .popover(isPresented: $showFullSize) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 512, maxHeight: 512)
                        .padding(8)
                }
        }
    }
}
