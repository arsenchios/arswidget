import AppKit

final class PromisedText: NSObject, NSPasteboardItemDataProvider {
    var reads = 0
    var text = "promised text"
    var onRead: (() -> Void)?
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        reads += 1
        onRead?()
        item.setString(text, forType: type)
    }
}

@main struct ClipboardManagerTests {
    @MainActor static func wait(_ seconds: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.contains("--test-worker") {
            ClipboardWorker.run(board: NSPasteboard(name: .init(args[args.firstIndex(of: "--test-worker")! + 1])), previousChangeCount: ClipboardWorker.previousChangeCount)
            return
        }
        if args.contains("--stalled-worker") {
            ClipboardWorker.emit(ClipboardReadEvent(kind: "busy"))
            Thread.sleep(forTimeInterval: 40)
            return
        }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let reader = ClipboardTextReader(board: board)
        let provider = PromisedText()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        item.setData(Data(), forType: .init("com.apple.is-remote-clipboard"))
        board.clearContents(); board.writeObjects([item])
        let count = board.changeCount
        precondition(reader.readChange().text == "promised text", "Remote text must join automatic history")
        precondition(reader.readChange().kind == "idle" && provider.reads == 1, "One read per generation")
        precondition(board.changeCount == count, "Capturing must never write back")

        for kind in [NSPasteboard.PasteboardType.png, .tiff, .fileURL,
                     .init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType")] {
            let excluded = PromisedText()
            let entry = NSPasteboardItem()
            entry.setDataProvider(excluded, forTypes: [.string, kind])
            board.clearContents(); board.writeObjects([entry])
            let before = board.changeCount
            precondition(reader.readChange().text == nil && excluded.reads == 0, "Images/files/private data must not be requested")
            precondition(board.changeCount == before)
        }
        let replaced = PromisedText()
        replaced.onRead = { board.clearContents(); board.setString("new copy", forType: .string) }
        let stale = NSPasteboardItem()
        stale.setDataProvider(replaced, forTypes: [.string])
        board.clearContents(); board.writeObjects([stale])
        precondition(reader.readChange().text == nil, "Discard data superseded during transfer")
        precondition(reader.readChange().text == "new copy")

        let manager = ClipboardManager(pasteboard: board, startAutomatically: false, workerExecutable: nil)
        manager.isEnabled = false // No subprocess in this pure storage test.
        manager.isEnabled = true
        manager.stopWatching()
        for index in 0..<40 { manager.remember("text \(index)") }
        precondition(manager.history.count == 30 && manager.history.first?.text == "text 39")
        manager.remember("text 39")
        precondition(manager.history.count == 30)
        manager.remember(String(repeating: "x", count: 65537))
        precondition(manager.history.first?.text == "text 39")
        manager.clearHistory()
        for index in 0..<30 { manager.remember("\(index)" + String(repeating: "x", count: 60000)) }
        precondition(manager.history.reduce(0, { $0 + $1.text.utf8.count }) <= 512 * 1024)
        let saved = manager.history[0]
        let beforeClear = board.changeCount
        manager.clearHistory()
        precondition(board.changeCount == beforeClear)
        manager.copyToClipboard(saved)
        precondition(board.string(forType: .string) == saved.text)
        manager.isEnabled = false
        manager.remember("disabled")
        precondition(manager.history.isEmpty)

        // Exercise the actual process/pipe/JSON path, using only a unique board.
        let automatic = ClipboardManager(pasteboard: board, workerExecutable: URL(fileURLWithPath: CommandLine.arguments[0]), workerArguments: ["--test-worker", board.name.rawValue])
        automatic.isEnabled = true
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        board.clearContents(); board.setString("automatic child capture", forType: .string)
        let automaticCount = board.changeCount
        precondition(wait(5) { automatic.history.first?.text == "automatic child capture" }, "Child reader must capture automatically")
        precondition(board.changeCount == automaticCount)
        let remoteProvider = PromisedText()
        remoteProvider.text = "iPhone promised text"
        let remoteItem = NSPasteboardItem()
        remoteItem.setDataProvider(remoteProvider, forTypes: [.string])
        remoteItem.setData(Data(), forType: .init("com.apple.is-remote-clipboard"))
        board.clearContents(); board.writeObjects([remoteItem])
        let remoteCount = board.changeCount
        precondition(wait(5) { automatic.history.first?.text == "iPhone promised text" })
        precondition(remoteProvider.reads == 1 && board.changeCount == remoteCount)
        // The original system representation remains independently pasteable.
        precondition(board.string(forType: .string) == "iPhone promised text")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        board.clearContents(); board.setString("copied during sleep", forType: .string)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(wait(7) { automatic.history.first?.text == "copied during sleep" }, "Wake must resume and capture the latest generation")
        automatic.isEnabled = false
        board.clearContents(); board.setString("after disabled", forType: .string)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        precondition(automatic.history.first?.text == "copied during sleep")

        let stalled = ClipboardManager(pasteboard: board, workerExecutable: URL(fileURLWithPath: CommandLine.arguments[0]), workerArguments: ["--stalled-worker"])
        stalled.isEnabled = true
        precondition(wait(11) { stalled.captureMessage?.contains("приостановлена") == true }, "Watchdog must stop an unresponsive reader")
        stalled.isEnabled = false
        print("Automatic clipboard regression passed: remote text, untouched photos/files, no capture writes, bounds, subprocess IPC, off switch and hung-reader watchdog")
    }
}
