//
//  ContentView.swift
//  macOSShaderCanvas
//
//  The main UI of the application. This single view orchestrates:
//  - The Metal rendering viewport (MetalView)
//  - The layer sidebar (add/remove/edit shader layers)
//  - The inline shader code editor (CodeEditor)
//  - The tutorial panel (step-by-step Metal lessons)
//  - The AI chat overlay
//  - Canvas file management (new / save / open)
//
//  STATE MANAGEMENT:
//  ─────────────────
//  All mutable application state is declared as @State properties here.
//  This state is passed down to child views as bindings or plain values:
//
//    @State activeShaders → MetalView → MetalRenderer (rendering)
//    @State activeShaders → ShaderEditorView (code editing)
//    @State meshType      → MetalView → MetalRenderer (mesh selection)
//    @State backgroundImage → MetalView → MetalRenderer (background)
//
//  NOTIFICATION HANDLING:
//  ──────────────────────
//  Menu commands arrive as NSNotification.Name posts (see macOSShaderCanvasApp.swift).
//  ContentView subscribes with .onReceive() modifiers to handle each menu action.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - ContentView

/// The root view of the application. Manages all UI panels and app state.
struct ContentView: View {

    // MARK: - Shader State

    /// All active shader layers, ordered by category (vertex → fragment → fullscreen).
    /// This array is the single source of truth for what the Metal renderer should compile.
    @State private var activeShaders: [ActiveShader] = []

    /// The ID of the shader currently being edited. nil = editor panel closed.
    @State private var editingShaderID: UUID? = nil

    // MARK: - Mesh & Background State

    /// The 3D mesh to render. Defaults to .sphere.
    @State private var meshType: MeshType = .sphere

    /// Display name for a custom-uploaded mesh file (for the tooltip).
    @State private var customFileName: String? = nil

    /// Optional background image rendered behind the 3D mesh.
    @State private var backgroundImage: NSImage? = nil

    // MARK: - File Importer State

    @State private var fileImporterPresented = false
    @State private var fileImporterMode: FileImporterMode = .mesh

    /// Determines whether the file importer dialog loads a mesh or a background image.
    enum FileImporterMode {
        case mesh, background
    }

    // MARK: - UI State

    @State private var isSidebarVisible = true

    // MARK: - Canvas File State

    /// The display name of the current workspace (shown in the top-left header).
    @State private var canvasName: String = String(localized: "Untitled Canvas")

    /// The file URL of the last saved/opened .shadercanvas file. nil = never saved.
    @State private var currentFileURL: URL? = nil

    @State private var showingNewCanvasConfirm = false
    @State private var isRenamingCanvas = false
    @State private var editedCanvasName = ""

    // MARK: - Tutorial State

    /// Whether the tutorial panel is currently visible.
    @State private var isTutorialMode = false
    @State private var tutorialStepIndex = 0
    @State private var showingSolution = false

    /// AI-generated tutorial steps (overrides built-in TutorialData when set).
    @State private var aiTutorialSteps: [TutorialStep]? = nil

    // MARK: - AI State

    @State private var aiSettings = AISettings()
    @State private var showingAISettings = false
    @State private var isAIChatActive = false
    @State private var chatMessages: [ChatMessage] = []

    // MARK: - Data Flow State
    
    /// Configurable vertex data fields shared across all mesh shaders.
    @State private var dataFlowConfig = DataFlowConfig()
    
    // MARK: - User Parameter State
    
    /// Current values for all user-declared shader parameters (keyed by param name).
    @State private var paramValues: [String: [Float]] = [:]
    
    /// Which parameter is currently being renamed (nil = none).
    @State private var renamingParamName: String? = nil
    @State private var editedParamName = ""
    
    /// Last shader compilation error message (nil = compilation OK).
    @State private var compilationError: String? = nil
    
    // MARK: - Undo Delete State

    /// Stores the most recently deleted shader for undo functionality.
    @State private var lastDeletedShader: ActiveShader? = nil
    @State private var lastDeletedIndex: Int = 0
    @State private var showUndoToast = false

    /// Token to prevent stale undo toast dismissals from conflicting with new deletes.
    @State private var undoToken = UUID()

    // MARK: - Body

