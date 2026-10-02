//
//  ClipboardManager.swift
//  ArsWidget
//
//  Added in personal fork: lightweight clipboard text history. Checks
//  NSPasteboard.changeCount once a second (a single integer comparison —
//  effectively free) and only reads the actual clipboard content on the
//  rare occasions it actually changed. Keeps only the last 30 text items,
//  in memory only (no disk writes), so it stays light on lower-end Macs.
//

import Foundation
import AppKit
import Combine
import SwiftUI

struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
}

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var history: [ClipboardItem] = []

    /// Master on/off switch. If this feature ever feels heavy on your
    /// Mac, flip this off in the Clipboard tab — the timer stops
    /// completely (not just hidden), so it truly costs nothing while off.
    @AppStorage("clipboardHistoryEnabled") var isEnabled: Bool = true {
        didSet { restartWatching() }
    }

    private let maxItems = 30
    private let maxItemBytes = 64 * 1024
    private var lastChangeCount: Int
    private var timerCancellable: AnyCancellable?
    private let pasteboard: NSPasteboard
    private var pendingChangeCount: Int?
    private static let remoteClipboard = NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
        restartWatching()
    }

    private func restartWatching() {
        timerCancellable?.cancel()
        guard isEnabled else { return }
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkPasteboard()
            }
    }

    func checkPasteboard() {
        guard isEnabled else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        // Inspect metadata before requesting any payload. Reading a remote
        // string can start a Universal Clipboard transfer before the user pastes.
        // Leave remote items entirely to macOS, including after they arrive.
        guard let types = pasteboard.types, pasteboard.changeCount == changeCount else { return }
        if types.contains(Self.remoteClipboard) {
            lastChangeCount = changeCount
            pendingChangeCount = nil
            return
        }

        // Give promised contents / remote metadata one polling interval to
        // settle. A newer copy supersedes this candidate without being read.
        guard pendingChangeCount == changeCount else {
            pendingChangeCount = changeCount
            return
        }
        guard types.contains(.string) else {
            lastChangeCount = changeCount
            pendingChangeCount = nil
            return
        }
        guard let text = pasteboard.string(forType: .string),
              pasteboard.changeCount == changeCount,
              pasteboard.types?.contains(Self.remoteClipboard) == false else { return }
        lastChangeCount = changeCount
        pendingChangeCount = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard text.lengthOfBytes(using: .utf8) <= maxItemBytes else { return }
        guard history.first?.text != text else { return } // skip immediate duplicates

        history.insert(ClipboardItem(text: text, date: Date()), at: 0)
        if history.count > maxItems {
            history.removeLast(history.count - maxItems)
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
    }

    func clearHistory() {
        history.removeAll()
    }
}
