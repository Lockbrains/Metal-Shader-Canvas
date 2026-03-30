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
import simd

// MARK: - ContentView

/// The root view of the application. Manages all UI panels and app state.
struct ContentView: View {

    // MARK: - Navigation (Hub ↔ Editor)

    var appState: AppState
    var recentManager: RecentProjectManager

    // MARK: - Shader State

    /// All active shader layers, ordered by category (vertex → fragment → fullscreen).
    @State private var activeShaders: [ActiveShader] = []

    /// The ID of the shader currently being edited. nil = editor panel closed.
    @State private var editingShaderID: UUID? = nil

    // MARK: - Canvas Mode

    @State private var canvasMode: CanvasMode = .threeDimensional

    /// The active 2D shape type. Kept for backward compat with legacy single-shape files.
    @State private var shape2DType: Shape2DType = .roundedRectangle

    // MARK: - 2D Scene State

    @State private var objects2D: [Object2D] = []
    @State private var sharedVertexCode2D: String = ShaderSnippets.distortion2DTemplate
    @State private var sharedFragmentCode2D: String = ShaderSnippets.fragment2DDemo
    @State private var selectedObjectID: UUID? = nil
    @State private var canvasZoom: Float = 1.0
    @State private var canvasPan: simd_float2 = .zero

    /// Editing mode for 2D shader editor (which shared / per-object shader is open).
    @State private var editing2DShaderTarget: Edit2DShaderTarget? = nil

    enum Edit2DShaderTarget: Equatable {
        case sharedVertex
        case sharedFragment
        case objectVertex(UUID)
        case objectFragment(UUID)
    }

    // MARK: - Mesh & Background State

    /// The 3D mesh to render. Defaults to .sphere.
    @State private var meshType: MeshType = .sphere

    /// Display name for a custom-uploaded mesh file (for the tooltip).
    @State private var customFileName: String? = nil

    /// Optional background image rendered behind the 3D mesh (or 2D canvas).
    @State private var backgroundImage: NSImage? = nil

    // MARK: - File Importer State

    @State private var fileImporterPresented = false
    @State private var fileImporterMode: FileImporterMode = .mesh

    enum FileImporterMode {
        case mesh, background
    }

    // MARK: - UI State

    @State private var isSidebarVisible = true

    // MARK: - Panel Collapse State

    @State private var isShadersCollapsed = false
    @State private var isObjectsCollapsed = false
    @State private var isPostProcessingCollapsed = false
    @State private var isDataFlowCollapsed = false
    @State private var isParametersCollapsed = false
    @State private var isLayersCollapsed = false

    private let panelWidth: CGFloat = 240

    /// Y-axis rotation angle in degrees, controlled by slider in the toolbar.
    @State private var rotationAngle: Double = 0

    // MARK: - Canvas File State

    @State private var canvasName: String = String(localized: "Untitled Canvas")
    @State private var currentFileURL: URL? = nil

    @State private var showingNewCanvasConfirm = false
    @State private var showingBackToHubConfirm = false
    @State private var hasUnsavedChanges = false
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

    // MARK: - Shape Lock State

    @State private var showingShapeLockAlert = false
    @State private var pendingShapeLockObjectName = ""
    @State private var pendingShapeLockExplanation = ""
    /// Object names whose shape-lock was approved by the user.  Consumed when
    /// the AI preview clone is created — the lock is applied to the clone, not
    /// the original.
    @State private var approvedShapeLocks: Set<String> = []

    // MARK: - Data Flow State
    