    var body: some View {
        ZStack {
            // Layer 0: Metal rendering viewport (fills the entire window).
            MetalView(activeShaders: activeShaders, meshType: meshType, backgroundImage: backgroundImage, dataFlowConfig: dataFlowConfig, paramValues: paramValues)
                .ignoresSafeArea()

            // Layer 1: UI overlay (sidebar, buttons, canvas name).
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        // Canvas name display + sidebar toggle button.
                        HStack(spacing: 10) {
                            Button(action: {
                                withAnimation { isSidebarVisible.toggle() }
                            }) {
                                Image(systemName: "sidebar.left")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)

                            if isRenamingCanvas {
                                TextField("", text: $editedCanvasName, onCommit: {
                                    let trimmed = editedCanvasName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty { canvasName = trimmed }
                                    isRenamingCanvas = false
                                })
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(4)
                                .frame(maxWidth: 200)

                                Button(action: {
                                    let trimmed = editedCanvasName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty { canvasName = trimmed }
                                    isRenamingCanvas = false
                                }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green.opacity(0.8))
                                }.buttonStyle(.plain)
                            } else {
                                Text(verbatim: canvasName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))

                                Button(action: {
                                    editedCanvasName = canvasName
                                    isRenamingCanvas = true
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.4))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 8)

                        // Collapsible layer sidebar.
                        if isSidebarVisible {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Layers")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.bottom, 4)

                                if activeShaders.isEmpty {
                                    Text("No Active Shaders")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.6))
                                } else {
                                    ForEach(activeShaders) { shader in
                                        HStack {
                                            Image(systemName: shader.category.icon)
                                                .foregroundColor(.blue)
                                            Text(verbatim: shader.name)
                                                .foregroundColor(.white)
                                            Spacer()
                                            Button(action: {
                                                withAnimation { editingShaderID = shader.id }
                                            }) {
                                                Image(systemName: "pencil.circle")
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundColor(.white.opacity(0.7))

                                            Button(action: { removeShader(shader) }) {
                                                Image(systemName: "xmark.circle.fill")
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundColor(.red.opacity(0.8))
                                        }
                                        .padding(8)
                                        .background(Color.black.opacity(0.4))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            .frame(width: 220)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            
                            dataFlowPanel
                            parametersPanel
                        }
                    }
                    .padding()

                    Spacer()

                    // AI chat toggle button (top-right corner).
                    VStack {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) { isAIChatActive.toggle() }
                        }) {
                            Image(systemName: isAIChatActive ? "sparkle" : "sparkles")
                                .font(.title2)
                                .foregroundColor(isAIChatActive ? .purple : .white)
                                .padding(8)
                                .background(isAIChatActive ? Color.purple.opacity(0.3) : Color.black.opacity(0.4))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help("AI Chat (⌘L)")
                        .padding()
                        Spacer()
                    }
                }

                Spacer()

                // Bottom toolbar: shader type buttons (left) + mesh/background controls (right).
                HStack(alignment: .bottom) {
                    // Shader layer creation buttons.
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.trailing, 4)

                        Button(action: { addShader(category: .vertex, name: String(localized: "Vertex Layer")) }) {
                            Text(verbatim: "VS").fontWeight(.bold).padding(.horizontal, 12).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain).background(Color.blue.opacity(0.8)).cornerRadius(8).foregroundColor(.white).help("Vertex Shader")

                        Button(action: { addShader(category: .fragment, name: String(localized: "Fragment Layer")) }) {
                            Text(verbatim: "FS").fontWeight(.bold).padding(.horizontal, 12).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain).background(Color.purple.opacity(0.8)).cornerRadius(8).foregroundColor(.white).help("Fragment Shader")

                        Button(action: { addShader(category: .fullscreen, name: String(localized: "Fullscreen Layer")) }) {
                            Text(verbatim: "PP").fontWeight(.bold).padding(.horizontal, 12).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain).background(Color.orange.opacity(0.8)).cornerRadius(8).foregroundColor(.white).help("Post Processing")
                    }
                    .padding(10).background(Color.black.opacity(0.6)).cornerRadius(12).padding()

                    Spacer()

                    // Mesh and background controls.
                    HStack(spacing: 12) {
                        Button(action: { fileImporterMode = .background; fileImporterPresented = true }) {
                            Image(systemName: "photo.fill").font(.title2)
                                .foregroundColor(backgroundImage != nil ? .green : .white)
                        }.buttonStyle(.plain).help("Background Image")

                        if backgroundImage != nil {
                            Button(action: { backgroundImage = nil }) {
                                Image(systemName: "photo.badge.minus").font(.title3)
                                    .foregroundColor(.red.opacity(0.8))
                            }.buttonStyle(.plain).help("Remove Background")
                        }

                        Divider().frame(height: 24).background(Color.white.opacity(0.3))

                        Button(action: { meshType = .sphere; customFileName = nil }) {
                            Image(systemName: "circle.fill").font(.title2)
                                .foregroundColor(meshType == .sphere ? .blue : .white)
                        }.buttonStyle(.plain).help("Sphere")

                        Button(action: { meshType = .cube; customFileName = nil }) {
                            Image(systemName: "square.fill").font(.title2)
                                .foregroundColor(meshType == .cube ? .blue : .white)
                        }.buttonStyle(.plain).help("Cube")

                        Button(action: { fileImporterMode = .mesh; fileImporterPresented = true }) {
                            Image(systemName: "cube.box.fill").font(.title2)
                                .foregroundColor({ if case .custom = meshType { return Color.blue }; return Color.white }())
                        }.buttonStyle(.plain).help(customFileName ?? String(localized: "Upload Custom Model..."))
                    }
                    .padding(10).background(Color.black.opacity(0.6)).cornerRadius(12).padding()
                }
            }

            // Tutorial instruction panel (bottom overlay).
            if isTutorialMode {
                VStack {
                    Spacer()
                    TutorialPanel(
                        step: currentTutorialSteps[tutorialStepIndex],
                        currentIndex: tutorialStepIndex,
                        totalSteps: currentTutorialSteps.count,
                        showingSolution: $showingSolution,
                        onPrevious: { navigateTutorial(delta: -1) },
                        onNext: { navigateTutorial(delta: 1) },
                        onShowSolution: { applySolution() },
                        onExit: { exitTutorial() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(0.5)
            }

            // Shader editor panel (slides in from the right).
            if let editingID = editingShaderID,
               let index = activeShaders.firstIndex(where: { $0.id == editingID }) {
                HStack(spacing: 0) {
                    Spacer()
                    ZStack(alignment: .bottom) {
                        ShaderEditorView(shader: $activeShaders[index], dataFlowConfig: dataFlowConfig, onClose: {
                            withAnimation { editingShaderID = nil }
                        })
                        
                        if let error = compilationError {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "xmark.octagon.fill")
                                        .foregroundColor(.red)
                                    Text("Compile Error")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.red)
                                    Spacer()
                                    Button(action: { compilationError = nil }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.5))
                                    }.buttonStyle(.plain)
                                }
                                Text(error)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(6)
                                    .textSelection(.enabled)
                            }
                            .padding(10)
                            .background(Color.red.opacity(0.15))
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.4), lineWidth: 1))
                            .padding(8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .id(editingID)
                    .frame(width: 500)
                    .transition(.move(edge: .trailing))
                }
                .zIndex(1)
            }

            // AI Chat overlay (bottom center).
            if isAIChatActive {
                VStack {
                    Spacer()
                    AIChatView(
                        messages: $chatMessages,
                        isActive: $isAIChatActive,
                        activeShaders: activeShaders,
                        aiSettings: aiSettings,
                        dataFlowConfig: dataFlowConfig,
                        onGenerateTutorial: { steps in loadAITutorial(steps) },
                        onAgentActions: { actions in executeAgentActions(actions) }
                    )
                    .frame(maxHeight: 400)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(2)

                // Apple Intelligence-style animated gradient border.
                AIGlowBorder()
                    .zIndex(3)
                    .transition(.opacity)
            }

            // Undo delete toast notification (bottom center).
            if showUndoToast, let deleted = lastDeletedShader {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .foregroundColor(.white.opacity(0.7))
                        Text("已删除「\(deleted.name)」")
                            .font(.system(size: 13))
                            .foregroundColor(.white)

                        Button(action: { undoDelete() }) {
                            Text("撤销")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.yellow)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("z", modifiers: .command)

                        Button(action: {
                            withAnimation { showUndoToast = false }
                            lastDeletedShader = nil
                        }) {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .padding(.bottom, 80)
                }
                .zIndex(4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        // Subscribe to menu command notifications.
        .onReceive(NotificationCenter.default.publisher(for: .canvasNew)) { _ in
            showingNewCanvasConfirm = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .canvasSave)) { _ in
            performSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .canvasSaveAs)) { _ in
            performSaveAs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .canvasOpen)) { _ in
            performOpen()
        }
        .onReceive(NotificationCenter.default.publisher(for: .canvasTutorial)) { _ in
            startTutorial()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiSettings)) { _ in
            showingAISettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiChat)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) { isAIChatActive.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shaderCompilationResult)) { notification in
            withAnimation(.easeInOut(duration: 0.2)) {
                compilationError = notification.object as? String
            }
        }
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: fileImporterContentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                switch fileImporterMode {
                case .mesh:
                    meshType = .custom(url)
                    customFileName = url.lastPathComponent
                case .background:
                    if let image = NSImage(contentsOf: url) {
                        backgroundImage = image
                    }
                }
            }
        }
        .alert("New Canvas", isPresented: $showingNewCanvasConfirm) {
            Button("Save & Create New", role: nil) {
                performSave()
                resetToNewCanvas()
            }
            Button("Discard & Create New", role: .destructive) {
                resetToNewCanvas()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Current canvas may have unsaved changes.")
        }
        .sheet(isPresented: $showingAISettings) {
            AISettingsView(settings: aiSettings)
        }
    }

    /// Returns the allowed file types for the current file importer mode.
    private var fileImporterContentTypes: [UTType] {
        switch fileImporterMode {
        case .mesh:
            return [UTType.usdz, UTType.usd, UTType(filenameExtension: "obj")].compactMap { $0 }
        case .background:
            return [UTType.png, UTType.jpeg, UTType.heic, UTType.tiff, UTType.bmp]
        }
    }

    // MARK: - AI Tutorial

    /// Returns the active tutorial steps: AI-generated if available, otherwise built-in.
    private var currentTutorialSteps: [TutorialStep] {
        aiTutorialSteps ?? TutorialData.steps
    }

    /// Loads AI-generated tutorial steps and enters tutorial mode.
    private func loadAITutorial(_ steps: [TutorialStep]) {
        aiTutorialSteps = steps
        isTutorialMode = true
        tutorialStepIndex = 0
        showingSolution = false
        loadTutorialStep(0)
    }

    // MARK: - Shader Management

    /// Creates a new shader layer with demo code and adds it to the workspace.
    ///
    /// Layers are auto-sorted by category to maintain the rendering pipeline order:
    /// vertex (0) → fragment (1) → fullscreen (2).
    ///
    /// - Parameters:
    ///   - category: The shader type (.vertex, .fragment, or .fullscreen).
    ///   - name: The base display name (a counter suffix is appended).
    private func addShader(category: ShaderCategory, name: String) {
        let code: String
        switch category {
        case .vertex: code = ShaderSnippets.generateVertexDemo(config: dataFlowConfig)
        case .fragment: code = ShaderSnippets.fragmentDemo
        case .fullscreen: code = ShaderSnippets.fullscreenDemo
        }
        let newShader = ActiveShader(category: category, name: "\(name) \(activeShaders.filter { $0.category == category }.count + 1)", code: code)
        activeShaders.append(newShader)
        activeShaders.sort { s1, s2 in
            let order: [ShaderCategory: Int] = [.vertex: 0, .fragment: 1, .fullscreen: 2]
            return order[s1.category]! < order[s2.category]!
        }
    }

    /// Removes a shader layer with undo support.
    ///
    /// The deleted shader is stored temporarily so it can be restored.
    /// A toast notification appears for 6 seconds with an undo button.
    /// The token-based expiration prevents stale dismissals from hiding
    /// a newer undo toast.
    private func removeShader(_ shader: ActiveShader) {
        guard let index = activeShaders.firstIndex(where: { $0.id == shader.id }) else { return }
        lastDeletedShader = activeShaders[index]
        lastDeletedIndex = index
        if editingShaderID == shader.id { editingShaderID = nil }
        activeShaders.remove(at: index)

        let token = UUID()
        undoToken = token
        withAnimation { showUndoToast = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if undoToken == token {
                withAnimation { showUndoToast = false }
                lastDeletedShader = nil
            }
        }
    }

    /// Restores the most recently deleted shader to its original position.
    private func undoDelete() {
        guard let shader = lastDeletedShader else { return }
        let insertIndex = min(lastDeletedIndex, activeShaders.count)
        activeShaders.insert(shader, at: insertIndex)
        activeShaders.sort { s1, s2 in
            let order: [ShaderCategory: Int] = [.vertex: 0, .fragment: 1, .fullscreen: 2]
            return order[s1.category]! < order[s2.category]!
        }
        lastDeletedShader = nil
        withAnimation { showUndoToast = false }
    }

    // MARK: - AI Agent Actions

    /// Executes a list of Agent actions: adds new layers or modifies existing ones.
    ///
    /// After executing all actions, re-sorts the layer list by category and
    /// opens the shader editor for the first affected layer.
    private func executeAgentActions(_ actions: [AgentAction]) {
        var firstAffectedID: UUID?
        for action in actions {
            guard let category = action.shaderCategory else { continue }
            switch action.type {
            case .addLayer:
                let shader = ActiveShader(category: category, name: action.name, code: action.code)
                activeShaders.append(shader)
                if firstAffectedID == nil { firstAffectedID = shader.id }
            case .modifyLayer:
                if let targetName = action.targetLayerName,
                   let index = activeShaders.firstIndex(where: { $0.name == targetName }) {
                    activeShaders[index].code = action.code
                    if !action.name.isEmpty && action.name != "Untitled" {
                        activeShaders[index].name = action.name
                    }
                    if firstAffectedID == nil { firstAffectedID = activeShaders[index].id }
                }
            }
        }
        activeShaders.sort { s1, s2 in
            let order: [ShaderCategory: Int] = [.vertex: 0, .fragment: 1, .fullscreen: 2]
            return order[s1.category]! < order[s2.category]!
        }
        if let id = firstAffectedID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { editingShaderID = id }
            }
        }
    }

    // MARK: - Tutorial

    /// Enters tutorial mode with the built-in 9-step lesson plan.
    private func startTutorial() {
        resetToNewCanvas()
        canvasName = String(localized: "Metal Shader Tutorial")
        isTutorialMode = true
        tutorialStepIndex = 0
        showingSolution = false
        loadTutorialStep(0)
    }

    /// Exits tutorial mode and clears any AI-generated steps.
    private func exitTutorial() {
        withAnimation {
            isTutorialMode = false
            showingSolution = false
            aiTutorialSteps = nil
        }
    }

    /// Navigates forward or backward in the tutorial step list.
    private func navigateTutorial(delta: Int) {
        let newIndex = tutorialStepIndex + delta
        guard newIndex >= 0, newIndex < currentTutorialSteps.count else { return }
        tutorialStepIndex = newIndex
        showingSolution = false
        loadTutorialStep(newIndex)
    }

    /// Loads a specific tutorial step: replaces the matching shader layer,
    /// opens the editor panel, and scrolls to the new shader.
    private func loadTutorialStep(_ index: Int) {
        let step = currentTutorialSteps[index]

        activeShaders.removeAll { $0.category == step.category }
        editingShaderID = nil

        let shader = ActiveShader(
            category: step.category,
            name: step.title,
            code: step.starterCode
        )
        activeShaders.append(shader)
        activeShaders.sort { s1, s2 in
            let order: [ShaderCategory: Int] = [.vertex: 0, .fragment: 1, .fullscreen: 2]
            return order[s1.category]! < order[s2.category]!
        }

        // Delay editor opening to let SwiftUI finish the layout pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            editingShaderID = shader.id
        }
    }

    /// Toggles between starter code and solution code for the current tutorial step.
    private func applySolution() {
        let step = currentTutorialSteps[tutorialStepIndex]
        if let index = activeShaders.firstIndex(where: { $0.name == step.title }) {
            if showingSolution {
                activeShaders[index].code = step.starterCode
                showingSolution = false
            } else {
                activeShaders[index].code = step.solutionCode
                showingSolution = true
            }
        }
    }

    // MARK: - Canvas Save / Open / New

    /// Resets the workspace to a blank state.
    private func resetToNewCanvas() {
        activeShaders = []
        editingShaderID = nil
        meshType = .sphere
        customFileName = nil
        backgroundImage = nil
        dataFlowConfig = DataFlowConfig()
        paramValues = [:]
        canvasName = String(localized: "Untitled Canvas")
        currentFileURL = nil
        aiTutorialSteps = nil
        isAIChatActive = false
    }

    /// Saves the canvas: to the existing file if previously saved, otherwise prompts Save As.
    private func performSave() {
        if let url = currentFileURL {
            saveCanvas(to: url)
        } else {
            performSaveAs()
        }
    }

    /// Presents a Save panel and saves the canvas to the chosen location.
    private func performSaveAs() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Save Canvas")
        panel.nameFieldStringValue = canvasName + ".shadercanvas"
        panel.allowedContentTypes = [.shaderCanvas]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            saveCanvas(to: url)
        }
    }

    /// Encodes the current workspace as JSON and writes it to disk.
    ///
    /// The CanvasDocument includes the canvas name, mesh type, and all shader layers.
    /// Uses pretty-printed JSON with sorted keys for human readability.
    private func saveCanvas(to url: URL) {
        let doc = CanvasDocument(name: canvasName, meshType: meshType, shaders: activeShaders, dataFlow: dataFlowConfig, paramValues: paramValues)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(doc)
            try data.write(to: url, options: .atomic)
            currentFileURL = url
            print("Canvas saved to \(url.path)")
        } catch {
            print("Failed to save canvas: \(error)")
        }
    }

    /// Presents an Open panel and loads a .shadercanvas file.
    private func performOpen() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open Canvas")
        panel.allowedContentTypes = [.shaderCanvas]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openCanvas(from: url)
        }
    }

    /// Decodes a .shadercanvas file and restores the workspace state.
    private func openCanvas(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let doc = try JSONDecoder().decode(CanvasDocument.self, from: data)
            canvasName = doc.name
            meshType = doc.meshType
            activeShaders = doc.shaders
            dataFlowConfig = doc.dataFlow
            paramValues = doc.paramValues
            currentFileURL = url
            editingShaderID = nil

            if case .custom(let modelURL) = meshType {
                customFileName = modelURL.lastPathComponent
            } else {
                customFileName = nil
            }
            print("Canvas loaded from \(url.path)")
        } catch {
            print("Failed to open canvas: \(error)")
        }
    }
    
    // MARK: - Data Flow Panel
    
    private var dataFlowPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Data Flow")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.bottom, 2)
            
            Text("Vertex fields shared across all mesh shaders")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 4)
            
            Group {
                dataFlowToggle(label: "Normal", icon: "arrow.up.right", binding: $dataFlowConfig.normalEnabled, locked: false)
                dataFlowToggle(label: "UV", icon: "squareshape.split.2x2", binding: $dataFlowConfig.uvEnabled, locked: false)
                dataFlowToggle(label: "Time", icon: "clock", binding: $dataFlowConfig.timeEnabled, locked: false)
            }
            
            Divider().background(Color.white.opacity(0.2))
            
            Text("Extended")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .padding(.top, 2)
            
            Group {
                dataFlowToggle(label: "World Position", icon: "globe", binding: $dataFlowConfig.worldPositionEnabled, locked: false)
                dataFlowToggle(label: "World Normal", icon: "arrow.up.forward.circle", binding: $dataFlowConfig.worldNormalEnabled, locked: !dataFlowConfig.normalEnabled)
                dataFlowToggle(label: "View Direction", icon: "eye", binding: $dataFlowConfig.viewDirectionEnabled, locked: !dataFlowConfig.worldPositionEnabled)
            }
            
            Divider().background(Color.white.opacity(0.2))
            
            dataFlowPreview
        }
        .frame(width: 220)
        .padding(12)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .transition(.move(edge: .leading).combined(with: .opacity))
        .onChange(of: dataFlowConfig) { _ in
            dataFlowConfig.resolveDependencies()
        }
    }
    
    /// Parsed @param declarations from the currently editing shader only.
    private var allParsedParams: [ShaderParam] {
        guard let editingID = editingShaderID,
              let shader = activeShaders.first(where: { $0.id == editingID }) else { return [] }
        return ShaderSnippets.parseParams(from: shader.code)
    }
    
    private func dataFlowToggle(label: String, icon: String, binding: Binding<Bool>, locked: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(locked ? .gray : .blue)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundColor(locked ? .gray : .white)
            Spacer()
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(locked)
        }
        .padding(.vertical, 1)
    }
    
    private var dataFlowPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Generated Structs")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            
            ScrollView {
                Text(ShaderSnippets.generateStructPreview(config: dataFlowConfig))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(6)
            .background(Color.black.opacity(0.5))
            .cornerRadius(6)
        }
    }
    
    // MARK: - Parameters Panel (Independent Section)
    
    private var parametersPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Parameters")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                if editingShaderID != nil {
                    Menu {
                        Button("Float Slider") { addParamToEditingShader(type: .float, withRange: true) }
                        Button("Float Input") { addParamToEditingShader(type: .float, withRange: false) }
                        Divider()
                        Button("Color") { addParamToEditingShader(type: .color, withRange: false) }
                        Divider()
                        Button("Float2") { addParamToEditingShader(type: .float2, withRange: false) }
                        Button("Float3") { addParamToEditingShader(type: .float3, withRange: false) }
                        Button("Float4") { addParamToEditingShader(type: .float4, withRange: false) }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                    .help("Add parameter to current shader")
                }
            }
            
            if allParsedParams.isEmpty {
                Text(editingShaderID != nil
                     ? "Use + to add parameters, or write\n// @param _name type default ..."
                     : "No parameters declared")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.vertical, 4)
            } else {
                ForEach(allParsedParams, id: \.name) { param in
                    paramControl(for: param)
                }
            }
        }
        .frame(width: 220)
        .padding(12)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .transition(.move(edge: .leading).combined(with: .opacity))
    }
    
    /// Generates a unique parameter name that doesn't conflict with existing ones.
    private func nextParamName(type: ParamType) -> String {
        let existingNames = Set(allParsedParams.map(\.name))
        let base: String
        switch type {
        case .float: base = "value"
        case .float2: base = "offset"
        case .float3: base = "direction"
        case .float4: base = "vector"
        case .color: base = "tint"
        }
        let candidate = "_\(base)"
        if !existingNames.contains(candidate) { return candidate }
        for i in 2...99 {
            let c = "_\(base)\(i)"
            if !existingNames.contains(c) { return c }
        }
        return "_\(base)_\(UUID().uuidString.prefix(4))"
    }
    
    /// Injects a `// @param` directive at the top of the currently editing shader's code.
    private func addParamToEditingShader(type: ParamType, withRange: Bool) {
        guard let editingID = editingShaderID,
              let index = activeShaders.firstIndex(where: { $0.id == editingID }) else { return }
        
        let name = nextParamName(type: type)
        var directive: String
        
        switch type {
        case .float:
            directive = withRange
                ? "// @param \(name) float 0.5 0.0 1.0"
                : "// @param \(name) float 0.0"
        case .float2:
            directive = "// @param \(name) float2 0.0 0.0"
        case .float3:
            directive = "// @param \(name) float3 0.0 0.0 0.0"
        case .float4:
            directive = "// @param \(name) float4 0.0 0.0 0.0 0.0"
        case .color:
            directive = "// @param \(name) color 1.0 1.0 1.0"
        }
        
        activeShaders[index].code = directive + "\n" + activeShaders[index].code
    }
    
    /// Renames a parameter across all shader code and transfers its stored value.
    ///
    /// Updates:
    /// 1. The `// @param` directive line in every shader
    /// 2. All word-boundary references of the old name in shader code
    /// 3. The paramValues dictionary key
    private func renameParam(from oldName: String, to rawNewName: String) {
        let displayName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }
        guard displayName.range(of: #"^[a-zA-Z]\w*$"#, options: .regularExpression) != nil else { return }
        
        let newInternalName = "_\(displayName)"
        guard newInternalName != oldName else { return }
        guard !allParsedParams.contains(where: { $0.name == newInternalName }) else { return }
        
        let escapedOld = NSRegularExpression.escapedPattern(for: oldName)
        
        // Step 1: Replace the @param directive line (name only, not type keyword)
        let paramLineRegex = try? NSRegularExpression(pattern: "(//\\s*@param\\s+)\(escapedOld)(\\s+)")
        
        // Step 2: Replace code references (word-boundary match on internal name)
        let codeRefRegex = try? NSRegularExpression(pattern: "\\b\(escapedOld)\\b")
        
        for i in activeShaders.indices {
            var code = activeShaders[i].code
            
            // First: rename in @param directive (targeted, only the name field)
            if let regex = paramLineRegex {
                code = regex.stringByReplacingMatches(
                    in: code,
                    range: NSRange(code.startIndex..., in: code),
                    withTemplate: "$1\(newInternalName)$2"
                )
            }
            
            // Second: rename code references (safe because _ prefix won't match MSL keywords)
            if let regex = codeRefRegex {
                code = regex.stringByReplacingMatches(
                    in: code,
                    range: NSRange(code.startIndex..., in: code),
                    withTemplate: newInternalName
                )
            }
            
            activeShaders[i].code = code
        }
        
        if let vals = paramValues.removeValue(forKey: oldName) {
            paramValues[newInternalName] = vals
        }
    }
    
    @ViewBuilder
    private func paramControl(for param: ShaderParam) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if renamingParamName == param.name {
                HStack(spacing: 4) {
                    TextField("", text: $editedParamName, onCommit: {
                        renameParam(from: param.name, to: editedParamName)
                        renamingParamName = nil
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(3)
                    
                    Button(action: {
                        renameParam(from: param.name, to: editedParamName)
                        renamingParamName = nil
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green.opacity(0.8))
                            .font(.system(size: 11))
                    }.buttonStyle(.plain)
                    
                    Button(action: { renamingParamName = nil }) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.white.opacity(0.4))
                            .font(.system(size: 11))
                    }.buttonStyle(.plain)
                }
            } else {
                Text(paramDisplayName(param.name))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .onTapGesture(count: 2) {
                        editedParamName = paramDisplayName(param.name)
                        renamingParamName = param.name
                    }
                    .help("Double-click to rename")
            }
            
            switch param.type {
            case .float:
                if let minVal = param.minValue, let maxVal = param.maxValue {
                    HStack(spacing: 4) {
                        Slider(
                            value: paramBinding(name: param.name, index: 0, defaultValue: param.defaultValue),
                            in: minVal...maxVal
                        ) { editing in
                            if !editing { syncParamToCode(name: param.name) }
                        }
                        .controlSize(.mini)
                        Text(String(format: "%.2f", currentParamValue(param.name, 0, param.defaultValue)))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 36, alignment: .trailing)
                    }
                } else {
                    floatInputField(name: param.name, index: 0, defaultValue: param.defaultValue)
                }
                
            case .color:
                colorControl(name: param.name, defaultValue: param.defaultValue)
                
            case .float2:
                HStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { i in
                        floatInputField(name: param.name, index: i, defaultValue: param.defaultValue)
                    }
                }
                
            case .float3:
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        floatInputField(name: param.name, index: i, defaultValue: param.defaultValue)
                    }
                }
                
            case .float4:
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        floatInputField(name: param.name, index: i, defaultValue: param.defaultValue)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func floatInputField(name: String, index: Int, defaultValue: [Float]) -> some View {
        let labels = ["X", "Y", "Z", "W"]
        return HStack(spacing: 2) {
            if defaultValue.count > 1 {
                Text(labels[min(index, 3)])
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 10)
            }
            TextField("", value: paramBinding(name: name, index: index, defaultValue: defaultValue), format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1))
                .cornerRadius(3)
        }
    }
    
    private func colorControl(name: String, defaultValue: [Float]) -> some View {
        let colorBinding = Binding<Color>(
            get: {
                Color(
                    red: Double(currentParamValue(name, 0, defaultValue)),
                    green: Double(currentParamValue(name, 1, defaultValue)),
                    blue: Double(currentParamValue(name, 2, defaultValue))
                )
            },
            set: { newColor in
                guard let rgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                let vals: [Float] = [Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent)]
                paramValues[name] = vals
                syncParamToCode(name: name)
            }
        )
        return ColorPicker("", selection: colorBinding, supportsOpacity: false)
            .labelsHidden()
    }
    
    // MARK: - Parameter Value Helpers
    
    /// Display name: strips leading `_` prefix for UI presentation.
    private func paramDisplayName(_ internalName: String) -> String {
        internalName.hasPrefix("_") ? String(internalName.dropFirst()) : internalName
    }
    
    private func currentParamValue(_ name: String, _ index: Int, _ defaultValue: [Float]) -> Float {
        let vals = paramValues[name] ?? defaultValue
        return index < vals.count ? vals[index] : (index < defaultValue.count ? defaultValue[index] : 0)
    }
    
    private func paramBinding(name: String, index: Int, defaultValue: [Float]) -> Binding<Float> {
        Binding<Float>(
            get: { currentParamValue(name, index, defaultValue) },
            set: { newVal in
                var vals = paramValues[name] ?? defaultValue
                while vals.count <= index { vals.append(0) }
                vals[index] = newVal
                paramValues[name] = vals
            }
        )
    }
    
    /// Syncs the current runtime param value back into the `// @param` line in shader code.
    /// Called only on explicit commit actions (slider release, color pick) to avoid
    /// constant recompilation during continuous dragging.
    private func syncParamToCode(name: String) {
        guard let vals = paramValues[name],
              let param = allParsedParams.first(where: { $0.name == name }) else { return }
        
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "//\\s*@param\\s+\(escapedName)\\s+.*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        var valueStrs: [String]
        if param.type == .float, let minV = param.minValue, let maxV = param.maxValue {
            valueStrs = [formatParamFloat(vals.first ?? 0), formatParamFloat(minV), formatParamFloat(maxV)]
        } else {
            valueStrs = vals.prefix(param.type.componentCount).map { formatParamFloat($0) }
        }
        
        let newDirective = "// @param \(name) \(param.type.rawValue) \(valueStrs.joined(separator: " "))"
        
        for i in activeShaders.indices {
            let code = activeShaders[i].code
            if let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) {
                activeShaders[i].code = (code as NSString).replacingCharacters(in: match.range, with: newDirective)
                return
            }
        }
    }
    
    private func formatParamFloat(_ v: Float) -> String {
        v == Float(Int(v)) ? String(format: "%.1f", v) : String(format: "%.3f", v)
    }
}

