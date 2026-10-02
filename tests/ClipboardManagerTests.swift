import AppKit

final class PromisedText: NSObject, NSPasteboardItemDataProvider {
    var reads = 0
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        reads += 1
        item.setString("remote payload", forType: type)
    }
}

@main
struct ClipboardManagerTests {
    @MainActor static func main() {
        // A private pasteboard keeps the user's clipboard and Handoff untouched.
        let board = NSPasteboard(name: .init("ArsWidget.Tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: board)
        manager.isEnabled = true
        func copy(_ text: String, remote: Bool = false) {
            board.clearContents()
            board.setString(text, forType: .string)
            if remote { board.setData(Data(), forType: .init("com.apple.is-remote-clipboard")) }
        }
        copy("local")
        let count = board.changeCount
        manager.checkPasteboard()
        precondition(manager.history.isEmpty, "Wait for stable metadata")
        manager.checkPasteboard()
        precondition(manager.history.first?.text == "local")
        precondition(board.changeCount == count, "Polling must never write")
        copy("iPhone", remote: true)
        let remoteCount = board.changeCount
        for _ in 0..<4 { manager.checkPasteboard() }
        precondition(manager.history.count == 1, "Remote clipboard must be ignored")
        precondition(board.changeCount == remoteCount)
        precondition(board.string(forType: .string) == "iPhone")
        let provider = PromisedText()
        let promised = NSPasteboardItem()
        promised.setDataProvider(provider, forTypes: [.string])
        promised.setData(Data(), forType: .init("com.apple.is-remote-clipboard"))
        board.clearContents()
        board.writeObjects([promised])
        for _ in 0..<4 { manager.checkPasteboard() }
        precondition(provider.reads == 0, "Remote payload must never be requested")
        precondition(manager.history.count == 1)
        copy("metadata still arriving")
        manager.checkPasteboard()
        board.setData(Data(), forType: .init("com.apple.is-remote-clipboard"))
        manager.checkPasteboard(); manager.checkPasteboard()
        precondition(manager.history.count == 1, "Late remote metadata must cancel capture")
        copy("superseded")
        manager.checkPasteboard()
        copy("newest")
        manager.checkPasteboard()
        manager.checkPasteboard()
        precondition(manager.history.map(\.text) == ["newest", "local"])
        copy("newest")
        manager.checkPasteboard(); manager.checkPasteboard()
        precondition(manager.history.count == 2)
        copy(String(repeating: "x", count: 65537))
        manager.checkPasteboard(); manager.checkPasteboard()
        precondition(manager.history.count == 2)
        manager.clearHistory()
        precondition(board.string(forType: .string)?.count == 65537, "Clearing history must not clear clipboard")
        print("Clipboard regression checks passed")
    }
}
