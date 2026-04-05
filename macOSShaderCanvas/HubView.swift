//
//  HubView.swift
//  macOSShaderCanvas
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - App State

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
    @State private var hoveredNewProject: CanvasMode? = nil

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(red: 0.098, green: 0.098, blue: 0.106, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().opacity(0.2)

                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        newProjectSection
                        recentProjectsSection
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Metal Shader Canvas")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Button(action: openFilePicker) {
                Label("Open…", systemImage: "folder")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 14)
    }

    // MARK: - New Project

    private var newProjectSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("New Project")

            HStack(spacing: 12) {
                newProjectCard(title: "2D Canvas", icon: "square.grid.3x3", mode: .twoDimensional)
                newProjectCard(title: "3D Canvas",  icon: "cube",            mode: .threeDimensional)
                newProjectCard(title: "2D Lab",     icon: "flask",           mode: .twoDimensionalLab)
                newProjectCard(title: "3D Lab",     icon: "flask",           mode: .threeDimensionalLab)
            }
        }
    }

    private func newProjectCard(title: String, icon: String, mode: CanvasMode) -> some View {
        let isHovered = hoveredNewProject == mode
        return Button {
            appState.canvasMode = mode
            appState.openFileURL = nil
            appState.currentScreen = .editor
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.white.opacity(isHovered ? 0.9 : 0.45))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 0.9 : 0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredNewProject = inside ? mode : nil
            }
        }
    }

    // MARK: - Recent Projects

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Recent")

            if recentManager.recentProjects.isEmpty {
                Text("No recent projects")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.18))
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                    ForEach(recentManager.recentProjects) { project in
                        recentProjectCard(project)
                    }
                }
            }
        }
    }

    private func recentProjectCard(_ project: RecentProject) -> some View {
        let isHovered = hoveredProjectURL == project.fileURL
        return Button {
            appState.canvasMode = project.mode
            appState.openFileURL = URL(fileURLWithPath: project.fileURL)
            appState.currentScreen = .editor
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    Color.white.opacity(0.03)
                    if let img = recentManager.snapshotImage(for: project) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: project.mode.isLab ? "flask" : (project.mode.is2D ? "square.grid.3x3" : "cube"))
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(.white.opacity(0.10))
                    }
                }
                .frame(height: 100)
                .clipped()

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    HStack(spacing: 0) {
                        Text(modeLabel(project.mode))
                        Text(" · ")
                        Text(project.lastOpened, style: .relative)
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.28))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isHovered ? 0.07 : 0.04))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredProjectURL = hovering ? project.fileURL : nil
            }
        }
        .contextMenu {
            Button("Remove from Recents", role: .destructive) {
                recentManager.removeRecent(at: project.fileURL)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.35))
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func modeLabel(_ mode: CanvasMode) -> String {
        switch mode {
        case .twoDimensional:      return "2D"
        case .threeDimensional:    return "3D"
        case .twoDimensionalLab:   return "2D Lab"
        case .threeDimensionalLab: return "3D Lab"
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
