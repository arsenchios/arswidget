import Foundation

@main
struct VocabPromptPresentationTests {
    static func main() {
        var availability = VocabSessionAvailability()
        precondition(availability.permitsPrompts)
        precondition(availability.setSuspended(.screensAsleep, suspended: true))
        precondition(!availability.setSuspended(.screensAsleep, suspended: true))
        precondition(!availability.setSuspended(.systemAsleep, suspended: true))
        precondition(!availability.setSuspended(.screenLocked, suspended: true))
        precondition(!availability.setSuspended(.systemAsleep, suspended: false))
        precondition(!availability.setSuspended(.screensAsleep, suspended: false))
        precondition(!availability.permitsPrompts, "Unlock must also finish before resuming")
        precondition(availability.setSuspended(.screenLocked, suspended: false))
        precondition(availability.permitsPrompts)
        precondition(!availability.setSuspended(.systemAsleep, suspended: false))
        var state = VocabPromptPresentation()
        precondition(state.synchronize(visible: false, hasWord: false, windowWasOpen: false) == nil)
        for _ in 0..<50 {
            precondition(state.synchronize(visible: true, hasWord: true, windowWasOpen: false) == .present)
            precondition(state.synchronize(visible: true, hasWord: true, windowWasOpen: true) == nil)
            precondition(state.synchronize(visible: false, hasWord: true, windowWasOpen: true) == .fold)
            precondition(!state.isPresented)
            // Delayed removal of the old text must not reopen an empty card.
            precondition(state.synchronize(visible: false, hasWord: false, windowWasOpen: false) == nil)
        }
        precondition(state.synchronize(visible: true, hasWord: true, windowWasOpen: true) == .present)
        precondition(state.synchronize(visible: false, hasWord: true, windowWasOpen: true) == .restoreOpen)
        precondition(state.synchronize(visible: true, hasWord: true, windowWasOpen: false) == .present)
        // Text disappearing independently of the flag must still dismiss.
        precondition(state.synchronize(visible: true, hasWord: false, windowWasOpen: true) == .fold)
        precondition(state.synchronize(visible: true, hasWord: true, windowWasOpen: false) == .present)
        state.cancel()
        precondition(state.synchronize(visible: false, hasWord: true, windowWasOpen: false) == nil)
        // A new prompt during the previous fold starts a fresh presentation.
        precondition(state.synchronize(visible: true, hasWord: true, windowWasOpen: false) == .present)
        precondition(state.synchronize(visible: false, hasWord: true, windowWasOpen: true) == .fold)
        print("Vocab presentation lifecycle passed: 50 cycles, restoration, manual close and missing text")
    }
}