// MARK: - Shader Editor Panel

/// A sliding panel that provides shader code editing with syntax highlighting,
/// snippet insertion, and preset selection.
///
/// The panel includes:
/// - A header with the shader name (editable) and reset button
/// - A horizontal snippet bar for quick MSL function insertion
/// - Preset buttons (fragment shading models or post-processing presets)
/// - A full CodeEditor with MSL syntax highlighting
struct ShaderEditorView: View {
    @Binding var shader: ActiveShader
    var dataFlowConfig: DataFlowConfig
    var onClose: () -> Void
    @State private var isRenaming = false
    @State private var editedName = ""

    /// Common MSL function snippets for quick insertion.
    let snippets = ["mix()", "smoothstep()", "normalize()", "dot()", "cross()", "length()", "distance()", "reflect()", "max()", "min()", "clamp()", "sin()", "cos()", "sample()"]

    var body: some View {
        VStack(spacing: 0) {
            // Header: shader name + close button.
            HStack {
                if isRenaming {
                    TextField("", text: $editedName, onCommit: {
                        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { shader.name = trimmed }
                        isRenaming = false
                    })
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                    .frame(maxWidth: 250)

                    Button(action: {
                        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { shader.name = trimmed }
                        isRenaming = false
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green.opacity(0.8))
                    }.buttonStyle(.plain)
                } else {
                    Text(verbatim: shader.name)
                        .font(.headline).foregroundColor(.white)
                    Button(action: {
                        editedName = shader.name
                        isRenaming = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.caption).foregroundColor(.white.opacity(0.5))
                    }.buttonStyle(.plain)
                }

                Spacer()
                Button(action: { resetShader() }) {
                    Image(systemName: "arrow.counterclockwise").foregroundColor(.orange)
                }.buttonStyle(.plain).help("Reset to Blank Template").padding(.trailing, 12)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.white.opacity(0.7))
                }.buttonStyle(.plain)
            }
            .padding().background(Color.black.opacity(0.7))

