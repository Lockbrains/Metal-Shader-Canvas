//
//  LabView.swift
//  macOSShaderCanvas
//
//  The Lab mode editor — a superset of Canvas with a dedicated multi-panel layout
//  for AI-collaborative shader development. Provides all Canvas editing capabilities
//  plus Reference Board, Project Document, collaborative discussion, and parameter
//  tuning with "engineering haptics" feedback.
//
//  LAYOUT:
//  ┌──────────────┬──────────────────────┬──────────────┐
//  │  Left Panel  │      Center          │  Right Panel │
//  │  - Refs      │  - Phase Indicator   │  - Lab Chat  │
//  │  - Document  │  - Metal Viewport    │  - Params    │
//  │              │  - Shader Editor     │              │
//  └──────────────┴──────────────────────┴──────────────┘
//

import SwiftUI
import UniformTypeIdentifiers
import simd

// MARK: - Chat State Container

/// Isolates chat message mutations from LabView's body evaluation.
/// Without this, every `messages.append` would re-evaluate the entire
/// LabView body — including MetalView (NSViewRepresentable), which
/// triggers `updateNSView` and blocks the main thread.
@Observable
class LabChatStore {
    var messages: [ChatMessage] = []
}

// MARK: - LabView

struct LabView: View {

    // MARK: - Navigation

    var appState: AppState
    var recentManager: RecentProjectManager

    // MARK: - Shader State (superset of Canvas)

    @State private var activeShaders: [ActiveShader] = []
    @State private var editingShaderID: UUID? = nil
    @State private var canvasMode: CanvasMode = .threeDimensionalLab

    // MARK: - 2D Scene State

    @State private var shape2DType: Shape2DType = .roundedRectangle
    @State private var objects2D: [Object2D] = []
    @State private var sharedVertexCode2D: String = ShaderSnippets.distortion2DTemplate
    @State private var sharedFragmentCode2D: String = ShaderSnippets.fragment2DDemo
    @State private var selectedObjectID: UUID? = nil
    @State private var canvasZoom: Float = 1.0
    @State private var canvasPan: simd_float2 = .zero

    // MARK: - Mesh & Background

    @State private var meshType: MeshType = .sphere
    @State private var customFileName: String? = nil
    @State private var backgroundImage: NSImage? = nil

    // MARK: - Data Flow

    @State private var dataFlowConfig = DataFlowConfig()
    @State private var dataFlow2DConfig = DataFlow2DConfig()

    // MARK: - Parameters

    @State private var paramValues: [String: [Float]] = [:]

    // MARK: - Canvas File State

    @State private var canvasName: String = "Untitled Lab Project"
    @State private var currentFileURL: URL? = nil
    @State private var rotationAngle: Double = 0
    @State private var hasUnsavedChanges = false
    @State private var showingBackToHubConfirm = false

    // MARK: - AI State

    @State private var aiSettings = AISettings()
    @State private var showingAISettings = false
    @State private var chatStore = LabChatStore()
    @State private var compilationError: String? = nil

    // MARK: - Lab-Specific State

    @State private var labSession = LabSession()
    @State private var references: [ReferenceItem] = []
    @State private var projectDocument = ProjectDocument()
    @State private var parameterSnapshots: [ParameterSnapshot] = []
    @State private var adversarialProposals: [AdversarialProposal] = []

    // MARK: - Panel State

    @State private var leftPanelTab: LeftPanelTab = .references
    @State private var rightPanelTab: RightPanelTab = .chat
    @State private var isLeftPanelVisible = true
    @State private var isRightPanelVisible = true
    @State private var isShaderEditorVisible = false

    enum LeftPanelTab: String, CaseIterable {
        case references = "References"
        case document = "Document"
        case layers = "Layers"
    }

    enum RightPanelTab: String, CaseIterable {
        case chat = "Discussion"
        case parameters = "Parameters"
        case adversarial = "Adversarial"
    }

    private let sidePanelWidth: CGFloat = 300

    // MARK: - Body

