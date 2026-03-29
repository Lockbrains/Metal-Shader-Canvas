//
//  ProjectDocumentView.swift
//  macOSShaderCanvas
//
//  Renders and allows editing of the co-authored Project Document in Lab mode.
//  Each section (visual goal, technical approach, parameter design, iteration log)
//  is independently editable by both human and AI.
//

import SwiftUI

// MARK: - ProjectDocumentView

struct ProjectDocumentView: View {
    @Binding var document: ProjectDocument
    @State private var editingSection: DocumentSection? = nil

    enum DocumentSection: String, CaseIterable, Identifiable {
        case title = "Title"
        case visualGoal = "Visual Goal"
        case referenceAnalysis = "Reference Analysis"
        case technicalApproach = "Technical Approach"
        case parameterDesign = "Parameter Design"
        case constraints = "Constraints"
        case iterationLog = "Iteration Log"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .title:             return "textformat"
            case .visualGoal:        return "eye"
            case .referenceAnalysis: return "sparkle.magnifyingglass"
            case .technicalApproach: return "wrench.and.screwdriver"
            case .parameterDesign:   return "slider.horizontal.3"
            case .constraints:       return "exclamationmark.triangle"
            case .iterationLog:      return "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                documentHeader

                sectionView(.visualGoal, text: $document.visualGoal,
                            placeholder: "Describe the visual effect you want to achieve...")

                sectionView(.referenceAnalysis, text: $document.referenceAnalysis,
                            placeholder: "AI analysis of reference materials will appear here...")

                sectionView(.technicalApproach, text: $document.technicalApproach,
                            placeholder: "Technical approach and shader architecture...")

                parameterDesignSection

                constraintsSection

                iterationLogSection
            }
            .padding(10)
        }
    }

    // MARK: - Header

    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                Text("Project Document")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }

            TextField("Project Title", text: $document.title)
                .font(.system(size: 14, weight: .bold))
                .textFieldStyle(.plain)
                .foregroundColor(.white)
        }
    }

    // MARK: - Generic Section

    private func sectionView(_ section: DocumentSection, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(section)

            if editingSection == section {
                TextEditor(text: text)
                    .font(.system(size: 11))
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(4)
                    .frame(minHeight: 60, maxHeight: 150)
                    .overlay(alignment: .topTrailing) {
                        Button(action: { editingSection = nil }) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
            } else {
                Group {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.2))
                            .italic()
                    } else {
                        Text(text.wrappedValue)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(Color.white.opacity(0.02))
                .cornerRadius(4)
                .onTapGesture { editingSection = section }
            }
        }
    }

    private func sectionHeader(_ section: DocumentSection) -> some View {
        HStack(spacing: 4) {
            Image(systemName: section.icon)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
            Text(section.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Button(action: { editingSection = (editingSection == section) ? nil : section }) {
                Image(systemName: "pencil")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Parameter Design Section

    private var parameterDesignSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(.parameterDesign)

            if document.parameterDesign.isEmpty {
                Text("Parameters will be defined during the planning phase...")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.2))
                    .italic()
                    .padding(6)
            } else {
                ForEach(document.parameterDesign) { param in
                    HStack(spacing: 6) {
                        Text(param.name)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.8))
                        Text("(\(param.type.rawValue))")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                        Text(param.purpose)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(3)
                }
            }
        }
    }

    // MARK: - Constraints Section

    private var constraintsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(.constraints)

            if document.constraints.isEmpty {
                Text("No constraints defined")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.2))
                    .italic()
                    .padding(6)
            } else {
                ForEach(document.constraints.indices, id: \.self) { idx in
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 8))
                            .foregroundColor(.orange.opacity(0.6))
                        Text(document.constraints[idx])
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Iteration Log Section

    private var iterationLogSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(.iterationLog)

            if document.iterationLog.isEmpty {
                Text("Iterations will be logged as you collaborate...")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.2))
                    .italic()
                    .padding(6)
            } else {
                ForEach(document.iterationLog) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.date, style: .relative)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                            Spacer()
                            outcomeTag(entry.outcome)
                        }
                        Text(entry.description)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                        if !entry.decision.isEmpty {
                            Text("Decision: \(entry.decision)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(4)
                }
            }
        }
    }

    private func outcomeTag(_ outcome: String) -> some View {
        let color: Color = switch outcome {
        case "accepted": .green
        case "rejected": .red
        case "partial": .orange
        default: .gray
        }
        return Text(outcome.capitalized)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .cornerRadius(3)
    }
}
