//
//  ClipboardSettings.swift
//  boringNotch
//
//  Created by Tudor Sandu on 2026-08-07.
//

import Defaults
import SwiftUI

struct ClipboardSettings: View {
    @ObservedObject private var manager = ClipboardManager.shared
    @Default(.enableClipboardHistory) private var enableClipboardHistory
    @Default(.clipboardHistoryLimit) private var historyLimit
    @State private var confirmationPresented = false

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableClipboardHistory) {
                    Text("Enable clipboard history")
                }
                .onChange(of: enableClipboardHistory) { _, enabled in
                    if enabled {
                        manager.start()
                    } else {
                        manager.stop()
                    }
                }

                Picker("History limit", selection: $historyLimit) {
                    Text("10 items").tag(10)
                    Text("25 items").tag(25)
                    Text("50 items").tag(50)
                    Text("100 items").tag(100)
                }
                .disabled(!enableClipboardHistory)
            } header: {
                Text("General")
            } footer: {
                Text("Copied text, images and files are captured when the clipboard changes. The clipboard history panel opens with ⌘⇧C.")
            }

            Section {
                HStack {
                    Text("Stored items")
                    Spacer()
                    Text("\(manager.items.count)")
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    confirmationPresented = true
                } label: {
                    Text("Clear history")
                }
                .disabled(manager.items.isEmpty)
                .confirmationDialog(
                    "Clear all clipboard history?",
                    isPresented: $confirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button("Clear history", role: .destructive) {
                        manager.clear()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Clipboard")
    }
}
