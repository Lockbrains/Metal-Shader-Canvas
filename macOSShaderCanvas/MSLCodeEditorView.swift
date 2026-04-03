//
//  MSLCodeEditorView.swift
//  macOSShaderCanvas
//
//  Read-only MSL code viewer for Lab mode with:
//  - Shader selector with DataFlow / Vertex / Fragment / Fullscreen targets
//  - MSL syntax highlighting
//  - Clickable variables everywhere (declarations + references)
//  - Floating Debug Preview overlay (4:3, bottom-right corner)
//  - Line number gutter with click-to-copy-reference
//  - Change visualization (diff highlighting)
//

import SwiftUI
import simd

// MARK: - Shader Selection Target

enum MSLShaderTarget: Hashable, Identifiable {
    case dataFlow
    case object2DVertex(UUID, String)
    case object2DFragment(UUID, String)
    case fullscreen(UUID, String)
    case mesh3DVertex
    case mesh3DFragment

    var id: String {
        switch self {
        case .dataFlow:                    return "df"
        case .object2DVertex(let id, _):   return "o2dv-\(id)"
        case .object2DFragment(let id, _): return "o2df-\(id)"
        case .fullscreen(let id, _):       return "fs-\(id)"
        case .mesh3DVertex:                return "m3dv"
        case .mesh3DFragment:              return "m3df"
        }
    }

    var displayName: String {
        switch self {
        case .dataFlow:                    return "DataFlow"
        case .object2DVertex(_, let n):    return "\(n) — Vertex"
        case .object2DFragment(_, let n):  return "\(n) — Fragment"
        case .fullscreen(_, let n):        return "\(n) (Fullscreen)"
        case .mesh3DVertex:                return "Mesh Vertex"
        case .mesh3DFragment:              return "Mesh Fragment"
        }
    }

    var icon: String {
        switch self {
        case .dataFlow:                             return "rectangle.3.group"
        case .object2DVertex, .mesh3DVertex:        return "arrow.up.and.down.text.horizontal"
        case .object2DFragment, .mesh3DFragment:    return "paintpalette"
        case .fullscreen:                           return "rectangle.inset.filled"
        }
    }

    var isDataFlow: Bool {
        if case .dataFlow = self { return true }
        return false
    }
}

// MARK: - MSLCodeEditorView

struct MSLCodeEditorView: View {
    let canvasMode: CanvasMode
    let objects2D: [Object2D]
    let activeShaders: [ActiveShader]
    let sharedVertexCode2D: String
    let sharedFragmentCode2D: String
    let dataFlowConfig: DataFlowConfig
    let dataFlow2DConfig: DataFlow2DConfig
    let meshType: MeshType
    let paramValues: [String: [Float]]
    let backgroundImage: NSImage?
    let rotationAngle: Float
    let canvasZoom: Float
    let canvasPan: simd_float2
    let shape2DType: Shape2DType

    @State private var selectedTarget: MSLShaderTarget?
    @State private var selectedVariable: MSLVariable?
    @State private var debugFragmentOverrides: [UUID: String] = [:]
    @State private var previousSources: [String: String] = [:]

    @State private var debugOffset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var debugSize: CGSize = CGSize(width: 280, height: 210)
    @State private var debugChannel: Int = -1

    private var targets: [MSLShaderTarget] {
        var t: [MSLShaderTarget] = [.dataFlow]
        if canvasMode.is2D {
            for obj in objects2D {
                t.append(.object2DVertex(obj.id, obj.name))
                t.append(.object2DFragment(obj.id, obj.name))
            }
        } else {
            t.append(.mesh3DVertex)
            t.append(.mesh3DFragment)
        }
        for shader in activeShaders where shader.category == .fullscreen {
            t.append(.fullscreen(shader.id, shader.name))
        }
        return t
    }

