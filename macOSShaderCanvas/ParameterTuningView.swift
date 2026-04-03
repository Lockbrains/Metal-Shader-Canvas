//
//  ParameterTuningView.swift
//  macOSShaderCanvas
//
//  Enhanced parameter tuning panel for Lab mode implementing "engineering haptics"
//  from the GDC 2026 talk. Provides:
//  - Real-time parameter sliders with sensitivity indicators
//  - Parameter snapshot system (save/restore/compare)
//  - Timeline browser for parameter evolution
//  - A/B comparison between snapshots
//  - AI feedback overlay showing suggestions
//

import SwiftUI

// MARK: - ParameterTuningView

struct ParameterTuningView: View {
    @Binding var paramValues: [String: [Float]]
    @Binding var snapshots: [ParameterSnapshot]
    let activeShaders: [ActiveShader]
    let canvasMode: CanvasMode
    let objects2D: [Object2D]
    let sharedFragmentCode2D: String
    let aiSettings: AISettings
    @Binding var projectDocument: ProjectDocument

    @State private var viewMode: TuningViewMode = .sliders
    @State private var compareA: UUID? = nil
    @State private var compareB: UUID? = nil
    @State private var snapshotLabel = ""
    @State private var aiFeedback: String?
    @State private var isRequestingFeedback = false
    @State private var feedbackDebounceTask: Task<Void, Never>?

    enum TuningViewMode: String, CaseIterable {
        case sliders = "Sliders"
        case timeline = "Timeline"
        case compare = "A/B Compare"
    }

    private struct ParamGroup: Identifiable {
        var id: String { scopeKey.isEmpty ? "global-\(label)" : scopeKey }
        let label: String
        let params: [ShaderParam]
        /// Object/shader UUID string used to scope parameter keys.
        /// Empty string means global (unscoped).
        let scopeKey: String
    }

    private var groupedParams: [ParamGroup] {
        var groups: [ParamGroup] = []
        var allFoundNames: Set<String> = []

        if canvasMode.is2D {
            for obj in objects2D {
                var objParams: [ShaderParam] = []
                if let vs = obj.customVertexCode {
                    for p in ShaderSnippets.parseParams(from: vs) {
                        objParams.append(p)
                    }
                }
                if let fs = obj.customFragmentCode {
                    for p in ShaderSnippets.parseParams(from: fs) {
                        if !objParams.contains(where: { $0.name == p.name }) {
                            objParams.append(p)
                        }
                    }
                }
                if !objParams.isEmpty {
                    allFoundNames.formUnion(objParams.map(\.name))
                    groups.append(ParamGroup(label: obj.name, params: objParams, scopeKey: obj.id.uuidString))
                }
            }
            var sharedParams: [ShaderParam] = []
            for p in ShaderSnippets.parseParams(from: sharedFragmentCode2D) {
                sharedParams.append(p)
            }
            if !sharedParams.isEmpty {
                allFoundNames.formUnion(sharedParams.map(\.name))
                groups.append(ParamGroup(label: "Shared", params: sharedParams, scopeKey: ""))
            }
        }

        for shader in activeShaders {
            var shaderParams: [ShaderParam] = []
            for p in ShaderSnippets.parseParams(from: shader.code) {
                shaderParams.append(p)
            }
            if !shaderParams.isEmpty {
                allFoundNames.formUnion(shaderParams.map(\.name))
                groups.append(ParamGroup(label: shader.name, params: shaderParams, scopeKey: shader.id.uuidString))
            }
        }

        let designParams = projectDocument.parameterDesign.filter { !allFoundNames.contains($0.name) }
        if !designParams.isEmpty {
            let converted = designParams.map { spec in
                ShaderParam(
                    name: spec.name,
                    type: spec.type,
                    defaultValue: spec.suggestedDefault,
                    minValue: spec.suggestedMin,
                    maxValue: spec.suggestedMax
                )
            }
            groups.append(ParamGroup(label: "Registered", params: converted, scopeKey: ""))
        }

        return groups
    }

    private var allParams: [ShaderParam] {
        groupedParams.flatMap(\.params)
    }

