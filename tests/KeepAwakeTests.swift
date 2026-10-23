import AppKit
import IOKit.pwr_mgt

private final class Assertions: KeepAwakeAssertionProviding {
    var created: [(KeepAwakeMode, TimeInterval)] = []
    var released: [IOPMAssertionID] = []
    var fails = false
    func create(mode: KeepAwakeMode, seconds: TimeInterval) -> IOPMAssertionID? {
        created.append((mode, seconds))
        return fails ? nil : IOPMAssertionID(created.count)
    }
    func release(_ id: IOPMAssertionID) { released.append(id) }
}

@main struct KeepAwakeTests {
    @MainActor static func main() {
        var now = Date(timeIntervalSince1970: 1_000)
        let assertions = Assertions()
        let manager = KeepAwakeManager(assertions: assertions, now: { now }, schedulesTimer: false)
        precondition(manager.sessions.isEmpty)
        manager.start(.system, minutes: 1)
        precondition(assertions.created.isEmpty, "Unsupported duration must not create an assertion")
        manager.start(.system, minutes: 30)
        manager.start(.display, minutes: 60)
        precondition(manager.sessions.count == 2 && assertions.created[0].1 == 1800 && assertions.created[1].1 == 3600)
        manager.start(.system, minutes: 120)
        precondition(assertions.released == [1], "Replacing a timer must release its previous assertion")
        precondition(manager.sessions[.display]?.assertionID == 2)
        now = now.addingTimeInterval(3600)
        manager.refresh()
        precondition(manager.sessions[.display] == nil && manager.remainingLabel(for: .system) == "Ещё 60 мин")
        precondition(assertions.released == [1, 2])
        now = now.addingTimeInterval(3600)
        manager.refresh()
        precondition(manager.sessions.isEmpty && assertions.released == [1, 2, 3])
        manager.stopAll()
        precondition(assertions.released.count == 3, "Expired assertions must not be released twice")
        manager.start(.system, minutes: 30)
        manager.start(.display, minutes: 30)
        manager.stop(.system)
        precondition(manager.sessions.count == 1 && manager.sessions[.display] != nil)
        manager.stopAll()
        precondition(manager.sessions.isEmpty && Set(assertions.released).count == 5)
        assertions.fails = true
        manager.start(.display, minutes: 60)
        precondition(manager.sessions.isEmpty && manager.errorMessage != nil)

        // Exercise the actual OS backend with a one-second deadline. Inspect
        // only our own assertion; no system preferences or other apps change.
        let native = SystemKeepAwakeAssertions()
        for mode in KeepAwakeMode.allCases {
            guard let id = native.create(mode: mode, seconds: 1) else { fatalError("IOPM assertion creation failed") }
            defer { native.release(id) }
            func level() -> Int? {
                guard let properties = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as NSDictionary? else { return nil }
                return (properties[kIOPMAssertionLevelKey] as? NSNumber)?.intValue
            }
            precondition(level() == kIOPMAssertionLevelOn, "Native assertion did not activate")
            let deadline = Date().addingTimeInterval(6)
            func timedOut() -> Bool {
                let properties = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as NSDictionary?
                return properties?["AssertTimedOutWhen"] is Date
            }
            while !timedOut() && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            // CopyProperties retains the original level on this macOS; the
            // OS-owned timeout date proves the TurnOff action has fired.
            precondition(timedOut(), "Native assertion must time out without a UI timer")
        }
        print("KeepAwake passed: validation, independent modes, replacement, expiry, cancellation, failure and native OS timeouts")
    }
}
