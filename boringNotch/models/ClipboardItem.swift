//
//  ClipboardItem.swift
//  boringNotch
//
//  Created by Tudor Sandu on 2026-08-07.
//

import Foundation

enum ClipboardItemKind: String, Codable {
    case text
    case image
    case fileURL
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: ClipboardItemKind
    var text: String?
    var imageData: Data?
    var fileURLs: [String]?
    var copiedAt: Date
    var isPinned: Bool

    init(
        kind: ClipboardItemKind,
        text: String? = nil,
        imageData: Data? = nil,
        fileURLs: [String]? = nil,
        copiedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.fileURLs = fileURLs
        self.copiedAt = copiedAt
        self.isPinned = isPinned
    }

    var previewText: String {
        switch kind {
        case .text:
            return text ?? ""
        case .image:
            return "Image"
        case .fileURL:
            let urls = fileURLs ?? []
            if urls.isEmpty {
                return "File"
            }
            return urls.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        }
    }

    var contentSignature: String {
        switch kind {
        case .text:
            return "text:" + (text ?? "")
        case .image:
            return "image:" + (imageData?.count.description ?? "0")
        case .fileURL:
            return "file:" + (fileURLs ?? []).joined(separator: "\n")
        }
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}