            // Snippet insertion bar.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(snippets, id: \.self) { snippet in
                        Button(action: {
                            NotificationCenter.default.post(name: .insertSnippet, object: snippet)
                        }) {
                            Text(snippet)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.white.opacity(0.15)).cornerRadius(4)
                                .foregroundColor(.white)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }.background(Color.black.opacity(0.6))

            // Fragment shader presets (shading models).
            if shader.category == .fragment {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        Text("Presets")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))

                        ForEach(ShaderSnippets.shadingModelNames, id: \.self) { name in
                            Button(action: { shader.code = ShaderSnippets.shadingModel(named: name) ?? shader.code }) {
                                Text(name)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.3)).cornerRadius(4)
                                    .foregroundColor(.white)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }.background(Color.black.opacity(0.55))
            }

            // Post-processing presets.
            if shader.category == .fullscreen {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        Text("PP Presets")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))

                        ForEach(ShaderSnippets.ppPresetNames, id: \.self) { name in
                            Button(action: { shader.code = ShaderSnippets.ppPreset(named: name) ?? shader.code }) {
                                Text(name)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.3)).cornerRadius(4)
                                    .foregroundColor(.white)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }.background(Color.black.opacity(0.55))
            }

            // Code editor with MSL syntax highlighting.
            CodeEditor(text: $shader.code)
        }
    }

    /// Resets the shader code to a blank educational template for its category.
    func resetShader() {
        switch shader.category {
        case .vertex: shader.code = ShaderSnippets.generateVertexTemplate(config: dataFlowConfig)
        case .fragment: shader.code = ShaderSnippets.fragmentTemplate
        case .fullscreen: shader.code = ShaderSnippets.fullscreenTemplate
        }
    }
}

