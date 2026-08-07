//
//  ClipboardView.swift
//  boringNotch
//
//  Created by Tudor Sandu on 2026-08-07.
//

import AppKit
import SwiftUI

struct ClipboardView: View {
    @ObservedObject var manager = ClipboardManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @State private var copiedItemID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if manager.items.isEmpty {
                Spacer()
                EmptyStateView(message: "Nothing copied yet")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(manager.items) { item in
                            ClipboardItemRow(item: item, copied: copiedItemID == item.id) {
                                copy(item)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .onHover { hovering in
                    vm.isHoveringClipboard = hovering
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var header: some View {
        HStack {
            Text("Clipboard history")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            if !manager.items.isEmpty {
                Button {
                    manager.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.system(.caption, design: .rounded))
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal, 4)
    }

    private func copy(_ item: ClipboardItem) {
        manager.copy(item)
        withAnimation(.snappy) {
            copiedItemID = item.id
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedItemID == item.id {
                withAnimation(.snappy) {
                    copiedItemID = nil
                }
            }
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let copied: Bool
    let onCopy: () -> Void

    @State private var isHovering = false
    @State private var showActions = false
    @State private var hoverTask: Task<Void, Never>?

    private let actionsWidth: CGFloat = 56
    private let maxTextChars = 40

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 28, height: 28)
                .background(Color(nsColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))

            content

            Spacer(minLength: 4)

            Group {
                if copied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else if showActions {
                    HStack(spacing: 10) {
                        Button {
                            onCopy()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        Button {
                            ClipboardManager.shared.togglePin(item)
                        } label: {
                            Image(systemName: item.isPinned ? "pin.slash" : "pin")
                        }
                        Button {
                            ClipboardManager.shared.remove(item)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .transition(.opacity)
                }
            }
            .frame(width: actionsWidth, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .secondarySystemFill).opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onCopy() }
        .onHover { hovering in
            hoverTask?.cancel()
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
            if hovering {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        showActions = true
                    }
                }
            } else {
                showActions = false
            }
        }
    }

    private var croppedText: String {
        let text = item.text ?? ""
        guard text.count > maxTextChars else { return text }
        return String(text.prefix(maxTextChars)) + "…"
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .foregroundStyle(.gray)
        case .image:
            if let image = ClipboardManager.shared.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.gray)
            }
        case .fileURL:
            Image(systemName: "doc.fill")
                .foregroundStyle(.gray)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text(croppedText)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
        case .image:
            VStack(alignment: .leading, spacing: 1) {
                Text("Image")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                Text(relativeDate)
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
        case .fileURL:
            Text(item.previewText)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var relativeDate: String {
        item.copiedAt.formatted(Self.relativeDateStyle)
    }

    private static let relativeDateStyle = Date.RelativeFormatStyle(presentation: .named)
}
