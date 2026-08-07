//
//  ClipboardManager.swift
//  boringNotch
//
//  Created by Tudor Sandu on 2026-08-07.
//

import AppKit
import Combine
import Defaults
import Foundation

/// Monitors the system pasteboard and maintains a persistent clipboard history.
///
/// macOS does not expose clipboard change notifications, so the manager
/// polls `NSPasteboard.general.changeCount` on a timer and captures new
/// content whenever the count changes.
@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isMonitoring: Bool = false

    private let persistence = ClipboardPersistenceService()

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var defaultsObserver: AnyCancellable?
    private var isRestoringPasteboard = false

    private init() {
        items = persistence.load()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastChangeCount = NSPasteboard.general.changeCount
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        defaultsObserver = Defaults.publisher(.clipboardHistoryLimit)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.trimToLimit()
                }
            }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        defaultsObserver?.cancel()
        defaultsObserver = nil
        isMonitoring = false
    }

    private func poll() {
        guard !isRestoringPasteboard else { return }
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let item = capture(pasteboard) else { return }

        let signature = item.contentSignature
        if let mostRecent = items.first, mostRecent.contentSignature == signature {
            items[0].copiedAt = Date()
            persistence.save(items)
            return
        }

        items.insert(item, at: 0)
        trimToLimit()
        persistence.save(items)
    }

    // MARK: - Capture

    private func capture(_ pasteboard: NSPasteboard) -> ClipboardItem? {
        if pasteboard.availableType(from: [.fileURL]) != nil,
            let urls = pasteboard.propertyList(forType: .fileURL) as? [String],
            !urls.isEmpty
        {
            return ClipboardItem(kind: .fileURL, fileURLs: urls)
        }

        if pasteboard.availableType(from: [.tiff]) != nil,
            let data = pasteboard.data(forType: .tiff),
            let image = NSImage(data: data),
            let pngData = image.normalizedPNGData(maxDimension: 1024)
        {
            return ClipboardItem(kind: .image, imageData: pngData)
        }

        if let text = pasteboardText(pasteboard), !text.isEmpty {
            return ClipboardItem(kind: .text, text: text)
        }

        return nil
    }

    private func pasteboardText(_ pasteboard: NSPasteboard) -> String? {
        if let string = pasteboard.string(forType: .string) {
            return string
        }
        if let data = pasteboard.data(forType: .rtf), let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            return attributed.string
        }
        if let data = pasteboard.data(forType: .html),
            let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
        {
            return attributed.string
        }
        let utf8PlainText = NSPasteboard.PasteboardType("public.utf8-plain-text")
        if pasteboard.availableType(from: [utf8PlainText]) != nil,
            let data = pasteboard.data(forType: utf8PlainText),
            let string = String(data: data, encoding: .utf8)
        {
            return string
        }
        return nil
    }

    // MARK: - Thumbnails

    private let imageCache = NSCache<NSString, NSImage>()

    /// Returns a small cached thumbnail for the item, decoding the full image only once.
    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard let data = item.imageData else { return nil }
        let key = item.id.uuidString as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(data: data) else { return nil }
        let thumb = image.downscaled(to: NSSize(width: 56, height: 56))
        imageCache.setObject(thumb, forKey: key)
        return thumb
    }

    // MARK: - Actions

    func copy(_ item: ClipboardItem) {
        isRestoringPasteboard = true
        defer { isRestoringPasteboard = false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            if let data = item.imageData {
                pasteboard.setData(data, forType: .png)
            }
        case .fileURL:
            if let urls = item.fileURLs {
                let nsurls = urls.map { URL(fileURLWithPath: $0) as NSURL }
                pasteboard.writeObjects(nsurls)
            }
        }

        items[items.firstIndex(of: item) ?? 0].copiedAt = Date()
        persistence.save(items)
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        persistence.save(items)
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        items.sort { $0.isPinned && !$1.isPinned }
        persistence.save(items)
    }

    func clear() {
        items.removeAll()
        persistence.save(items)
    }

    private func trimToLimit() {
        let limit = Defaults[.clipboardHistoryLimit]
        guard items.count > limit else { return }
        let pinned = items.filter(\.isPinned)
        let unpinned = items.filter { !$0.isPinned }
        items = pinned + Array(unpinned.prefix(max(0, limit - pinned.count)))
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else {
            return nil
        }
        return data
    }

    /// Downscales the image to fit within `maxDimension` before encoding, so large
    /// screenshots don't bloat history storage.
    func normalizedPNGData(maxDimension: CGFloat) -> Data? {
        let size = self.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return pngData() }
        let scale = maxDimension / maxSide
        let target = downscaled(to: NSSize(width: size.width * scale, height: size.height * scale))
        return target.pngData()
    }

    /// Draws the image into `size`, aspect-filled and centered.
    func downscaled(to size: NSSize) -> NSImage {
        let target = NSImage(size: size)
        target.lockFocus()
        guard let context = NSGraphicsContext.current else {
            target.unlockFocus()
            return target
        }
        context.imageInterpolation = .high

        let imageSize = self.size
        let scale = max(size.width / max(imageSize.width, 1), size.height / max(imageSize.height, 1))
        let scaledSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = NSPoint(
            x: (size.width - scaledSize.width) / 2,
            y: (size.height - scaledSize.height) / 2
        )
        draw(
            in: NSRect(origin: origin, size: scaledSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        target.unlockFocus()
        return target
    }
}

/// Persists clipboard history as JSON in Application Support, mirroring the Shelf pattern.
private final class ClipboardPersistenceService {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (support ?? fm.temporaryDirectory).appendingPathComponent("boringNotch", isDirectory: true).appendingPathComponent("Clipboard", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        if let items = try? decoder.decode([ClipboardItem].self, from: data) {
            return items
        }
        print("⚠️ Failed to decode clipboard history, starting fresh")
        return []
    }

    func save(_ items: [ClipboardItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save clipboard history: \(error.localizedDescription)")
        }
    }
}
