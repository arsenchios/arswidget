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
    private let pasteboard = NSPasteboard.general

    private init() {
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

    private func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string) else { return }
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
