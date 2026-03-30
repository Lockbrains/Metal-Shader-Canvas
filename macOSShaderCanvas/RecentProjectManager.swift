//
//  RecentProjectManager.swift
//  macOSShaderCanvas
//
//  Manages the list of recently-opened projects shown in the Hub window.
//  Data is persisted in UserDefaults; snapshot thumbnails are stored as
//  PNG files under ~/Library/Application Support/macOSShaderCanvas/snapshots/.
//

import AppKit
import Foundation

@Observable
class RecentProjectManager {

    private static let defaultsKey = "recentProjects"
    private static let maxRecents = 20

    var recentProjects: [RecentProject] = []

    init() {
        load()
    }

    // MARK: - Public API

    func addRecent(name: String, fileURL: URL, mode: CanvasMode, snapshot: NSImage? = nil) {
        var entry = RecentProject(
            name: name,
            fileURL: fileURL.path,
            mode: mode,
            lastOpened: Date(),
            snapshotPath: nil
        )

        if let snapshot {
            entry.snapshotPath = saveSnapshot(snapshot, for: fileURL)
        }

        recentProjects.removeAll { $0.fileURL == fileURL.path }
        recentProjects.insert(entry, at: 0)
        if recentProjects.count > Self.maxRecents {
            recentProjects = Array(recentProjects.prefix(Self.maxRecents))
        }
        save()
    }

    func removeRecent(at url: String) {
        recentProjects.removeAll { $0.fileURL == url }
        save()
    }

    func snapshotImage(for project: RecentProject) -> NSImage? {
        guard let path = project.snapshotPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([RecentProject].self, from: data) else {
            return
        }
        recentProjects = decoded.filter {
            FileManager.default.fileExists(atPath: $0.fileURL)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(recentProjects) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    // MARK: - Snapshot Storage

    private var snapshotsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("macOSShaderCanvas/snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func saveSnapshot(_ image: NSImage, for fileURL: URL) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let thumbW = 400, thumbH = 300
        guard let ctx = CGContext(
            data: nil, width: thumbW, height: thumbH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high

        let srcAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        let dstAspect = CGFloat(thumbW) / CGFloat(thumbH)
        var drawRect = CGRect(x: 0, y: 0, width: thumbW, height: thumbH)
        if srcAspect > dstAspect {
            let h = CGFloat(thumbW) / srcAspect
            drawRect = CGRect(x: 0, y: (CGFloat(thumbH) - h) / 2, width: CGFloat(thumbW), height: h)
        } else {
            let w = CGFloat(thumbH) * srcAspect
            drawRect = CGRect(x: (CGFloat(thumbW) - w) / 2, y: 0, width: w, height: CGFloat(thumbH))
        }
        ctx.draw(cgImage, in: drawRect)

        guard let thumbCG = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: thumbCG)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }

        let id = fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
        let dest = snapshotsDirectory.appendingPathComponent("\(id).png")
        try? png.write(to: dest)
        return dest.path
    }
}
