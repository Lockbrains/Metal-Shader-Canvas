//
//  ReferenceBoard.swift
//  macOSShaderCanvas
//
//  Reference collection panel for Lab mode. Supports drag-and-drop import of
//  images (jpg/png/webp), videos (mp4/mov), animated GIFs, and text descriptions.
//  Each reference can be annotated and sent to AI for analysis.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - ReferenceBoard

struct ReferenceBoard: View {
    @Binding var references: [ReferenceItem]
    @State private var isGridView = true
    @State private var expandedItemID: UUID? = nil
    @State private var editingAnnotation: UUID? = nil
    @State private var newTextDescription = ""
    @State private var isAddingText = false
    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Color.white.opacity(0.1))

            if references.isEmpty {
                emptyState
            } else {
                ScrollView {
                    if isGridView {
                        gridLayout
                    } else {
                        listLayout
                    }
                }
            }
        }
        .overlay(dragOverlay)
        .onDrop(of: supportedDropTypes, isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $isAddingText) {
            textDescriptionSheet
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("References")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            Text("\(references.count)")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.08))
                .cornerRadius(3)

            Spacer()

            Button(action: { isAddingText = true }) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Add text description")

            Button(action: importFromFile) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Import file")

            Button(action: { withAnimation { isGridView.toggle() } }) {
                Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Grid Layout

    private var gridLayout: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 8)], spacing: 8) {
            ForEach(references) { ref in
                referenceGridItem(ref)
            }
        }
        .padding(8)
    }

    private func referenceGridItem(_ ref: ReferenceItem) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Color.black.opacity(0.3)

                if let thumbData = ref.thumbnailData, let nsImage = NSImage(data: thumbData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    typeIcon(ref.type)
                }
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 3) {
                Image(systemName: typeIconName(ref.type))
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.4))
                Text(ref.annotation.isEmpty ? (ref.originalFilename ?? ref.type.rawValue) : ref.annotation)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .onTapGesture { expandedItemID = ref.id }
        .contextMenu {
            Button("Edit Annotation") { editingAnnotation = ref.id }
            Button("Remove", role: .destructive) {
                references.removeAll { $0.id == ref.id }
            }
        }
    }

    // MARK: - List Layout

    private var listLayout: some View {
        VStack(spacing: 4) {
            ForEach(references) { ref in
                referenceListItem(ref)
            }
        }
        .padding(8)
    }

    private func referenceListItem(_ ref: ReferenceItem) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Color.black.opacity(0.3)
                if let thumbData = ref.thumbnailData, let nsImage = NSImage(data: thumbData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    typeIcon(ref.type)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(ref.originalFilename ?? ref.type.rawValue.capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)

                if !ref.annotation.isEmpty {
                    Text(ref.annotation)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }

                Text(ref.dateAdded, style: .relative)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            Image(systemName: typeIconName(ref.type))
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
        .contextMenu {
            Button("Edit Annotation") { editingAnnotation = ref.id }
            Button("Remove", role: .destructive) {
                references.removeAll { $0.id == ref.id }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.15))
            Text("Drop references here")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
            Text("Images, Videos, GIFs, or Text")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Drag Overlay

    private var dragOverlay: some View {
        Group {
            if isDragOver {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.green, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Color.green.opacity(0.05))
                    .padding(4)
            }
        }
    }

    // MARK: - Drop Handling

    private var supportedDropTypes: [UTType] {
        [.image, .movie, .gif, .fileURL]
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async {
                        addImageReference(data: data, filename: nil)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                    guard let url else { return }
                    let data = try? Data(contentsOf: url)
                    let thumbnail = generateVideoThumbnail(url: url)
                    DispatchQueue.main.async {
                        let ref = ReferenceItem(
                            type: .video,
                            mediaData: data,
                            thumbnailData: thumbnail,
                            originalFilename: url.lastPathComponent
                        )
                        references.append(ref)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        importFile(at: url)
                    }
                }
            }
        }
        return true
    }

    // MARK: - File Import

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Reference"
        panel.allowedContentTypes = [.image, .movie, .gif,
                                     UTType(filenameExtension: "gif") ?? .gif]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                importFile(at: url)
            }
        }
    }

    private func importFile(at url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "heic", "tiff", "bmp"].contains(ext) {
            if let data = try? Data(contentsOf: url) {
                addImageReference(data: data, filename: url.lastPathComponent)
            }
        } else if ext == "gif" {
            if let data = try? Data(contentsOf: url) {
                let thumb = NSImage(data: data)?.jpegThumbnail(maxSize: 200)
                let ref = ReferenceItem(type: .gif, mediaData: data, thumbnailData: thumb, originalFilename: url.lastPathComponent)
                references.append(ref)
            }
        } else if ["mp4", "mov", "m4v"].contains(ext) {
            let data = try? Data(contentsOf: url)
            let thumb = generateVideoThumbnail(url: url)
            let ref = ReferenceItem(type: .video, mediaData: data, thumbnailData: thumb, originalFilename: url.lastPathComponent)
            references.append(ref)
        }
    }

    private func addImageReference(data: Data, filename: String?) {
        let thumb = NSImage(data: data)?.jpegThumbnail(maxSize: 200)
        let ref = ReferenceItem(type: .image, mediaData: data, thumbnailData: thumb, originalFilename: filename)
        references.append(ref)
    }

    // MARK: - Text Description Sheet

    private var textDescriptionSheet: some View {
        VStack(spacing: 16) {
            Text("Add Text Reference")
                .font(.headline)
                .foregroundColor(.white)

            TextEditor(text: $newTextDescription)
                .font(.system(size: 12))
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)

            HStack {
                Button("Cancel") {
                    newTextDescription = ""
                    isAddingText = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add") {
                    let ref = ReferenceItem(type: .text, annotation: String(newTextDescription.prefix(60)), textContent: newTextDescription)
                    references.append(ref)
                    newTextDescription = ""
                    isAddingText = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Helpers

    private func typeIcon(_ type: ReferenceType) -> some View {
        Image(systemName: typeIconName(type))
            .font(.system(size: 20))
            .foregroundColor(.white.opacity(0.2))
    }

    private func typeIconName(_ type: ReferenceType) -> String {
        switch type {
        case .image: return "photo"
        case .video: return "film"
        case .gif:   return "photo.stack"
        case .text:  return "doc.text"
        }
    }

    private func generateVideoThumbnail(url: URL) -> Data? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return nsImage.jpegThumbnail(maxSize: 200)
        }
        return nil
    }
}

// MARK: - NSImage Thumbnail Extension

extension NSImage {
    func jpegThumbnail(maxSize: CGFloat) -> Data? {
        let ratio = min(maxSize / size.width, maxSize / size.height, 1.0)
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
