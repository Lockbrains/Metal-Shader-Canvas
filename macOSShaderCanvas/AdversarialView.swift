//
//  AdversarialView.swift
//  macOSShaderCanvas
//
//  Adversarial generation UI for Lab mode. Displays AI-proposed alternatives,
//  allows accept/reject/partial adoption, and tracks proposal history
//  with version branching.
//

import SwiftUI

// MARK: - AdversarialView

struct AdversarialView: View {
    @Binding var proposals: [AdversarialProposal]
    @Binding var paramValues: [String: [Float]]
    @Binding var activeShaders: [ActiveShader]
    @Binding var projectDocument: ProjectDocument
    let aiSettings: AISettings
    let onApplyCode: (String, String) -> Void

    @State private var isGenerating = false
    @State private var selectedProposalID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            adversarialHeader
            Divider().background(Color.white.opacity(0.1))

            if proposals.isEmpty {
                emptyState
            } else {
                proposalList
            }
        }
    }

    // MARK: - Header

    private var adversarialHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text("Adversarial Proposals")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            if isGenerating {
                ProgressView().scaleEffect(0.5)
            } else {
                Button(action: generateProposal) {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10))
                        Text("Generate")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .disabled(!aiSettings.isConfigured || activeShaders.isEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.12))
            Text("No proposals yet")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
            Text("AI will challenge your shader with alternatives")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Proposal List

    private var proposalList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(proposals.reversed()) { proposal in
                    proposalCard(proposal)
                }
            }
            .padding(10)
        }
    }

    private func proposalCard(_ proposal: AdversarialProposal) -> some View {
        let isExpanded = selectedProposalID == proposal.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                outcomeBadge(proposal.outcome)
                Text(proposal.date, style: .relative)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
                Button(action: {
                    withAnimation { selectedProposalID = isExpanded ? nil : proposal.id }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            Text(proposal.description)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(isExpanded ? nil : 3)

            if isExpanded {
                if !proposal.rationale.isEmpty {
                    Text(proposal.rationale)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(6)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(4)
                }

                if let paramChanges = proposal.paramChanges, !paramChanges.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Proposed Parameter Changes:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                        ForEach(Array(paramChanges.sorted(by: { $0.key < $1.key })), id: \.key) { key, vals in
                            HStack(spacing: 4) {
                                Text(key)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.cyan.opacity(0.7))
                                Text("\u{2192}")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.3))
                                Text(vals.map { String(format: "%.2f", $0) }.joined(separator: ", "))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.orange.opacity(0.7))
                            }
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(4)
                }

                if let codeChanges = proposal.codeChanges, !codeChanges.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Proposed Code Changes:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                        ForEach(Array(codeChanges.keys.sorted()), id: \.self) { layerName in
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 8))
                                    .foregroundColor(.purple.opacity(0.7))
                                Text(layerName)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.purple.opacity(0.8))
                                Text("\((codeChanges[layerName] ?? "").count) chars")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                    }
                    .padding(6)
                    .background(Color.purple.opacity(0.06))
                    .cornerRadius(4)
                }

                if proposal.outcome == .pending {
                    actionButtons(proposal)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(outlineColor(proposal.outcome), lineWidth: 0.5)
        )
    }

    private func actionButtons(_ proposal: AdversarialProposal) -> some View {
        HStack(spacing: 8) {
            Button(action: { updateOutcome(proposal, outcome: .accepted) }) {
                Label("Accept", systemImage: "checkmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)

            Button(action: { updateOutcome(proposal, outcome: .partiallyAdopted) }) {
                Label("Partial", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)

            Button(action: { updateOutcome(proposal, outcome: .rejected) }) {
                Label("Reject", systemImage: "xmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Badge Helpers

    private func outcomeBadge(_ outcome: ProposalOutcome) -> some View {
        let (text, color): (String, Color) = switch outcome {
        case .pending: ("Pending", .gray)
        case .accepted: ("Accepted", .green)
        case .rejected: ("Rejected", .red)
        case .partiallyAdopted: ("Partial", .orange)
        }
        return Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .cornerRadius(3)
    }

    private func outlineColor(_ outcome: ProposalOutcome) -> Color {
        switch outcome {
        case .pending: return .white.opacity(0.06)
        case .accepted: return .green.opacity(0.2)
        case .rejected: return .red.opacity(0.15)
        case .partiallyAdopted: return .orange.opacity(0.2)
        }
    }

    // MARK: - Actions

    private func generateProposal() {
        isGenerating = true
        let currentCode = activeShaders.map(\.code).joined(separator: "\n\n")
        let currentParams = paramValues
        let doc = projectDocument
        let captured = aiSettings.captured

        Task {
            do {
                let capture = await Task.detached { await MetalRenderer.current?.captureForAI() }.value
                let proposal = try await LabAIFlow.proposeAlternative(
                    currentCode: currentCode,
                    paramValues: currentParams,
                    projectDocument: doc,
                    captured: captured,
                    renderCapture: capture
                )
                await MainActor.run {
                    proposals.append(proposal)
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                }
            }
        }
    }

    private func updateOutcome(_ proposal: AdversarialProposal, outcome: ProposalOutcome) {
        guard let idx = proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        proposals[idx].outcome = outcome

        if outcome == .accepted || outcome == .partiallyAdopted {
            if let paramChanges = proposal.paramChanges {
                for (key, vals) in paramChanges {
                    paramValues[key] = vals
                }
            }

            if let codeChanges = proposal.codeChanges {
                for (layerName, code) in codeChanges {
                    if let shaderIdx = activeShaders.firstIndex(where: { $0.name == layerName }) {
                        activeShaders[shaderIdx].code = code
                    } else {
                        onApplyCode(layerName, code)
                    }
                }
            }
        }

        let entry = IterationEntry(
            description: proposal.description,
            decision: outcome.rawValue,
            outcome: outcome.rawValue
        )
        projectDocument.iterationLog.append(entry)
    }
}