/// Notification name for snippet insertion from the snippet bar into the code editor.
extension NSNotification.Name {
    static let insertSnippet = NSNotification.Name("insertSnippet")
    static let shaderCompilationResult = NSNotification.Name("shaderCompilationResult")
}

// MARK: - Code Editor (NSViewRepresentable)

/// A Metal Shading Language code editor built on NSTextView.
///
/// This is another NSViewRepresentable bridge, similar to MetalView but for text editing.
/// It provides:
/// - Monospaced font with dark theme
/// - MSL syntax highlighting (keywords, types, functions, attributes, numbers, preprocessor, comments)
/// - Auto-indent on newline (preserves indentation level, adds indent after '{')
/// - Tab key inserts 4 spaces instead of a tab character
/// - Snippet insertion via NotificationCenter
///
/// The syntax highlighting is applied via regex-based rules that color-code
/// different MSL language elements. Highlighting is reapplied on every text change.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        // Disable macOS text "smart" features that interfere with code editing.
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true

        // Dark theme styling.
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        textView.textColor = NSColor(white: 0.9, alpha: 1.0)
        textView.insertionPointColor = NSColor.white
        textView.selectedTextAttributes = [.backgroundColor: NSColor(white: 0.3, alpha: 1.0)]
        textView.textContainerInset = NSSize(width: 4, height: 8)

        context.coordinator.textView = textView
        textView.delegate = context.coordinator

        textView.string = text
        context.coordinator.applyHighlighting(to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only update if the text actually changed (avoids cursor position reset).
        // The isUpdating flag prevents infinite loops between SwiftUI and NSTextView.
        if textView.string != text && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
            context.coordinator.isUpdating = false
        }
    }

    /// Coordinator that acts as NSTextViewDelegate and handles snippet insertion.
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        var isUpdating = false
        weak var textView: NSTextView?

        init(_ parent: CodeEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(handleInsertSnippet(_:)), name: .insertSnippet, object: nil)
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        /// Inserts a code snippet at the current cursor position.
        @objc func handleInsertSnippet(_ notification: Notification) {
            guard let tv = textView, let snippet = notification.object as? String else { return }
            tv.insertText(snippet, replacementRange: tv.selectedRange())
        }

        /// Called when the user types in the editor. Syncs text back to SwiftUI
        /// and re-applies syntax highlighting.
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            guard !isUpdating else { return }
            isUpdating = true
            parent.text = tv.string
            applyHighlighting(to: tv)
            isUpdating = false
        }

        /// Intercepts Tab and Return key presses for custom behavior.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Tab → insert 4 spaces (soft tab).
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("    ", replacementRange: textView.selectedRange())
                return true
            }
            // Return → auto-indent (preserve current line's indentation,
            // add extra indent after opening brace '{').
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let s = textView.string as NSString
                let sel = textView.selectedRange()
                let lineRange = s.lineRange(for: NSRange(location: sel.location, length: 0))
                let line = s.substring(with: lineRange)
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
                var ins = "\n" + indent
                if line.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("{") { ins += "    " }
                textView.insertText(ins, replacementRange: sel)
                return true
            }
            return false
        }

        // MARK: - Syntax Highlighting

        /// Regex-based syntax highlighting rules for Metal Shading Language.
        /// Rules are applied in order; later rules override earlier ones for overlapping matches.
        ///
        /// Color scheme:
        /// - Pink: keywords (vertex, fragment, kernel, return, struct, etc.)
        /// - Cyan: types (float, float4, texture2d, void, etc.)
        /// - Yellow: built-in functions (sin, cos, dot, normalize, etc.)
        /// - Orange: attributes ([[position]], [[stage_in]], etc.)
        /// - Green: numeric literals (1.0, 42, etc.)
        /// - Orange: preprocessor directives (#include, #define, etc.)
        /// - Gray-green: comments (// ...)
        private let highlightRules: [(String, NSColor, NSRegularExpression.Options)] = [
            ("\\b(include|using|namespace|struct|vertex|fragment|kernel|constant|device|thread|threadgroup|return|constexpr|sampler|address|filter)\\b", NSColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 1.0), []),
            ("\\b(float|float2|float3|float4|float4x4|float3x3|half|half2|half3|half4|int|uint|uint2|uint3|uint4|texture2d|void|bool)\\b", NSColor(red: 0.3, green: 0.7, blue: 0.8, alpha: 1.0), []),
            ("\\b(sin|cos|tan|max|min|clamp|dot|cross|normalize|length|distance|reflect|refract|mix|smoothstep|step|sample)\\b", NSColor(red: 0.8, green: 0.8, blue: 0.5, alpha: 1.0), []),
            ("\\[\\[[^\\]]+\\]\\]", NSColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1.0), []),
            ("\\b\\d+(\\.\\d+)?\\b", NSColor(red: 0.6, green: 0.8, blue: 0.6, alpha: 1.0), []),
            ("^\\s*#.*", NSColor(red: 0.8, green: 0.5, blue: 0.3, alpha: 1.0), .anchorsMatchLines),
            ("//.*", NSColor(red: 0.5, green: 0.6, blue: 0.5, alpha: 1.0), []),
        ]

        /// Applies regex-based syntax highlighting to the entire text.
        /// Resets all text to the default color, then applies each rule's color
        /// to matching ranges.
        func applyHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            let content = storage.string
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor(white: 0.9, alpha: 1.0), range: range)
            storage.addAttribute(.font, value: font, range: range)

            for (pattern, color, opts) in highlightRules {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
                for match in regex.matches(in: content, range: range) {
                    storage.addAttribute(.foregroundColor, value: color, range: match.range)
                }
            }
            storage.endEditing()
        }
    }
}