    /// The display source — function body only (or struct defs for DataFlow).
    private var displaySource: String {
        guard let target = selectedTarget else { return "// Select a shader to view" }
        switch target {
        case .dataFlow:
            return dataFlowContent
        case .object2DVertex(let id, _):
            guard let obj = objects2D.first(where: { $0.id == id }) else { return "" }
            let composed = MSLSourceComposer.decompose2DVertex(
                object: obj, sharedVS: sharedVertexCode2D, config: dataFlow2DConfig)
            return composed.userFunction
        case .object2DFragment(let id, _):
            guard let obj = objects2D.first(where: { $0.id == id }) else { return "" }
            let composed = MSLSourceComposer.decompose2DFragment(
                object: obj, sharedFS: sharedFragmentCode2D, config: dataFlow2DConfig)
            return composed.userFunction
        case .fullscreen(let id, _):
            guard let shader = activeShaders.first(where: { $0.id == id }) else { return "" }
            return shader.code
        case .mesh3DVertex:
            let composed = MSLSourceComposer.decompose3DVertex(
                shaders: activeShaders, config: dataFlowConfig)
            return composed.userFunction
        case .mesh3DFragment:
            let composed = MSLSourceComposer.decompose3DFragment(
                shaders: activeShaders, config: dataFlowConfig)
            return composed.userFunction
        }
    }

    private var dataFlowContent: String {
        var content = ""
        if canvasMode.is2D {
            content += MSLSourceComposer.structDefinitions2D(config: dataFlow2DConfig)
        } else {
            content += MSLSourceComposer.structDefinitions3D(config: dataFlowConfig)
        }
        let allCodes: [String]
        if canvasMode.is2D {
            allCodes = objects2D.flatMap {
                [$0.customVertexCode ?? "", $0.customFragmentCode ?? ""]
            }
        } else {
            allCodes = activeShaders.map(\.code)
        }
        let paramDefs = MSLSourceComposer.paramDefinesFor(codes: allCodes)
        if !paramDefs.isEmpty {
            content += "\n" + paramDefs
        }
        return content
    }

    /// Full compiled source for debug shader generation.
    private var fullCompiledSource: String {
        guard let target = selectedTarget else { return "" }
        switch target {
        case .dataFlow:
            return ""
        case .object2DVertex(let id, _):
            guard let obj = objects2D.first(where: { $0.id == id }) else { return "" }
            return MSLSourceComposer.decompose2DVertex(
                object: obj, sharedVS: sharedVertexCode2D, config: dataFlow2DConfig).fullSource
        case .object2DFragment(let id, _):
            guard let obj = objects2D.first(where: { $0.id == id }) else { return "" }
            return MSLSourceComposer.decompose2DFragment(
                object: obj, sharedFS: sharedFragmentCode2D, config: dataFlow2DConfig).fullSource
        case .fullscreen(let id, _):
            guard let shader = activeShaders.first(where: { $0.id == id }) else { return "" }
            return shader.code
        case .mesh3DVertex:
            return MSLSourceComposer.decompose3DVertex(
                shaders: activeShaders, config: dataFlowConfig).fullSource
        case .mesh3DFragment:
            return MSLSourceComposer.decompose3DFragment(
                shaders: activeShaders, config: dataFlowConfig).fullSource
        }
    }

    private var parsedVariables: [MSLVariable] {
        guard let target = selectedTarget, !target.isDataFlow else { return [] }
        return MSLVariableParser.parse(source: displaySource)
    }

    /// Lines that differ from the previous version (for change highlighting).
    private var changedLines: Set<Int> {
        guard let target = selectedTarget,
              let prev = previousSources[target.id] else { return [] }
        let oldLines = prev.components(separatedBy: "\n")
        let newLines = displaySource.components(separatedBy: "\n")
        var changed = Set<Int>()
        let maxLines = max(oldLines.count, newLines.count)
        for i in 0..<maxLines {
            let oldLine = i < oldLines.count ? oldLines[i] : ""
            let newLine = i < newLines.count ? newLines[i] : ""
            if oldLine != newLine { changed.insert(i) }
        }
        return changed
    }

