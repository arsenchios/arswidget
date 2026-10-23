// Clipboard reads run in a disposable process. Only an explicit history-row
// click writes to the system pasteboard; capture never takes ownership of it.
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
    @Published private(set) var captureMessage: String?
    @AppStorage("clipboardAutomaticHistoryV2Enabled") var isEnabled: Bool = true {
        willSet { objectWillChange.send() }
        didSet { if isEnabled { startWatching() } else { stopWatching(); lastObservedChange = nil } }
    }

    private let maxItems = 30
    private let maxHistoryBytes = 512 * 1024
    private let executable: URL?
    private let arguments: [String]
    private let injectedPasteboard: NSPasteboard?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var generation = UUID()
    private var lastReply = Date()
    private var lastObservedChange: Int?
    private var retryAfter = Date.distantPast
    private var watchdog: Timer?
    private var observers: [AnyCancellable] = []
    private enum PauseReason: Hashable { case sleep, display, session, lock }
    private var pauses: Set<PauseReason> = []
    private var suspended: Bool { !pauses.isEmpty }

    init(pasteboard: NSPasteboard? = nil, startAutomatically: Bool = true,
         workerExecutable: URL? = Bundle.main.url(forAuxiliaryExecutable: "ArsWidgetClipboardReader"),
         workerArguments: [String] = [ClipboardWorker.argument]) {
        injectedPasteboard = pasteboard
        executable = workerExecutable
        arguments = workerArguments
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "clipboardAutomaticHistoryV2Enabled") == nil {
            let previous = defaults.object(forKey: "clipboardManualHistoryEnabled") as? Bool ?? true
            defaults.set(previous, forKey: "clipboardAutomaticHistoryV2Enabled")
        }
        defaults.set(false, forKey: "clipboardHistoryEnabled")
        guard startAutomatically else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let transitions: [(Notification.Name, PauseReason, Bool)] = [
            (NSWorkspace.willSleepNotification, .sleep, true),
            (NSWorkspace.didWakeNotification, .sleep, false),
            (NSWorkspace.screensDidSleepNotification, .display, true),
            (NSWorkspace.screensDidWakeNotification, .display, false),
            (NSWorkspace.sessionDidResignActiveNotification, .session, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .session, false)
        ]
        for (name, reason, paused) in transitions {
            workspace.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in
                self?.setPaused(reason, paused)
            }.store(in: &observers)
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.publisher(for: .init("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.setPaused(.lock, true) }.store(in: &observers)
        distributed.publisher(for: .init("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.setPaused(.lock, false) }.store(in: &observers)
        startWatching()
    }

    private func setPaused(_ reason: PauseReason, _ paused: Bool) {
        if paused {
            pauses.insert(reason)
            stopWatching()
        } else {
            pauses.remove(reason)
            guard !suspended else { return }
            retryAfter = Date().addingTimeInterval(3)
            startWatching()
        }
    }

    private func startWatching() {
        guard isEnabled, !suspended, watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkWorker() }
        }
        if let watchdog { RunLoop.main.add(watchdog, forMode: .common) }
        checkWorker()
    }

    private func checkWorker() {
        guard isEnabled, !suspended else { return }
        if let process, process.isRunning {
            guard Date().timeIntervalSince(lastReply) > 8 else { return }
            stopWorker()
            retryAfter = Date().addingTimeInterval(30)
            captureMessage = "Передача занята — история ненадолго приостановлена"
            return
        }
        guard Date() >= retryAfter, let executable else { return }
        stopWorker()
        let task = Process()
        let pipe = Pipe()
        let control = Pipe()
        let token = UUID()
        generation = token
        task.executableURL = executable
        task.arguments = arguments + (lastObservedChange.map { ["--after-change-count", String($0)] } ?? [])
        task.standardOutput = pipe
        task.standardInput = control
        task.standardError = FileHandle.nullDevice
        task.qualityOfService = .utility
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.receive(data)
            }
        }
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.stopWorker()
                self.retryAfter = Date().addingTimeInterval(30)
            }
        }
        process = task
        output = pipe
        input = control
        lastReply = Date()
        do {
            try task.run()
            // Only the child's inherited descriptor may keep stdin alive.
            try? control.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        } catch {
            stopWorker()
            retryAfter = Date().addingTimeInterval(30)
            captureMessage = "Не удалось запустить историю буфера"
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        guard buffer.count <= 512 * 1024 else { stopWorker(); retryAfter = Date().addingTimeInterval(30); return }
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let event = try? JSONDecoder().decode(ClipboardReadEvent.self, from: line) else { continue }
            // A hung read emits busy once, then no replies. It cannot keep
            // extending its own deadline while blocked in the system provider.
            lastReply = Date()
            if let count = event.changeCount { lastObservedChange = count }
            if event.kind == "text", isEnabled, let text = event.text {
                remember(text)
            } else if event.kind == "idle" {
                captureMessage = nil
            }
        }
    }

    func remember(_ text: String) {
        guard isEnabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= ClipboardTextReader.maxItemBytes else { return }
        guard history.first?.text != text else { return }
        history.insert(ClipboardItem(text: text, date: Date()), at: 0)
        while history.count > maxItems || history.reduce(0, { $0 + $1.text.utf8.count }) > maxHistoryBytes {
            history.removeLast()
        }
        captureMessage = nil
    }

    private func stopWorker() {
        generation = UUID()
        output?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        try? input?.fileHandleForWriting.close()
        try? output?.fileHandleForReading.close()
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process = nil
        input = nil
        output = nil
        buffer.removeAll(keepingCapacity: false)
    }

    func stopWatching() {
        watchdog?.invalidate()
        watchdog = nil
        stopWorker()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let board = injectedPasteboard ?? .general
        board.clearContents()
        board.setString(item.text, forType: .string)
    }

    func clearHistory() {
        stopWorker()
        lastObservedChange = nil
        history.removeAll()
        captureMessage = nil
    }
}
