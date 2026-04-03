//
//  HubView.swift
//  macOSShaderCanvas
//
//  The Hub is the app's landing screen (Unreal-style project browser).
//  It displays recent projects with snapshot thumbnails and provides
//  buttons to create a new 2D or 3D canvas.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - App State

/// Top-level observable state controlling Hub vs Editor navigation.
@Observable
class AppState {
    enum Screen { case hub, editor }
    var currentScreen: Screen = .hub
    var canvasMode: CanvasMode = .threeDimensional
    var openFileURL: URL? = nil
}

// MARK: - HubView

struct HubView: View {
    var appState: AppState
    var recentManager: RecentProjectManager

    @State private var hoveredProjectURL: String? = nil

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(Color.white.opacity(0.1))
                newProjectSection
                Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 32)
                recentProjectsSection
            }
        }
        .frame(minWidth: 780, minHeight: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
            Text("Metal Shader Canvas")
                .font(.title2).bold()
                .foregroundColor(.white)
            Spacer()
            Button(action: openFilePicker) {
                Label("Open...", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
    }

    // MARK: - New Project

    private var newProjectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Project")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))

            HStack(spacing: 20) {
                newProjectCard(
                    title: "2D Canvas",
                    subtitle: String(localized: "Fragment shaders on a fullscreen quad"),
                    icon: "square.grid.3x3",
                    gradient: [.cyan, .blue],
                    mode: .twoDimensional
                )
                newProjectCard(
                    title: "3D Canvas",
                    subtitle: String(localized: "Vertex & fragment shaders on 3D meshes"),
                    icon: "cube.fill",
                    gradient: [.purple, .pink],
                    mode: .threeDimensional
                )
                newProjectCard(
                    title: "2D Lab",
                    subtitle: String(localized: "AI-collaborative 2D shader development"),
                    icon: "flask.fill",
                    gradient: [.green, .teal],
                    mode: .twoDimensionalLab
                )
                newProjectCard(
                    title: "3D Lab",
                    subtitle: String(localized: "AI-collaborative 3D shader development"),
                    icon: "flask.fill",
                    gradient: [.orange, .red],
                    mode: .threeDimensionalLab
                )
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
    }

    private func newProjectCard(title: String, subtitle: String, icon: String, gradient: [Color], mode: CanvasMode) -> some View {
        Button {
            appState.canvasMode = mode
            appState.openFileURL = nil
            appState.currentScreen = .editor
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.linearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(Color.white.opacity(0.06))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Projects

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Projects")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))

            if recentManager.recentProjects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.2))
                    Text("No Recent Projects")
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 16) {
                        ForEach(recentManager.recentProjects) { project in
                            recentProjectCard(project)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func recentProjectCard(_ project: RecentProject) -> some View {
        Button {
            appState.canvasMode = project.mode
            appState.openFileURL = URL(fileURLWithPath: project.fileURL)
            appState.currentScreen = .editor
        } label: {
            VStack(spacing: 0) {
                // Thumbnail
                ZStack {
                    Color.black.opacity(0.3)
                    if let img = recentManager.snapshotImage(for: project) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: project.mode.isLab ? "flask.fill" : (project.mode.is2D ? "square.grid.3x3" : "cube.fill"))
                            .font(.title)
                            .foregroundColor(.white.opacity(0.15))
                    }
                }
                .frame(height: 110)
                .clipped()

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(project.name)
                            .font(.caption).bold()
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(project.mode.rawValue)
                            .font(.caption2).bold()
                            .foregroundColor(modeAccentColor(project.mode))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(modeAccentColor(project.mode).opacity(0.15))
                            .cornerRadius(4)
                    }
                    Text(project.lastOpened, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(8)
            }
            .background(Color.white.opacity(hoveredProjectURL == project.fileURL ? 0.10 : 0.05))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(hoveredProjectURL == project.fileURL ? 0.15 : 0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredProjectURL = hovering ? project.fileURL : nil
        }
        .contextMenu {
            Button("Remove from Recents", role: .destructive) {
                recentManager.removeRecent(at: project.fileURL)
            }
        }
    }

    private func modeAccentColor(_ mode: CanvasMode) -> Color {
        switch mode {
        case .twoDimensional:    return .cyan
        case .threeDimensional:  return .purple
        case .twoDimensionalLab: return .green
        case .threeDimensionalLab: return .orange
        }
    }

    // MARK: - Open File Picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open Canvas")
        panel.allowedContentTypes = [.shaderCanvas, .shaderLab]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url),
               let doc = try? JSONDecoder().decode(CanvasDocument.self, from: data) {
                appState.canvasMode = doc.mode
            }
            appState.openFileURL = url
            appState.currentScreen = .editor
        }
    }
}