    var body: some View {
        let _ = print("[DIAG] LabView.body EVALUATED  \(CFAbsoluteTimeGetCurrent())")
        labMainLayout
            .modifier(LabEventModifier(
                onInit: { initializeFromAppState() },
                onBackToHub: { requestNavigateBackToHub() },
                onSave: { performSave() },
                onSaveAs: { performSaveAs() },
                onShowSettings: { showingAISettings = true },
                onCompilationResult: { error in
                    withAnimation(.easeInOut(duration: 0.2)) { compilationError = error }
                }
            ))
            .modifier(LabChangeTrackingModifier(
                activeShaders: activeShaders,
                objects2D: objects2D,
                paramValues: paramValues,
                canvasName: canvasName,
                dataFlowConfig: dataFlowConfig,
                dataFlow2DConfig: dataFlow2DConfig,
                sharedVertexCode2D: sharedVertexCode2D,
                sharedFragmentCode2D: sharedFragmentCode2D,
                onChanged: { hasUnsavedChanges = true }
            ))
    }

    private var labMainLayout: some View {
        ZStack {
            Color(nsColor: NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                labTopBar
                Divider().background(Color.white.opacity(0.1))
                phaseIndicator
                Divider().background(Color.white.opacity(0.1))

                HStack(spacing: 0) {
                    if isLeftPanelVisible {
                        leftPanel
                            .frame(width: sidePanelWidth)
                        Divider().background(Color.white.opacity(0.1))
                    }

                    centerPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isRightPanelVisible {
                        Divider().background(Color.white.opacity(0.1))
                        rightPanel
                            .frame(width: sidePanelWidth + 40)
                    }
                }
            }
        }
        .alert(String(localized: "Back to Hub"), isPresented: $showingBackToHubConfirm) {
            Button(String(localized: "Save & Return"), role: nil) {
                performSave()
                navigateBackToHub()
            }
            Button(String(localized: "Discard & Return"), role: .destructive) {
                navigateBackToHub()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Returning to Hub will discard your current progress.")
        }
        .sheet(isPresented: $showingAISettings) {
            AISettingsView(settings: aiSettings)
        }
    }

    // MARK: - Initialization

    private func initializeFromAppState() {
        canvasMode = appState.canvasMode
        if let url = appState.openFileURL {
            openCanvas(from: url)
        }
    }

    // MARK: - Top Bar

    private var labTopBar: some View {
        HStack(spacing: 12) {
            Button(action: { requestNavigateBackToHub() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.6))

            Image(systemName: "flask.fill")
                .font(.system(size: 14))
                .foregroundStyle(.linearGradient(
                    colors: canvasMode.is2D ? [.green, .teal] : [.orange, .red],
                    startPoint: .leading, endPoint: .trailing
                ))

            Text(canvasName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            Text(canvasMode.rawValue)
                .font(.caption2).bold()
                .foregroundColor(canvasMode.is2D ? .green : .orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((canvasMode.is2D ? Color.green : Color.orange).opacity(0.15))
                .cornerRadius(4)

            Spacer()

            HStack(spacing: 8) {
                Button(action: { withAnimation { isLeftPanelVisible.toggle() } }) {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(isLeftPanelVisible ? .white : .white.opacity(0.3))
                }
                .buttonStyle(.plain)

                Button(action: { withAnimation { isShaderEditorVisible.toggle() } }) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(isShaderEditorVisible ? .white : .white.opacity(0.3))
                }
                .buttonStyle(.plain)

                Button(action: { withAnimation { isRightPanelVisible.toggle() } }) {
                    Image(systemName: "sidebar.right")
                        .foregroundColor(isRightPanelVisible ? .white : .white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Phase Indicator

    private var phaseIndicator: some View {
        HStack(spacing: 0) {
            ForEach(LabPhase.allCases) { phase in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        labSession.advanceTo(phase)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: phase.icon)
                            .font(.system(size: 10))
                        Text(phase.displayName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        labSession.currentPhase == phase
                            ? Color.white.opacity(0.12)
                            : Color.clear
                    )
                    .foregroundColor(
                        labSession.currentPhase == phase
                            ? .white
                            : labSession.hasVisited(phase)
                                ? .white.opacity(0.5)
                                : .white.opacity(0.25)
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                if phase != LabPhase.allCases.last {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.15))
                        .padding(.horizontal, 2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            Picker("", selection: $leftPanelTab) {
                ForEach(LeftPanelTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider().background(Color.white.opacity(0.1))

            switch leftPanelTab {
            case .references:
                ReferenceBoard(references: $references)
            case .document:
                ProjectDocumentView(document: $projectDocument)
            case .layers:
                layerListPanel
            }
        }
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Center Panel

    private var centerPanel: some View {
        VStack(spacing: 0) {
            MetalView(
                activeShaders: activeShaders,
                meshType: meshType,
                backgroundImage: backgroundImage,
                dataFlowConfig: dataFlowConfig,
                dataFlow2DConfig: dataFlow2DConfig,
                paramValues: paramValues,
                rotationAngle: Float(rotationAngle),
                canvasMode: canvasMode,
                objects2D: objects2D,
                sharedVertexCode2D: sharedVertexCode2D,
                sharedFragmentCode2D: sharedFragmentCode2D,
                canvasZoom: canvasZoom,
                canvasPan: canvasPan,
                shape2DType: shape2DType
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isShaderEditorVisible, let shaderID = editingShaderID,
               let index = activeShaders.firstIndex(where: { $0.id == shaderID }) {
                Divider().background(Color.white.opacity(0.1))
                shaderEditorPanel(index: index)
                    .frame(height: 220)
            }
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            Picker("", selection: $rightPanelTab) {
                ForEach(RightPanelTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider().background(Color.white.opacity(0.1))

            switch rightPanelTab {
            case .chat:
                LabChatView(
                    chatStore: chatStore,
                    labSession: $labSession,
                    references: references,
                    projectDocument: $projectDocument,
                    activeShaders: activeShaders,
                    aiSettings: aiSettings,
                    canvasMode: canvasMode,
                    dataFlowConfig: dataFlowConfig,
                    dataFlow2DConfig: dataFlow2DConfig,
                    objects2D: objects2D,
                    sharedVertexCode2D: sharedVertexCode2D,
                    sharedFragmentCode2D: sharedFragmentCode2D,
                    compilationError: compilationError,
                    paramValues: paramValues,
                    meshType: meshType,
                    onAgentActions: { actions in executeAgentActions(actions) }
                )
            case .parameters:
                ParameterTuningView(
                    paramValues: $paramValues,
                    snapshots: $parameterSnapshots,
                    activeShaders: activeShaders,
                    canvasMode: canvasMode,
                    objects2D: objects2D,
                    sharedFragmentCode2D: sharedFragmentCode2D
                )
            case .adversarial:
                AdversarialView(
                    proposals: $adversarialProposals,
                    paramValues: $paramValues,
                    activeShaders: $activeShaders,
                    projectDocument: $projectDocument,
                    aiSettings: aiSettings,
                    onApplyCode: { layerName, code in
                        if let idx = activeShaders.firstIndex(where: { $0.name == layerName }) {
                            activeShaders[idx].code = code
                        }
                    }
                )
            }
        }
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Layer List (Left Panel Tab)

    private var layerListPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if canvasMode.is3D {
                    ForEach(activeShaders) { shader in
                        layerRow(shader)
                    }
                    Divider().padding(.vertical, 4)
                    addLayerButtons3D
                } else {
                    ForEach(objects2D) { obj in
                        objectRow(obj)
                    }
                    Divider().padding(.vertical, 4)
                    ForEach(activeShaders.filter { $0.category == .fullscreen }) { shader in
                        layerRow(shader)
                    }
                }
            }
            .padding(8)
        }
    }

    private func layerRow(_ shader: ActiveShader) -> some View {
        HStack(spacing: 6) {
            Image(systemName: shader.category.icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Text(shader.name)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
            Spacer()
            Button(action: {
                withAnimation {
                    editingShaderID = shader.id
                    isShaderEditorVisible = true
                }
            }) {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(editingShaderID == shader.id ? Color.white.opacity(0.08) : Color.clear)
        .cornerRadius(4)
    }

    private func objectRow(_ obj: Object2D) -> some View {
        HStack(spacing: 6) {
            Image(systemName: obj.shapeType.icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Text(obj.name)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(selectedObjectID == obj.id ? Color.white.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .onTapGesture { selectedObjectID = obj.id }
    }

    private var addLayerButtons3D: some View {
        VStack(spacing: 4) {
            ForEach([ShaderCategory.vertex, .fragment, .fullscreen], id: \.self) { cat in
                Button(action: { addShader(category: cat) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 10))
                        Text(cat.rawValue)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Shader Editor

    private func shaderEditorPanel(index: Int) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(activeShaders[index].name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button(action: { withAnimation { isShaderEditorVisible = false } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            TextEditor(text: $activeShaders[index].code)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.3))
        }
        .background(Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)))
    }

    // MARK: - Canvas Actions

    private func addShader(category: ShaderCategory) {
        let code = CanvasActions.defaultShaderCode(for: category, is2D: canvasMode.is2D, dataFlowConfig: dataFlowConfig)
        let name = "\(category.rawValue) Layer \(activeShaders.filter { $0.category == category }.count + 1)"
        let shader = ActiveShader(category: category, name: name, code: code)
        activeShaders.append(shader)
        CanvasActions.sortShadersByCategory(&activeShaders)
        withAnimation {
            editingShaderID = shader.id
            isShaderEditorVisible = true
        }
    }

    private func executeAgentActions(_ actions: [AgentAction]) {
        applyDataFlowActions(actions)

        var noLocks = Set<String>()
        let result = CanvasActions.executeAgentActions(
            actions,
            activeShaders: &activeShaders,
            objects2D: &objects2D,
            sharedVertexCode2D: &sharedVertexCode2D,
            sharedFragmentCode2D: &sharedFragmentCode2D,
            approvedShapeLocks: &noLocks
        )
        for req in result.shapeLockRequests {
            if let idx = objects2D.firstIndex(where: { $0.name == req.objectName }) {
                objects2D[idx].shapeLocked = true
            }
        }
        if let id = result.firstShaderID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation {
                    editingShaderID = id
                    isShaderEditorVisible = true
                }
            }
        } else if let id = result.firstObjectID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { selectedObjectID = id }
            }
        }
    }

    private func applyDataFlowActions(_ actions: [AgentAction]) {
        for action in actions where action.type == .enableDataFlow {
            let fields = Set(
                action.code
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            )
            if canvasMode.is2D {
                var cfg = dataFlow2DConfig
                if fields.contains("time") { cfg.timeEnabled = true }
                if fields.contains("mouse") { cfg.mouseEnabled = true }
                if fields.contains("objectposition") { cfg.objectPositionEnabled = true }
                if fields.contains("screenuv") { cfg.screenUVEnabled = true }
                if cfg != dataFlow2DConfig { dataFlow2DConfig = cfg }
            } else {
                var cfg = dataFlowConfig
                if fields.contains("normal") { cfg.normalEnabled = true }
                if fields.contains("uv") { cfg.uvEnabled = true }
                if fields.contains("time") { cfg.timeEnabled = true }
                if fields.contains("worldposition") { cfg.worldPositionEnabled = true }
                if fields.contains("worldnormal") { cfg.worldNormalEnabled = true }
                if fields.contains("viewdirection") { cfg.viewDirectionEnabled = true }
                cfg.resolveDependencies()
                if cfg != dataFlowConfig { dataFlowConfig = cfg }
            }
        }
    }

    // MARK: - File I/O

    private func requestNavigateBackToHub() {
        if hasUnsavedChanges {
            showingBackToHubConfirm = true
        } else {
            navigateBackToHub()
        }
    }

    private func navigateBackToHub() {
        hasUnsavedChanges = false
        appState.currentScreen = .hub
        appState.openFileURL = nil
    }

    private func performSave() {
        if let url = currentFileURL {
            saveCanvas(to: url)
        } else {
            performSaveAs()
        }
    }

    private func performSaveAs() {
        let panel = NSSavePanel()
        panel.title = "Save Lab Project"
        panel.nameFieldStringValue = canvasName + ".shadercanvas"
        panel.allowedContentTypes = [.shaderCanvas]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            saveCanvas(to: url)
        }
    }

    private func saveCanvas(to url: URL) {
        var session = labSession
        session.parameterSnapshots = parameterSnapshots
        session.adversarialProposals = adversarialProposals
        let doc = CanvasActions.buildDocument(
            name: canvasName, mode: canvasMode, meshType: meshType,
            shape2DType: shape2DType, shaders: activeShaders,
            dataFlow: dataFlowConfig, dataFlow2D: dataFlow2DConfig,
            paramValues: paramValues, objects2D: objects2D,
            sharedVertexCode2D: sharedVertexCode2D,
            sharedFragmentCode2D: sharedFragmentCode2D,
            labSession: session,
            references: references.isEmpty ? nil : references,
            projectDocument: projectDocument.isEmpty ? nil : projectDocument
        )
        do {
            try CanvasActions.saveDocument(doc, to: url)
            currentFileURL = url
            hasUnsavedChanges = false
            let savedName = canvasName
            let savedMode = canvasMode
            let savedURL = url
            Task {
                let capture = await Task.detached { MetalRenderer.current?.captureForAI() }.value
                if let data = capture {
                    recentManager.addRecent(name: savedName, fileURL: savedURL, mode: savedMode, snapshot: NSImage(data: data))
                } else {
                    recentManager.addRecent(name: savedName, fileURL: savedURL, mode: savedMode)
                }
            }
        } catch {
            print("Lab save error: \(error)")
        }
    }

    private func openCanvas(from url: URL) {
        do {
            let doc = try CanvasActions.loadDocument(from: url)
            canvasMode = doc.mode
            canvasName = doc.name
            meshType = doc.meshType
            shape2DType = doc.shape2DType
            activeShaders = doc.shaders
            dataFlowConfig = doc.dataFlow
            dataFlow2DConfig = doc.dataFlow2D
            paramValues = doc.paramValues
            objects2D = doc.objects2D ?? []
            sharedVertexCode2D = doc.sharedVertexCode2D ?? ShaderSnippets.distortion2DTemplate
            sharedFragmentCode2D = doc.sharedFragmentCode2D ?? ShaderSnippets.fragment2DDemo
            currentFileURL = url

            if let session = doc.labSession {
                labSession = session
                parameterSnapshots = session.parameterSnapshots
                adversarialProposals = session.adversarialProposals
            }
            if let refs = doc.references { references = refs }
            if let projDoc = doc.projectDocument { projectDocument = projDoc }

            recentManager.addRecent(name: doc.name, fileURL: url, mode: doc.mode)
            Task { @MainActor in hasUnsavedChanges = false }
        } catch {
            print("Lab open error: \(error)")
        }
    }
}

// MARK: - LabView Helper Modifiers

/// Extracts lifecycle and notification receivers into a separate modifier
/// to reduce type-checker load on LabView.body.
private struct LabEventModifier: ViewModifier {
    let onInit: () -> Void
    let onBackToHub: () -> Void
    let onSave: () -> Void
    let onSaveAs: () -> Void
    let onShowSettings: () -> Void
    let onCompilationResult: (String?) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { onInit() }
            .onReceive(NotificationCenter.default.publisher(for: .backToHub)) { _ in onBackToHub() }
            .onReceive(NotificationCenter.default.publisher(for: .canvasSave)) { _ in onSave() }
            .onReceive(NotificationCenter.default.publisher(for: .canvasSaveAs)) { _ in onSaveAs() }
            .onReceive(NotificationCenter.default.publisher(for: .aiSettings)) { _ in onShowSettings() }
            .onReceive(NotificationCenter.default.publisher(for: .shaderCompilationResult)) { n in
                onCompilationResult(n.object as? String)
            }
    }
}

/// Tracks all state changes that mark the document as unsaved.
/// Consolidated into a single modifier to help the Swift type-checker.
private struct LabChangeTrackingModifier: ViewModifier {
    let activeShaders: [ActiveShader]
    let objects2D: [Object2D]
    let paramValues: [String: [Float]]
    let canvasName: String
    let dataFlowConfig: DataFlowConfig
    let dataFlow2DConfig: DataFlow2DConfig
    let sharedVertexCode2D: String
    let sharedFragmentCode2D: String
    let onChanged: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: activeShaders) { onChanged() }
            .onChange(of: objects2D) { onChanged() }
            .onChange(of: paramValues) { onChanged() }
            .onChange(of: canvasName) { onChanged() }
            .onChange(of: dataFlowConfig) { onChanged() }
            .onChange(of: dataFlow2DConfig) { onChanged() }
            .onChange(of: sharedVertexCode2D) { onChanged() }
            .onChange(of: sharedFragmentCode2D) { onChanged() }
    }
}