    /// Returns the scoped parameter key for a given group and param.
    private func paramKey(scope: String, name: String) -> String {
        scope.isEmpty ? name : "\(scope)/\(name)"
    }

    /// Reads a parameter value using scoped key with fallback to global key.
    private func readParam(scope: String, param: ShaderParam) -> [Float] {
        if !scope.isEmpty, let scoped = paramValues["\(scope)/\(param.name)"] {
            return scoped
        }
        return paramValues[param.name] ?? param.defaultValue
    }

    var body: some View {
        VStack(spacing: 0) {
            tuningToolbar
            Divider().background(Color.white.opacity(0.1))

            switch viewMode {
            case .sliders:
                slidersView
            case .timeline:
                timelineView
            case .compare:
                compareView
            }
        }
    }

    // MARK: - Toolbar

    private var tuningToolbar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $viewMode) {
                ForEach(TuningViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Spacer()

            Button(action: takeSnapshot) {
                HStack(spacing: 3) {
                    Image(systemName: "camera")
                        .font(.system(size: 10))
                    Text("Snapshot")
                        .font(.system(size: 10))
                }
                .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Save current parameter state")

            Text("\(snapshots.count)")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.06))
                .cornerRadius(3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Sliders View

    private var slidersView: some View {
        ScrollView {
            if allParams.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No parameters declared")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Add // @param directives to your shader code")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.2))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    aiFeedbackBanner

                    ForEach(groupedParams) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "cube")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.3))
                                Text(group.label)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.4))
                                    .textCase(.uppercase)
                                Spacer()
                                Text("\(group.params.count)")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.2))
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, group.id == groupedParams.first?.id ? 0 : 4)

                            ForEach(group.params, id: \.name) { param in
                                parameterSlider(param, scopeKey: group.scopeKey)
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private var aiFeedbackBanner: some View {
        if let feedback = aiFeedback, !feedback.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9))
                        .foregroundColor(.purple)
                    Text("AI Feedback")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.purple.opacity(0.8))
                    Spacer()
                    Button(action: { aiFeedback = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                Text(feedback)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                    .lineSpacing(2)
            }
            .padding(8)
            .background(Color.purple.opacity(0.1))
            .cornerRadius(6)
        }

        HStack {
            Spacer()
            Button(action: requestAIFeedback) {
                HStack(spacing: 3) {
                    if isRequestingFeedback {
                        ProgressView().scaleEffect(0.5)
                    } else {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9))
                    }
                    Text("Get AI Feedback")
                        .font(.system(size: 9))
                }
                .foregroundColor(.purple.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(isRequestingFeedback || !aiSettings.isConfigured)
        }
    }

    private func parameterSlider(_ param: ShaderParam, scopeKey: String = "") -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(param.name.hasPrefix("_") ? String(param.name.dropFirst()) : param.name)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.8))
                Text("(\(param.type.rawValue))")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
                Text(currentValueText(param, scopeKey: scopeKey))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            if param.type == .color {
                colorControl(param, scopeKey: scopeKey)
            } else {
                ForEach(0..<param.type.componentCount, id: \.self) { comp in
                    sliderRow(param: param, component: comp, scopeKey: scopeKey)
                }
            }

            sensitivityIndicator(param, scopeKey: scopeKey)
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }

    private func sliderRow(param: ShaderParam, component: Int, scopeKey: String = "") -> some View {
        let minVal = param.minValue ?? 0.0
        let maxVal = param.maxValue ?? (param.type == .color ? 1.0 : 10.0)
        let key = paramKey(scope: scopeKey, name: param.name)
        let binding = Binding<Float>(
            get: {
                let vals = readParam(scope: scopeKey, param: param)
                return component < vals.count ? vals[component] : param.defaultValue.first ?? 0
            },
            set: { newVal in
                var vals = readParam(scope: scopeKey, param: param)
                while vals.count <= component { vals.append(0) }
                vals[component] = newVal
                paramValues[key] = vals
            }
        )

        return HStack(spacing: 6) {
            if param.type.componentCount > 1 {
                Text(["x", "y", "z", "w"][min(component, 3)])
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 10)
            }
            Slider(value: binding, in: minVal...maxVal)
                .tint(.cyan)
            Text(String(format: "%.2f", binding.wrappedValue))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func colorControl(_ param: ShaderParam, scopeKey: String = "") -> some View {
        let vals = readParam(scope: scopeKey, param: param)
        let r = vals.count > 0 ? Double(vals[0]) : 1.0
        let g = vals.count > 1 ? Double(vals[1]) : 1.0
        let b = vals.count > 2 ? Double(vals[2]) : 1.0

        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: r, green: g, blue: b))
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2)))

            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { comp in
                    sliderRow(param: param, component: comp, scopeKey: scopeKey)
                }
            }
        }
    }

    private func sensitivityIndicator(_ param: ShaderParam, scopeKey: String = "") -> some View {
        HStack(spacing: 3) {
            Image(systemName: "waveform.path")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.2))
            GeometryReader { geo in
                let vals = readParam(scope: scopeKey, param: param)
                let normalizedPosition = normalizedParameterPosition(param: param, values: vals)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.cyan.opacity(0.2))
                    .frame(width: geo.size.width * CGFloat(normalizedPosition))
            }
            .frame(height: 3)
        }
    }

    private func normalizedParameterPosition(param: ShaderParam, values: [Float]) -> Float {
        guard let minVal = param.minValue, let maxVal = param.maxValue, maxVal > minVal else { return 0.5 }
        let val = values.first ?? param.defaultValue.first ?? 0
        return max(0, min(1, (val - minVal) / (maxVal - minVal)))
    }

    private func currentValueText(_ param: ShaderParam, scopeKey: String = "") -> String {
        let vals = readParam(scope: scopeKey, param: param)
        return vals.map { String(format: "%.2f", $0) }.joined(separator: ", ")
    }

    // MARK: - Timeline View

    private var timelineView: some View {
        ScrollView {
            if snapshots.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No snapshots yet")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Click 'Snapshot' to save parameter states")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.2))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 6) {
                    ForEach(snapshots.reversed()) { snapshot in
                        snapshotRow(snapshot)
                    }
                }
                .padding(10)
            }
        }
    }

    private func snapshotRow(_ snapshot: ParameterSnapshot) -> some View {
        HStack(spacing: 8) {
            if let captureData = snapshot.renderCapture, let nsImage = NSImage(data: captureData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 48, height: 36)
                    .overlay(
                        Image(systemName: "camera")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.2))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.label ?? "Snapshot")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text(snapshot.date, style: .relative)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                if let comment = snapshot.aiComment {
                    Text(comment)
                        .font(.system(size: 9))
                        .foregroundColor(.purple.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: { restoreSnapshot(snapshot) }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Restore this snapshot")
        }
        .padding(6)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }

    // MARK: - Compare View

    private var compareView: some View {
        VStack(spacing: 8) {
            if snapshots.count < 2 {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.15))
                    Text("Need at least 2 snapshots to compare")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 4) {
                    compareSelector(label: "A", selection: $compareA)
                    compareSelector(label: "B", selection: $compareB)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                if let a = compareA, let b = compareB,
                   let snapA = snapshots.first(where: { $0.id == a }),
                   let snapB = snapshots.first(where: { $0.id == b }) {
                    paramDiffView(snapA: snapA, snapB: snapB)
                }

                Spacer()
            }
        }
    }

    private func compareSelector(label: String, selection: Binding<UUID?>) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
            Picker("", selection: selection) {
                Text("Select...").tag(nil as UUID?)
                ForEach(snapshots) { snap in
                    Text(snap.label ?? snap.date.formatted(.dateTime.hour().minute().second()))
                        .tag(snap.id as UUID?)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func paramDiffView(snapA: ParameterSnapshot, snapB: ParameterSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                let allKeys = Set(snapA.paramValues.keys).union(Set(snapB.paramValues.keys))
                ForEach(Array(allKeys.sorted()), id: \.self) { key in
                    let valsA = snapA.paramValues[key] ?? []
                    let valsB = snapB.paramValues[key] ?? []
                    let changed = valsA != valsB

                    HStack(spacing: 6) {
                        Text(key)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(changed ? .orange : .white.opacity(0.5))
                            .frame(width: 70, alignment: .leading)
                        Text(valsA.map { String(format: "%.2f", $0) }.joined(separator: ","))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(changed ? .orange.opacity(0.6) : .white.opacity(0.2))
                        Text(valsB.map { String(format: "%.2f", $0) }.joined(separator: ","))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(changed ? Color.orange.opacity(0.05) : Color.clear)
                    .cornerRadius(3)
                }
            }
            .padding(10)
        }
    }

    // MARK: - Actions

    private func takeSnapshot() {
        let label = snapshotLabel.isEmpty ? "Snapshot \(snapshots.count + 1)" : snapshotLabel
        let vals = paramValues
        let hash = activeShaders.map(\.code).joined().hashValue.description
        snapshotLabel = ""
        let captured = aiSettings.captured
        let isConfigured = aiSettings.isConfigured
        let shaderCode = activeShaders.map(\.code).joined(separator: "\n\n")
        let doc = projectDocument

        Task {
            let capture = await Task.detached { await MetalRenderer.current?.captureForAI() }.value
            var snapshot = ParameterSnapshot(
                paramValues: vals,
                renderCapture: capture,
                label: label,
                codeHash: hash
            )

            if isConfigured {
                let comment = await Self.evaluateParamsForSnapshot(
                    params: vals, shaderCode: shaderCode, document: doc,
                    captured: captured, renderCapture: capture
                )
                snapshot.aiComment = comment
            }

            await MainActor.run {
                snapshots.append(snapshot)
            }
        }
    }

    private func restoreSnapshot(_ snapshot: ParameterSnapshot) {
        paramValues = snapshot.paramValues
    }

    private func requestAIFeedback() {
        isRequestingFeedback = true
        let vals = paramValues
        let shaderCode = activeShaders.map(\.code).joined(separator: "\n\n")
        let doc = projectDocument
        let captured = aiSettings.captured

        Task {
            let capture = await Task.detached { await MetalRenderer.current?.captureForAI() }.value
            let feedback = await Self.evaluateParamsForSnapshot(
                params: vals, shaderCode: shaderCode, document: doc,
                captured: captured, renderCapture: capture
            )
            await MainActor.run {
                aiFeedback = feedback
                isRequestingFeedback = false
            }
        }
    }

    /// Requests a brief AI evaluation of the current parameter state.
    private nonisolated static func evaluateParamsForSnapshot(
        params: [String: [Float]], shaderCode: String,
        document: ProjectDocument, captured: CapturedAISettings,
        renderCapture: Data?
    ) async -> String? {
        let paramStr = params.sorted(by: { $0.key < $1.key })
            .map { "\($0.key) = \($0.value.map { String(format: "%.3f", $0) }.joined(separator: ", "))" }
            .joined(separator: "\n")

        let prompt = """
        Briefly evaluate these shader parameters (2-3 sentences max). \
        Note any visual issues, suggest improvements, flag saturation points.

        Project context: \(document.markdown.isEmpty ? document.visualGoal : String(document.markdown.prefix(500)))

        Shader code (\(shaderCode.count) chars):
        \(shaderCode.prefix(2000))

        Current parameters:
        \(paramStr)
        """

        let msg = ChatMessage(role: .user, content: prompt)
        do {
            let response: String = try await AIService.onBackground {
                switch captured.provider {
                case .openai:
                    return try await AIService.shared.callOpenAI(
                        system: "You are a shader parameter tuning assistant. Be concise and specific.",
                        messages: [msg], captured: captured, imageData: renderCapture)
                case .anthropic:
                    return try await AIService.shared.callAnthropic(
                        system: "You are a shader parameter tuning assistant. Be concise and specific.",
                        messages: [msg], captured: captured, imageData: renderCapture)
                case .gemini:
                    return try await AIService.shared.callGemini(
                        system: "You are a shader parameter tuning assistant. Be concise and specific.",
                        messages: [msg], captured: captured, imageData: renderCapture)
                }
            }
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[PARAM-AI] Evaluation failed: \(error)")
            return nil
        }
    }
}