// MARK: - Tutorial Panel

/// An expandable/collapsible panel that displays tutorial step instructions,
/// navigation controls, hint/solution toggles, and progress indicators.
struct TutorialPanel: View {
    let step: TutorialStep
    let currentIndex: Int
    let totalSteps: Int
    var showingSolution: Binding<Bool>
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onShowSolution: () -> Void
    var onExit: () -> Void

    @State private var isExpanded = true
    @State private var showHint = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar with step counter, title, expand/collapse, and exit.
            HStack {
                Image(systemName: "graduationcap.fill")
                    .foregroundColor(.yellow)
                Text("\(currentIndex + 1) / \(totalSteps)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Text(step.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .foregroundColor(.white.opacity(0.6))
                }.buttonStyle(.plain)

                Button(action: onExit) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                }.buttonStyle(.plain).help("Exit Tutorial")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.black.opacity(0.7))

            // Expandable content: instructions, goal, hint, navigation buttons.
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(step.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.yellow.opacity(0.9))

                    Text(step.instructions)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.green)
                        Text(step.goal)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green.opacity(0.9))
                    }

                    if showHint {
                        HStack(alignment: .top) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text(step.hint)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.yellow.opacity(0.8))
                        }
                        .padding(8)
                        .background(Color.yellow.opacity(0.1))
                        .cornerRadius(6)
                    }

                    HStack(spacing: 12) {
                        Button(action: { withAnimation { showHint.toggle() } }) {
                            HStack(spacing: 4) {
                                Image(systemName: showHint ? "lightbulb.slash" : "lightbulb")
                                Text(showHint ? "Hide Hint" : "Show Hint")
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(5)
                            .foregroundColor(.yellow)
                        }.buttonStyle(.plain)

                        Button(action: onShowSolution) {
                            HStack(spacing: 4) {
                                Image(systemName: showingSolution.wrappedValue ? "eye.slash" : "eye")
                                Text(showingSolution.wrappedValue ? "Hide Solution" : "Show Solution")
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(5)
                            .foregroundColor(.blue)
                        }.buttonStyle(.plain)

                        Spacer()

                        Button(action: onPrevious) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Prev")
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(5)
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(currentIndex == 0)
                        .opacity(currentIndex == 0 ? 0.3 : 1)

                        Button(action: onNext) {
                            HStack(spacing: 4) {
                                Text(currentIndex == totalSteps - 1 ? "Done" : "Next")
                                if currentIndex < totalSteps - 1 {
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Color.green.opacity(0.7))
                            .cornerRadius(5)
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(currentIndex >= totalSteps - 1)
                        .opacity(currentIndex >= totalSteps - 1 ? 0.3 : 1)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.black.opacity(0.65))
            }
        }
        .cornerRadius(12)
        .padding(.horizontal, 20)
        .padding(.bottom, 80)
        .onChange(of: currentIndex) {
            showHint = false
        }
    }
}

#Preview {
    ContentView()
}