    var body: some View {
        VStack(spacing: 0) {
            shaderSelector
            Divider().background(Color.white.opacity(0.1))

            ZStack(alignment: .bottomTrailing) {
                ReadonlyMSLTextView(
                    source: displaySource,
                    variables: parsedVariables,
                    changedLines: changedLines,
                    onVariableClicked: handleVariableClick,
                    onLineReferenceCopied: handleLineReferenceCopy
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if selectedVariable != nil,
                   let target = selectedTarget,
                   !target.isDataFlow {
                    debugOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)))
        .onAppear {
            if selectedTarget == nil, let first = targets.first {
                selectedTarget = first
            }
        }
        .onChange(of: objects2D.count) {
            if selectedTarget == nil, let first = targets.first {
                selectedTarget = first
            }
        }
    }

    // MARK: - Shader Selector

    private var shaderSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(targets) { target in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            cacheCurrentSource()
                            selectedTarget = target
                            selectedVariable = nil
                            debugFragmentOverrides = [:]
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: target.icon)
                                .font(.system(size: 8))
                            Text(target.displayName)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(selectedTarget == target ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedTarget == target
                                    ? (target.isDataFlow ? Color.purple.opacity(0.2) : Color.cyan.opacity(0.2))
                                    : Color.white.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Debug Overlay (draggable, resizable)

    private var debugOverlay: some View {
        VStack(spacing: 0) {
            if let variable = selectedVariable {
                debugTitleBar(variable)

                MetalView(
                    activeShaders: activeShaders,
                    meshType: meshType,
                    backgroundImage: backgroundImage,
                    dataFlowConfig: dataFlowConfig,
                    dataFlow2DConfig: dataFlow2DConfig,
                    paramValues: paramValues,
                    rotationAngle: rotationAngle,
                    canvasMode: canvasMode,
                    objects2D: objects2D,
                    sharedVertexCode2D: sharedVertexCode2D,
                    sharedFragmentCode2D: sharedFragmentCode2D,
                    canvasZoom: canvasZoom,
                    canvasPan: canvasPan,
                    shape2DType: shape2DType,
                    isDebugMode: true,
                    debugFragmentOverrides: debugFragmentOverrides
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                debugChannelBar(variable)
            }
        }
        .frame(width: debugSize.width, height: debugSize.height)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.95)))
                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .offset(debugOffset)
    }

    private func debugTitleBar(_ variable: MSLVariable) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "ladybug")
                .font(.system(size: 9))
                .foregroundColor(.cyan.opacity(0.8))
            Text(variable.name)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
            Text(variable.type.rawValue)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Text("L\(variable.lineNumber + 1)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
            Button(action: { clearDebug() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.cyan.opacity(0.08))
        .gesture(
            DragGesture()
                .onChanged { value in
                    debugOffset = CGSize(
                        width: dragStart.width + value.translation.width,
                        height: dragStart.height + value.translation.height
                    )
                }
                .onEnded { _ in dragStart = debugOffset }
        )
        .onHover { hovering in
            if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
    }

    private func debugChannelBar(_ variable: MSLVariable) -> some View {
        HStack(spacing: 0) {
            channelButton(label: "All", channel: -1, color: .white, variable: variable)
            if variable.type.componentCount >= 1 && variable.type.componentCount > 1 {
                channelButton(label: variable.type.componentCount <= 2 ? "X" : "R",
                              channel: 0, color: .red, variable: variable)
            }
            if variable.type.componentCount >= 2 {
                channelButton(label: variable.type.componentCount <= 2 ? "Y" : "G",
                              channel: 1, color: .green, variable: variable)
            }
            if variable.type.componentCount >= 3 {
                channelButton(label: "B", channel: 2, color: .blue, variable: variable)
            }
            if variable.type.componentCount >= 4 {
                channelButton(label: "A", channel: 3, color: .white.opacity(0.7), variable: variable)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func channelButton(label: String, channel: Int, color: Color, variable: MSLVariable) -> some View {
        let isActive = debugChannel == channel
        return Button(action: {
            debugChannel = channel
            regenerateDebugShader(for: variable, channel: channel)
        }) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label).font(.system(size: 9, weight: isActive ? .bold : .regular))
            }
            .foregroundColor(isActive ? .white : .white.opacity(0.4))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isActive ? color.opacity(0.2) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    @State private var resizeStart: CGSize = .zero

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 8))
            .foregroundColor(.white.opacity(0.25))
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newW = max(180, resizeStart.width + value.translation.width)
                        let newH = max(120, resizeStart.height + value.translation.height)
                        debugSize = CGSize(width: min(newW, 600), height: min(newH, 500))
                    }
                    .onEnded { _ in resizeStart = debugSize }
            )
            .onAppear { resizeStart = debugSize }
            .onHover { hovering in
                if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .padding(4)
    }

    // MARK: - Variable Click Handler

    private func handleVariableClick(_ variable: MSLVariable) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedVariable = variable
            debugChannel = -1
        }
        regenerateDebugShader(for: variable, channel: -1)
    }

    private func regenerateDebugShader(for variable: MSLVariable, channel: Int) {
        guard let target = selectedTarget else { return }

        let debugSource = MSLDebugShaderGenerator.generateDebugFragmentSource(
            originalFragmentSource: fullCompiledSource,
            variable: variable,
            displaySource: displaySource,
            channel: channel
        )

        switch target {
        case .object2DFragment(let id, _):
            debugFragmentOverrides = [id: debugSource]
        case .fullscreen(let id, _):
            debugFragmentOverrides = [id: debugSource]
        case .mesh3DFragment:
            let sentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            debugFragmentOverrides = [sentinel: debugSource]
        default:
            break
        }
    }

    private func handleLineReferenceCopy(_ lineNum: Int, _ lineText: String) {
        guard let target = selectedTarget else { return }
        let ref = "[\(target.displayName):L\(lineNum + 1)] \(lineText.trimmingCharacters(in: .whitespaces))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ref, forType: .string)
    }

    private func clearDebug() {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedVariable = nil
            debugFragmentOverrides = [:]
            debugChannel = -1
            debugOffset = .zero
            dragStart = .zero
        }
    }

    private func cacheCurrentSource() {
        guard let target = selectedTarget else { return }
        previousSources[target.id] = displaySource
    }
}