    /// Configurable vertex data fields shared across all mesh shaders (3D).
    @State private var dataFlowConfig = DataFlowConfig()
    /// Configurable vertex data fields for 2D canvas shaders.
    @State private var dataFlow2DConfig = DataFlow2DConfig()
    
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
        canvasMainLayout
            .modifier(CanvasLifecycleModifier(
                canvasMode: appState.canvasMode,
                openFileURL: appState.openFileURL,
                onInit: { mode, url in
                    canvasMode = mode
                    if let url { openCanvas(from: url) }
                },
                onNewCanvas: { showingNewCanvasConfirm = true },
                onSave: { performSave() },
                onSaveAs: { performSaveAs() },
                onOpen: { performOpen() },
                onTutorial: { startTutorial() },
                onSettings: { showingAISettings = true },
                onChat: { withAnimation(.easeInOut(duration: 0.3)) { isAIChatActive.toggle() } },
                onBackToHub: { requestNavigateBackToHub() },
                onCompilationResult: { error in
                    withAnimation(.easeInOut(duration: 0.2)) { compilationError = error }
                },
                onObjectSelected: { id in selectedObjectID = id },
                onObjectMoved: { id, x, y in
                    if let idx = objects2D.firstIndex(where: { $0.id == id }) {
                        objects2D[idx].posX = x; objects2D[idx].posY = y
                    }
                },
                onZoomChanged: { z in canvasZoom = z },
                onPanChanged: { p in canvasPan = p }
            ))
            .onChange(of: activeShaders) { hasUnsavedChanges = true }
            .onChange(of: objects2D) { hasUnsavedChanges = true }
            .onChange(of: paramValues) { hasUnsavedChanges = true }
            .onChange(of: canvasName) { hasUnsavedChanges = true }
            .onChange(of: dataFlowConfig) { hasUnsavedChanges = true }
            .onChange(of: dataFlow2DConfig) { hasUnsavedChanges = true }
            .onChange(of: sharedVertexCode2D) { hasUnsavedChanges = true }
            .onChange(of: sharedFragmentCode2D) { hasUnsavedChanges = true }
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
    }

    /// Alerts and sheets separated from body to reduce type-checker pressure.
    @ViewBuilder
    private var canvasAlerts: some View { EmptyView() }

    private var canvasMainLayout: some View {
        canvasMainZStack
            .frame(minWidth: 800, minHeight: 600)
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
            .alert(String(localized: "Lock Shape"), isPresented: $showingShapeLockAlert) {
                Button(String(localized: "Lock"), role: nil) {
                    if canvasMode.is2D {
                        approvedShapeLocks.insert(pendingShapeLockObjectName)
                    } else if let idx = objects2D.firstIndex(where: { $0.name == pendingShapeLockObjectName }) {
                        objects2D[idx].shapeLocked = true
                    }
                    NotificationCenter.default.post(name: .shapeLockResolved, object: true)
                }
                Button(String(localized: "Deny"), role: .cancel) {
                    NotificationCenter.default.post(name: .shapeLockResolved, object: false)
                }
            } message: {
                if let obj = objects2D.first(where: { $0.name == pendingShapeLockObjectName }) {
                    Text("AI requests SDF access for \"\(pendingShapeLockObjectName)\" (\(obj.shapeType.rawValue)). Locking the shape enables edge-aware effects but prevents shape changes.")
                } else {
                    Text(pendingShapeLockExplanation)
                }
            }
            .sheet(isPresented: $showingAISettings) {
                AISettingsView(settings: aiSettings)
            }
    }

    private var canvasMainZStack: some View {
        ZStack {
            // Layer 0: Metal rendering viewport (fills the entire window).
            MetalView(activeShaders: activeShaders, meshType: meshType, backgroundImage: backgroundImage, dataFlowConfig: dataFlowConfig, dataFlow2DConfig: dataFlow2DConfig, paramValues: paramValues, rotationAngle: Float(rotationAngle), canvasMode: canvasMode, objects2D: objects2D, sharedVertexCode2D: sharedVertexCode2D, sharedFragmentCode2D: sharedFragmentCode2D, canvasZoom: canvasZoom, canvasPan: canvasPan, shape2DType: shape2DType)
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
                            if canvasMode.is2D {
                                sidebar2DContent
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    collapsibleHeader("Layers", isCollapsed: $isLayersCollapsed)

                                    if !isLayersCollapsed {
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
                                }
                                .frame(width: panelWidth)
                                .padding(12)
                                .glassEffect(.regular.tint(Color(white: 0.15)), in: .rect(cornerRadius: 12))
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                            
                            if canvasMode.is3D {
                                dataFlowPanel
                            } else {
                                dataFlow2DPanel
                            }
                            parametersPanel
                        }
                    }
                    .padding()

                    Spacer()

                    VStack {
                        if !isAIChatActive {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) { isAIChatActive.toggle() }
                            }) {
                                Image(systemName: "sparkles")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .help("AI Chat (⌘L)")
                            .padding()
                            .transition(.opacity)
                        }
                        Spacer()
                    }
                }

                Spacer()

                // Bottom toolbar: shader type buttons (left) + mesh/background controls (right).
                HStack(alignment: .bottom) {
                    // Shader layer creation buttons (mode-aware).
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.trailing, 4)

                        if canvasMode.is3D {
                            Button(action: { addShader(category: .vertex, name: String(localized: "Vertex Layer")) }) {
                                Text(verbatim: "VS").fontWeight(.bold).padding(.horizontal, 12).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain).foregroundColor(.white).glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: 8)).help("Vertex Shader")

                            Button(action: { addShader(category: .fragment, name: String(localized: "Fragment Layer")) }) {
                                Text(verbatim: "FS").fontWeight(.bold).padding(.horizontal, 12).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain).foregroundColor(.white).glassEffect(.regular.tint(.purple).interactive(), in: .rect(cornerRadius: 8)).help("Fragment Shader")
                        }

                        Button(action: { addShader(category: .fullscreen, name: String(localized: "Fullscreen Layer")) }) {
                            Text(verbatim: "PP").fontWeight(.bold).padding(.horizontal, 12).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain).foregroundColor(.white).glassEffect(.regular.tint(.orange).interactive(), in: .rect(cornerRadius: 8)).help("Post Processing")
                    }
                    .padding(10).glassEffect(.regular.tint(Color(white: 0.15)), in: .rect(cornerRadius: 12)).padding()

                    Spacer()

                    // Right-side controls (mode-aware).
                    HStack(spacing: 12) {
                        // Background image (available in both modes).
                        Button(action: { fileImporterMode = .background; fileImporterPresented = true }) {
                            Image(systemName: "photo.fill").font(.title2)
                                .foregroundColor(backgroundImage != nil ? .green : .white)
                        }.buttonStyle(.plain).help("Background Image")

                        if backgroundImage != nil {
                            Button(action: { backgroundImage = nil }) {
                                Image(systemName: "xmark.circle").font(.title3)
                                    .foregroundColor(.red.opacity(0.8))
                            }.buttonStyle(.plain).help("Remove Background")
                        }

                        if canvasMode.is2D {
                            Divider().frame(height: 24).background(Color.white.opacity(0.3))

                            Button(action: { addObject2D() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.square.fill").font(.title2)
                                    Text("Object").font(.caption)
                                }
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Add Object"))

                            Button(action: { canvasZoom = 1.0; canvasPan = .zero }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.title2)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Reset Zoom/Pan"))
                        }

                        if canvasMode.is3D {
                            // 3D mesh selection controls.
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

                            Divider().frame(height: 24).background(Color.white.opacity(0.3))

                            Image(systemName: "rotate.3d")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))

                            Slider(value: $rotationAngle, in: 0...360)
                                .frame(width: 100)

                            Text(String(format: "%.0f°", rotationAngle))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 32, alignment: .trailing)

                            Button(action: { rotationAngle = 0 }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption2)
                                    .foregroundColor(rotationAngle == 0 ? .white.opacity(0.3) : .orange)
                            }
                            .buttonStyle(.plain)
                            .disabled(rotationAngle == 0)
                            .help(String(localized: "Reset to 0°"))
                        }

                        Divider().frame(height: 24).background(Color.white.opacity(0.3))

                        // Back to Hub button.
                        Button(action: { requestNavigateBackToHub() }) {
                            Image(systemName: "house.fill").font(.title2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Back to Hub")
                    }
                    .padding(10).glassEffect(.regular.tint(Color(white: 0.15)), in: .rect(cornerRadius: 12)).padding()
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
                            .glassEffect(.regular.tint(.red), in: .rect(cornerRadius: 8))
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

            // 2D Shader editor panel (slides in from the right).
            if let target = editing2DShaderTarget {
                HStack(spacing: 0) {
                    Spacer()
                    ZStack(alignment: .bottom) {
                        shader2DEditorPanel(target: target)

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
                            .glassEffect(.regular.tint(.red), in: .rect(cornerRadius: 8))
                            .padding(8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(width: 500)
                    .transition(.move(edge: .trailing))
                }
                .zIndex(1.5)
            }

            // AI Chat panel (slides in from the right).
            if isAIChatActive {
                HStack(spacing: 0) {
                    Spacer()
                    AIChatView(
                        messages: $chatMessages,
                        isActive: $isAIChatActive,
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
                        rotationAngle: Float(rotationAngle),
                        selectedObjectID: selectedObjectID,
                        onGenerateTutorial: { steps in loadAITutorial(steps) },
                        onAgentActions: { actions in executeAgentActions(actions) }
                    )
                    .frame(width: 420)
                    .padding(.top, 48)
                    .padding(.bottom, 64)
                    .padding(.trailing, 16)
                    .transition(.move(edge: .trailing))
                }
                .zIndex(2)

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
                    .glassEffect(.regular.tint(Color(white: 0.15)), in: .rect(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .padding(.bottom, 80)
                }
                .zIndex(4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
        if canvasMode.is2D {
            switch category {
            case .vertex: code = ShaderSnippets.generateVertexDemo(config: dataFlowConfig)
            case .fragment: code = ShaderSnippets.fragment2DDemo
            case .fullscreen: code = ShaderSnippets.fullscreenDemo
            }
        } else {
            switch category {
            case .vertex: code = ShaderSnippets.generateVertexDemo(config: dataFlowConfig)
            case .fragment: code = ShaderSnippets.fragmentDemo
            case .fullscreen: code = ShaderSnippets.fullscreenDemo
            }
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

    /// Executes a list of Agent actions: adds/modifies layers, 2D objects, or 2D shaders.
    ///
    /// After executing all actions, re-sorts the layer list by category and
    /// opens the shader editor for the first affected layer (3D) or selects
    /// the first affected object (2D).
    ///
    /// `requestShapeLock` actions trigger a confirmation alert rather than
    /// executing immediately.
    private func executeAgentActions(_ actions: [AgentAction]) {
        let result = CanvasActions.executeAgentActions(
            actions,
            activeShaders: &activeShaders,
            objects2D: &objects2D,
            sharedVertexCode2D: &sharedVertexCode2D,
            sharedFragmentCode2D: &sharedFragmentCode2D,
            usePreviewClone: canvasMode.is2D,
            approvedShapeLocks: &approvedShapeLocks
        )

        if let req = result.shapeLockRequests.first {
            pendingShapeLockObjectName = req.objectName
            pendingShapeLockExplanation = req.explanation
            showingShapeLockAlert = true
        }

        if let id = result.firstShaderID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { editingShaderID = id }
            }
        } else if let id = result.firstObjectID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { selectedObjectID = id }
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
        shape2DType = .roundedRectangle
        customFileName = nil
        backgroundImage = nil
        dataFlowConfig = DataFlowConfig()
        dataFlow2DConfig = DataFlow2DConfig()
        paramValues = [:]
        rotationAngle = 0
        canvasName = String(localized: "Untitled Canvas")
        currentFileURL = nil
        aiTutorialSteps = nil
        isAIChatActive = false
        objects2D = []
        sharedVertexCode2D = ShaderSnippets.distortion2DTemplate
        sharedFragmentCode2D = ShaderSnippets.fragment2DDemo
        selectedObjectID = nil
        canvasZoom = 1.0
        canvasPan = .zero
        editing2DShaderTarget = nil
        Task { @MainActor in hasUnsavedChanges = false }
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
    /// Also captures a snapshot and registers the project in the recent list.
    private func saveCanvas(to url: URL) {
        let doc = CanvasDocument(name: canvasName, mode: canvasMode, meshType: meshType, shape2DType: shape2DType, shaders: activeShaders, dataFlow: dataFlowConfig, dataFlow2D: dataFlow2DConfig, paramValues: paramValues, objects2D: objects2D.isEmpty ? nil : objects2D, sharedVertexCode2D: sharedVertexCode2D, sharedFragmentCode2D: sharedFragmentCode2D)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(doc)
            try data.write(to: url, options: .atomic)
            currentFileURL = url
            hasUnsavedChanges = false
            print("Canvas saved to \(url.path)")

            recentManager.addRecent(name: canvasName, fileURL: url, mode: canvasMode, snapshot: nil)
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
            canvasMode = doc.mode
            meshType = doc.meshType
            shape2DType = doc.shape2DType
            activeShaders = doc.shaders
            dataFlowConfig = doc.dataFlow
            dataFlow2DConfig = doc.dataFlow2D
            paramValues = doc.paramValues
            currentFileURL = url
            editingShaderID = nil
            editing2DShaderTarget = nil

            objects2D = doc.objects2D ?? []
            sharedVertexCode2D = doc.sharedVertexCode2D ?? ShaderSnippets.distortion2DTemplate
            sharedFragmentCode2D = doc.sharedFragmentCode2D ?? ShaderSnippets.fragment2DDemo
            selectedObjectID = nil
            canvasZoom = 1.0
            canvasPan = .zero

            if case .custom(let modelURL) = meshType {
                customFileName = modelURL.lastPathComponent
            } else {
                customFileName = nil
            }

            recentManager.addRecent(name: doc.name, fileURL: url, mode: doc.mode)
            Task { @MainActor in hasUnsavedChanges = false }
            print("Canvas loaded from \(url.path)")
        } catch {
            print("Failed to open canvas: \(error)")
        }
    }

    /// Checks for unsaved changes before navigating back to Hub.
    private func requestNavigateBackToHub() {
        if hasUnsavedChanges {
            showingBackToHubConfirm = true
        } else {
            navigateBackToHub()
        }
    }

    /// Navigates back to the Hub window.
    private func navigateBackToHub() {
        hasUnsavedChanges = false
        appState.currentScreen = .hub
        appState.openFileURL = nil
    }

    // MARK: - 2D Scene Helpers

    private func addObject2D() {
        let count = objects2D.count + 1
        let obj = Object2D(name: "Object \(count)")
        objects2D.append(obj)
        selectedObjectID = obj.id
    }

    private func removeObject2D(_ id: UUID) {
        objects2D.removeAll { $0.id == id }
        if selectedObjectID == id { selectedObjectID = nil }
    }

    // MARK: - Collapsible Section Header

    private func collapsibleHeader(_ title: String, isCollapsed: Binding<Bool>) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) { isCollapsed.wrappedValue.toggle() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white.opacity(0.5))
                    .rotationEffect(.degrees(isCollapsed.wrappedValue ? 0 : 90))
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2D Sidebar

    private var sidebar2DContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ─── Shared Shaders ───
            VStack(alignment: .leading, spacing: 6) {
                collapsibleHeader("Shared Shaders", isCollapsed: $isShadersCollapsed)

                if !isShadersCollapsed {
                    HStack {
                        Image(systemName: "move.3d").foregroundColor(.cyan)
                        Text("Vertex (Distortion)").foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            withAnimation { editing2DShaderTarget = .sharedVertex }
                        }) {
                            Image(systemName: "pencil.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)

                    HStack {
                        Image(systemName: "paintbrush.fill").foregroundColor(.purple)
                        Text("Fragment (Color)").foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            withAnimation { editing2DShaderTarget = .sharedFragment }
                        }) {
                            Image(systemName: "pencil.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)
                }
            }

            Divider().background(Color.white.opacity(0.2))

            // ─── Objects ───
            VStack(alignment: .leading, spacing: 6) {
                collapsibleHeader("Objects", isCollapsed: $isObjectsCollapsed)

                if !isObjectsCollapsed {
                    if objects2D.isEmpty {
                        Text("No objects yet")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        ForEach(Array(objects2D.enumerated()), id: \.element.id) { idx, object in
                            VStack(spacing: 0) {
                                HStack {
                                    Image(systemName: object.shapeType.icon)
                                        .foregroundColor(selectedObjectID == object.id ? .blue : .white.opacity(0.6))

                                    if object.isAIPreview {
                                        Text("AI").font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Color.purple.opacity(0.6))
                                            .cornerRadius(3)
                                    }

                                    Text(object.name)
                                        .foregroundColor(object.isAIPreview ? .purple.opacity(0.9) : .white)
                                        .lineLimit(1)
                                    Spacer()

                                    Button(action: { removeObject2D(object.id) }) {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.red.opacity(0.7))
                                }
                                .padding(8)
                                .background(
                                    selectedObjectID == object.id
                                        ? Color.blue.opacity(0.2)
                                        : object.isAIPreview ? Color.purple.opacity(0.1) : Color.black.opacity(0.4)
                                )
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedObjectID = object.id }

                                if selectedObjectID == object.id {
                                    objectPropertyInspector(index: idx)
                                }
                            }
                        }
                    }
                }
            }

            Divider().background(Color.white.opacity(0.2))

            // ─── Post Processing Layers ───
            VStack(alignment: .leading, spacing: 6) {
                collapsibleHeader("Post Processing", isCollapsed: $isPostProcessingCollapsed)

                if !isPostProcessingCollapsed {
                    let ppLayers = activeShaders.filter { $0.category == .fullscreen }
                    if ppLayers.isEmpty {
                        Text("No PP layers")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        ForEach(ppLayers) { shader in
                            HStack {
                                Image(systemName: "display")
                                    .foregroundColor(.orange)
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
            }
        }
        .frame(width: panelWidth)
        .padding(12)
        .glassEffect(.regular.tint(Color(white: 0.15)), in: .rect(cornerRadius: 12))
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    @ViewBuilder
    private func objectPropertyInspector(index idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Shape selection
            HStack(spacing: 4) {
                Text("Shape").font(.caption).foregroundColor(.white.opacity(0.6))
                if objects2D[idx].shapeLocked {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                        .foregroundColor(.orange.opacity(0.8))
                        .help(String(localized: "Shape locked — SDF access enabled for this object's shader"))
                    Button(action: {
                        objects2D[idx].shapeLocked = false
                    }) {
                        Image(systemName: "lock.open").font(.system(size: 9))
                            .foregroundColor(.orange.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Unlock shape (may break edge-aware shader effects)"))
                }
                Spacer()
                ForEach(Shape2DType.allCases) { shape in
                    Button(action: { objects2D[idx].shapeType = shape }) {
                        Image(systemName: shape.icon).font(.caption)
                            .foregroundColor(objects2D[idx].shapeType == shape ? .blue : .white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(objects2D[idx].shapeLocked)
                }
            }

            // Size sliders
            HStack {
                Text("W").font(.caption2).foregroundColor(.white.opacity(0.5))
                Slider(value: $objects2D[idx].scaleW, in: 0.05...2.0)
                Text("H").font(.caption2).foregroundColor(.white.opacity(0.5))
                Slider(value: $objects2D[idx].scaleH, in: 0.05...2.0)
            }

            // Rotation
            HStack {
                Text("Rot").font(.caption2).foregroundColor(.white.opacity(0.5))
                Slider(value: $objects2D[idx].rotation, in: -.pi...(.pi))
            }

            // Corner radius (visible for rounded rectangle)
            if objects2D[idx].shapeType == .roundedRectangle {
                HStack {
                    Text("R").font(.caption2).foregroundColor(.white.opacity(0.5))
                    Slider(value: $objects2D[idx].cornerRadius, in: 0.0...0.5)
                }
            }

            // Shader status
            HStack(spacing: 4) {
                let hasCustomVS = objects2D[idx].customVertexCode != nil
                let hasCustomFS = objects2D[idx].customFragmentCode != nil

                Button(action: {
                    if hasCustomVS {
                        withAnimation { editing2DShaderTarget = .objectVertex(objects2D[idx].id) }
                    } else {
                        objects2D[idx].customVertexCode = sharedVertexCode2D
                        withAnimation { editing2DShaderTarget = .objectVertex(objects2D[idx].id) }
                    }
                }) {
                    Text("VS")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundColor(hasCustomVS ? .blue : .white.opacity(0.5))
                        .background(hasCustomVS ? Color.blue.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                if hasCustomVS {
                    Button(action: { objects2D[idx].customVertexCode = nil }) {
                        Image(systemName: "arrow.uturn.backward.circle").font(.caption2)
                            .foregroundColor(.orange.opacity(0.8))
                    }.buttonStyle(.plain).help(String(localized: "Revert to shared VS"))
                }

                Button(action: {
                    if hasCustomFS {
                        withAnimation { editing2DShaderTarget = .objectFragment(objects2D[idx].id) }
                    } else {
                        objects2D[idx].customFragmentCode = sharedFragmentCode2D
                        withAnimation { editing2DShaderTarget = .objectFragment(objects2D[idx].id) }
                    }
                }) {
                    Text("FS")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundColor(hasCustomFS ? .purple : .white.opacity(0.5))
                        .background(hasCustomFS ? Color.purple.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                if hasCustomFS {
                    Button(action: { objects2D[idx].customFragmentCode = nil }) {
                        Image(systemName: "arrow.uturn.backward.circle").font(.caption2)
                            .foregroundColor(.orange.opacity(0.8))
                    }.buttonStyle(.plain).help(String(localized: "Revert to shared FS"))
                }

                Spacer()
                Text(hasCustomVS || hasCustomFS ? "Custom" : "Shared")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - 2D Shader Editor Panel

    @ViewBuilder
    private func shader2DEditorPanel(target: Edit2DShaderTarget) -> some View {
        switch target {
        case .sharedVertex:
            Shared2DShaderEditorView(
                title: "Shared Vertex (Distortion)",
                code: $sharedVertexCode2D,
                onClose: { withAnimation { editing2DShaderTarget = nil } }
            )
        case .sharedFragment:
            Shared2DShaderEditorView(
                title: "Shared Fragment (Color)",
                code: $sharedFragmentCode2D,
                onClose: { withAnimation { editing2DShaderTarget = nil } }
            )
        case .objectVertex(let objID):
            if let idx = objects2D.firstIndex(where: { $0.id == objID }),
               objects2D[idx].customVertexCode != nil {
                ObjectCustomShaderEditorView(
                    title: "\(objects2D[idx].name) — Custom VS",
                    code: Binding(
                        get: { objects2D[idx].customVertexCode ?? "" },
                        set: { objects2D[idx].customVertexCode = $0 }
                    ),
                    onClose: { withAnimation { editing2DShaderTarget = nil } }
                )
            }
        case .objectFragment(let objID):
            if let idx = objects2D.firstIndex(where: { $0.id == objID }),
               objects2D[idx].customFragmentCode != nil {
                ObjectCustomShaderEditorView(
                    title: "\(objects2D[idx].name) — Custom FS",
                    code: Binding(
                        get: { objects2D[idx].customFragmentCode ?? "" },
                        set: { objects2D[idx].customFragmentCode = $0 }
                    ),
                    onClose: { withAnimation { editing2DShaderTarget = nil } }
                )
            }
        }
    }

    // MARK: - Data Flow Panel
    
    private var dataFlowPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            collapsibleHeader("Data Flow", isCollapsed: $isDataFlowCollapsed)
            
            if !isDataFlowCollapsed {
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
        }
        .frame(width: panelWidth)
        .padding(12)
        .glassEffect(.regular.tint(Color(white: 0.15)), in: .rect(cornerRadius: 12))
        .transition(.move(edge: .leading).combined(with: .opacity))
        .onChange(of: dataFlowConfig) { _ in
            dataFlowConfig.resolveDependencies()
        }
    }
    
    // MARK: - 2D Data Flow Panel

    private var dataFlow2DPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            collapsibleHeader("Data Flow", isCollapsed: $isDataFlowCollapsed)

            if !isDataFlowCollapsed {
                Text("Vertex fields for all 2D object shaders")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 4)

                Group {
                    dataFlowToggle(label: "Time", icon: "clock", binding: $dataFlow2DConfig.timeEnabled, locked: false)
                    dataFlowToggle(label: "Mouse", icon: "cursorarrow.motionlines", binding: $dataFlow2DConfig.mouseEnabled, locked: false)
                    dataFlowToggle(label: "Object Position", icon: "square.on.square.dashed", binding: $dataFlow2DConfig.objectPositionEnabled, locked: false)
                    dataFlowToggle(label: "Screen UV", icon: "rectangle.dashed", binding: $dataFlow2DConfig.screenUVEnabled, locked: false)
                }

                Divider().background(Color.white.opacity(0.2))

                dataFlow2DPreview
            }
        }
        .frame(width: panelWidth)
        .padding(12)
        .glassEffect(.regular.tint(Color(white: 0.15)), in: .rect(cornerRadius: 12))
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var dataFlow2DPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Generated Structs")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }

            ScrollView {
                Text(ShaderSnippets.generateStructPreview2D(config: dataFlow2DConfig))
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

    /// Parsed @param declarations from the currently editing shader.
    /// In 3D mode: from the active shader layer being edited.
    /// In 2D mode: from the currently editing shared/per-object shader.
    private var allParsedParams: [ShaderParam] {
        if canvasMode.is2D {
            return parsed2DParams
        }
        guard let editingID = editingShaderID,
              let shader = activeShaders.first(where: { $0.id == editingID }) else { return [] }
        return ShaderSnippets.parseParams(from: shader.code)
    }

    private var parsed2DParams: [ShaderParam] {
        guard let target = editing2DShaderTarget else {
            // No editor open — show params from the selected object or shared shaders
            var codes = [sharedVertexCode2D, sharedFragmentCode2D]
            if let selID = selectedObjectID, let obj = objects2D.first(where: { $0.id == selID }) {
                if let vs = obj.customVertexCode { codes.append(vs) }
                if let fs = obj.customFragmentCode { codes.append(fs) }
            }
            var result: [ShaderParam] = []; var seen = Set<String>()
            for code in codes {
                for p in ShaderSnippets.parseParams(from: code) {
                    if seen.insert(p.name).inserted { result.append(p) }
                }
            }
            return result
        }
        switch target {
        case .sharedVertex:   return ShaderSnippets.parseParams(from: sharedVertexCode2D)
        case .sharedFragment: return ShaderSnippets.parseParams(from: sharedFragmentCode2D)
        case .objectVertex(let id):
            guard let obj = objects2D.first(where: { $0.id == id }), let code = obj.customVertexCode else { return [] }
            return ShaderSnippets.parseParams(from: code)
        case .objectFragment(let id):
            guard let obj = objects2D.first(where: { $0.id == id }), let code = obj.customFragmentCode else { return [] }
            return ShaderSnippets.parseParams(from: code)
        }
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
            HStack(spacing: 6) {
                collapsibleHeader("Parameters", isCollapsed: $isParametersCollapsed)
                
                if !isParametersCollapsed, editingShaderID != nil || editing2DShaderTarget != nil {
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
            
            if !isParametersCollapsed {
                if allParsedParams.isEmpty {
                    Text((editingShaderID != nil || editing2DShaderTarget != nil)
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
        }
        .frame(width: panelWidth)
        .padding(12)
        .glassEffect(.regular.tint(Color(white: 0.15)), in: .rect(cornerRadius: 12))
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
        let name = nextParamName(type: type)
        var directive: String
        switch type {
        case .float:
            directive = withRange
                ? "// @param \(name) float 0.5 0.0 1.0"
                : "// @param \(name) float 0.0"
        case .float2:  directive = "// @param \(name) float2 0.0 0.0"
        case .float3:  directive = "// @param \(name) float3 0.0 0.0 0.0"
        case .float4:  directive = "// @param \(name) float4 0.0 0.0 0.0 0.0"
        case .color:   directive = "// @param \(name) color 1.0 1.0 1.0"
        }

        // 3D mode: inject into the active shader layer
        if let editingID = editingShaderID,
           let index = activeShaders.firstIndex(where: { $0.id == editingID }) {
            activeShaders[index].code = directive + "\n" + activeShaders[index].code
            return
        }
        // 2D mode: inject into the currently editing 2D shader target
        guard let target = editing2DShaderTarget else { return }
        switch target {
        case .sharedVertex:   sharedVertexCode2D = directive + "\n" + sharedVertexCode2D
        case .sharedFragment: sharedFragmentCode2D = directive + "\n" + sharedFragmentCode2D
        case .objectVertex(let id):
            if let idx = objects2D.firstIndex(where: { $0.id == id }) {
                objects2D[idx].customVertexCode = directive + "\n" + (objects2D[idx].customVertexCode ?? "")
            }
        case .objectFragment(let id):
            if let idx = objects2D.firstIndex(where: { $0.id == id }) {
                objects2D[idx].customFragmentCode = directive + "\n" + (objects2D[idx].customFragmentCode ?? "")
            }
        }
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

        // Try replacing in 3D active shader layers
        for i in activeShaders.indices {
            let code = activeShaders[i].code
            if let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) {
                activeShaders[i].code = (code as NSString).replacingCharacters(in: match.range, with: newDirective)
                return
            }
        }
        // Try replacing in 2D shared shaders
        for code in [sharedVertexCode2D, sharedFragmentCode2D] {
            if let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) {
                let replaced = (code as NSString).replacingCharacters(in: match.range, with: newDirective)
                if code == sharedVertexCode2D { sharedVertexCode2D = replaced }
                else { sharedFragmentCode2D = replaced }
                return
            }
        }
        // Try replacing in 2D per-object custom shaders
        for i in objects2D.indices {
            if let code = objects2D[i].customVertexCode,
               let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) {
                objects2D[i].customVertexCode = (code as NSString).replacingCharacters(in: match.range, with: newDirective)
                return
            }
            if let code = objects2D[i].customFragmentCode,
               let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) {
                objects2D[i].customFragmentCode = (code as NSString).replacingCharacters(in: match.range, with: newDirective)
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
    /// Posted when the user responds to a shape-lock permission dialog.
    /// `object` is `true` (approved) or `false` (denied).
    static let shapeLockResolved = NSNotification.Name("shapeLockResolved")
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

// MARK: - Shared 2D Shader Editor View

struct Shared2DShaderEditorView: View {
    let title: String
    @Binding var code: String
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.black.opacity(0.6))

            CodeEditor(text: $code)
        }
        .background(Color.black.opacity(0.85))
        .cornerRadius(10)
    }
}

// MARK: - Object Custom Shader Editor View

struct ObjectCustomShaderEditorView: View {
    let title: String
    @Binding var code: String
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.black.opacity(0.6))

            CodeEditor(text: $code)
        }
        .background(Color.black.opacity(0.85))
        .cornerRadius(10)
    }
}

// MARK: - ContentView Helper Modifiers

/// Extracts all NotificationCenter receivers and onAppear into a single
/// modifier to reduce type-checker load on ContentView.body.
private struct CanvasLifecycleModifier: ViewModifier {
    let canvasMode: CanvasMode
    let openFileURL: URL?
    let onInit: (CanvasMode, URL?) -> Void
    let onNewCanvas: () -> Void
    let onSave: () -> Void
    let onSaveAs: () -> Void
    let onOpen: () -> Void
    let onTutorial: () -> Void
    let onSettings: () -> Void
    let onChat: () -> Void
    let onBackToHub: () -> Void
    let onCompilationResult: (String?) -> Void
    let onObjectSelected: (UUID?) -> Void
    let onObjectMoved: (UUID, Float, Float) -> Void
    let onZoomChanged: (Float) -> Void
    let onPanChanged: (simd_float2) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { onInit(canvasMode, openFileURL) }
            .onReceive(NotificationCenter.default.publisher(for: .canvasNew)) { _ in onNewCanvas() }
            .onReceive(NotificationCenter.default.publisher(for: .canvasSave)) { _ in onSave() }
            .onReceive(NotificationCenter.default.publisher(for: .canvasSaveAs)) { _ in onSaveAs() }
            .onReceive(NotificationCenter.default.publisher(for: .canvasOpen)) { _ in onOpen() }
            .onReceive(NotificationCenter.default.publisher(for: .canvasTutorial)) { _ in onTutorial() }
            .onReceive(NotificationCenter.default.publisher(for: .aiSettings)) { _ in onSettings() }
            .onReceive(NotificationCenter.default.publisher(for: .aiChat)) { _ in onChat() }
            .onReceive(NotificationCenter.default.publisher(for: .backToHub)) { _ in onBackToHub() }
            .onReceive(NotificationCenter.default.publisher(for: .shaderCompilationResult)) { n in
                onCompilationResult(n.object as? String)
            }
            .onReceive(NotificationCenter.default.publisher(for: .canvas2DObjectSelected)) { n in
                onObjectSelected(n.object as? UUID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .canvas2DObjectMoved)) { n in
                guard let arr = n.object as? [Any],
                      let id = arr[0] as? UUID,
                      let px = arr[1] as? Float,
                      let py = arr[2] as? Float else { return }
                onObjectMoved(id, px, py)
            }
            .onReceive(NotificationCenter.default.publisher(for: .canvas2DZoomChanged)) { n in
                if let z = n.object as? Float { onZoomChanged(z) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .canvas2DPanChanged)) { n in
                if let arr = n.object as? [Float], arr.count >= 2 {
                    onPanChanged(simd_float2(arr[0], arr[1]))
                }
            }
    }
}

#Preview {
    ContentView(appState: AppState(), recentManager: RecentProjectManager())
}
