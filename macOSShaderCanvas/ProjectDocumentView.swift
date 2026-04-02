//
//  ProjectDocumentView.swift
//  macOSShaderCanvas
//
//  MarkdownDocumentView — reusable markdown editor/viewer for Lab mode documents.
//  Used by both the Design Doc and Project Doc center-panel tabs.
//
//  Modes:
//  - Read: renders markdown via MarkdownTextView (headings, code, lists, bold, inline code)
//  - Edit: raw markdown TextEditor for direct editing
//
//  Toolbar: edit toggle, export .md, copy to clipboard
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - MarkdownDocumentView

struct MarkdownDocumentView: View {
    @Binding var markdown: String
    @Binding var lastModified: Date
    let title: String
    let accentColor: Color

    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Color.white.opacity(0.1))
            content
        }
        .background(Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 11))
                .foregroundColor(accentColor)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            if !markdown.isEmpty {
                Text("Modified \(lastModified, style: .relative) ago")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            Button(action: { isEditing.toggle() }) {
                Image(systemName: isEditing ? "eye" : "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(isEditing ? .cyan : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(isEditing ? "Switch to preview" : "Edit markdown")

            Button(action: copyToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
            .disabled(markdown.isEmpty)

            Button(action: exportMarkdown) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Export as .md file")
            .disabled(markdown.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEditing {
            emptyState
        } else if isEditing {
            editMode
        } else {
            readMode
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.15))
            Text("No content yet")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.3))
            Text("The AI will write here as the conversation progresses, or you can start editing directly.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button("Start Editing") {
                isEditing = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(accentColor.opacity(0.15))
            .cornerRadius(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editMode: some View {
        TextEditor(text: $markdown)
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.2))
            .padding(8)
            .onChange(of: markdown) {
                lastModified = Date()
            }
    }

    private var readMode: some View {
        ScrollView {
            MarkdownTextView(markdown, fontSize: 12, color: .white.opacity(0.85))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.title = "Export \(title)"
        let safeName = title
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        panel.nameFieldStringValue = "\(safeName).md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("[MarkdownDocumentView] Export failed: \(error)")
            }
        }
    }
}