// MARK: - ReadonlyMSLTextView (NSViewRepresentable)

struct ReadonlyMSLTextView: View {
    let source: String
    let variables: [MSLVariable]
    let changedLines: Set<Int>
    let onVariableClicked: (MSLVariable) -> Void
    let onLineReferenceCopied: (Int, String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            lineNumberGutter
            Divider().background(Color.white.opacity(0.15))
            MSLTextViewWrapper(
                source: source,
                variables: variables,
                changedLines: changedLines,
                onVariableClicked: onVariableClicked
            )
        }
    }

    private var lineNumberGutter: some View {
        let lines = source.components(separatedBy: "\n")
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(spacing: 0) {
                        if changedLines.contains(idx) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.green.opacity(0.6))
                                .frame(width: 3, height: 14)
                                .padding(.trailing, 2)
                        }
                        Text("\(idx + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .frame(height: 17, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onLineReferenceCopied(idx, line)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 6)
        }
        .frame(width: 44)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)))
    }
}

/// Minimal NSTextView wrapper matching the working CodeEditor pattern.
private struct MSLTextViewWrapper: NSViewRepresentable {
    let source: String
    let variables: [MSLVariable]
    let changedLines: Set<Int>
    let onVariableClicked: (MSLVariable) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onVariableClicked: onVariableClicked) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)
        textView.textColor = NSColor(white: 0.9, alpha: 1.0)
        textView.textContainerInset = NSSize(width: 4, height: 8)

        context.coordinator.textView = textView

        let clickGesture = NSClickGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        textView.addGestureRecognizer(clickGesture)

        textView.string = source
        context.coordinator.applyHighlighting(to: textView, variables: variables, changedLines: changedLines)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onVariableClicked = onVariableClicked
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != source {
            textView.string = source
            context.coordinator.applyHighlighting(to: textView, variables: variables, changedLines: changedLines)
        }
    }

    class Coordinator: NSObject {
        var onVariableClicked: (MSLVariable) -> Void
        weak var textView: NSTextView?

        init(onVariableClicked: @escaping (MSLVariable) -> Void) {
            self.onVariableClicked = onVariableClicked
        }

        func applyHighlighting(to textView: NSTextView, variables: [MSLVariable], changedLines: Set<Int>) {
            guard let storage = textView.textStorage else { return }
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            MSLHighlighter.apply(to: storage, font: font, variables: variables)

            guard !changedLines.isEmpty else { return }
            let lines = storage.string.components(separatedBy: "\n")
            var offset = 0
            let changeColor = NSColor(red: 0.2, green: 0.35, blue: 0.15, alpha: 1.0)
            storage.beginEditing()
            for (i, line) in lines.enumerated() {
                if changedLines.contains(i) {
                    let range = NSRange(location: offset, length: (line as NSString).length)
                    storage.addAttribute(.backgroundColor, value: changeColor, range: range)
                }
                offset += (line as NSString).length + 1
            }
            storage.endEditing()
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let tv = textView else { return }
            let point = gesture.location(in: tv)
            let charIndex = tv.characterIndexForInsertion(at: point)
            guard charIndex < tv.string.count,
                  let storage = tv.textStorage else { return }

            let attrs = storage.attributes(at: charIndex, effectiveRange: nil)
            if let variable = attrs[MSLHighlighter.variableAttributeKey] as? MSLVariable {
                onVariableClicked(variable)
            }
        }
    }
}

