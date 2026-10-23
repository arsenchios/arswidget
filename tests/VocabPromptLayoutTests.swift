// Standalone AppKit regression: compile with the actual VocabPromptCardView.swift.
// Uses an isolated model and a hidden panel, without touching saved user progress.
import AppKit
import SwiftUI

struct VocabWord: Equatable {
    var category: String? = "Вопросы и уточнения"
    var example: String? = "Наві́що це́ потрі́бно?"
    var exampleTranslation: String? = "Зачем это нужно?"
}
enum TestLanguagePack { case ukrainian }
final class VocabManager: ObservableObject {
    static let shared = VocabManager()
    @Published var currentPrompt: VocabWord? = VocabWord()
    var currentPromptPack: TestLanguagePack? = .ukrainian
    var languagePack = TestLanguagePack.ukrainian
    var currentPromptIsGap = false
    var currentPromptIsRuToUk = false
    var currentPromptTextColor = Color.yellow
    var currentAnswerTextColor = Color.blue
    var currentPromptPairColors: (from: Color, to: Color) = (.yellow, .blue)
    var answers: [Bool] = []
    var masteredCount = 0
    var dismissCount = 0
    var reportedHeights: [CGFloat] = []
    func targetLabel(for pack: TestLanguagePack) -> String { "Украинский" }
    func promptText(for word: VocabWord) -> String { "наві́що" }
    func answerText(for word: VocabWord) -> String { "зачем" }
    func dismissPrompt() { dismissCount += 1 }
    func answer(knew: Bool) { answers.append(knew) }
    func markMastered(_ word: VocabWord) { masteredCount += 1 }
}
struct VocabStudySwitch: View {
    let compact: Bool
    var body: some View { Color.clear.frame(width: 57, height: 26) }
}
extension View { func vocabHandCursor() -> some View { self } }

private struct PromptLayoutHarness: View {
    @State private var height: CGFloat = 220
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 32)
            VocabPromptCardView {
                height = $0
                VocabManager.shared.reportedHeights.append($0)
            }
        }
        .frame(width: VocabPromptCardView.width)
        .background(.black)
        .clipShape(NotchShape(topCornerRadius: 19, bottomCornerRadius: 24))
        .frame(height: height + 32, alignment: .top)
        .contentShape(Rectangle())
        .frame(width: 680, height: 900, alignment: .top)
        .compositingGroup()
    }
}

@main
struct VocabPromptLayoutTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 900),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: PromptLayoutHarness())
        panel.contentView = host
        settle(host)
        let initial = buttons(in: host)
        precondition(initial.count == 2, "Expected reveal and exclude buttons")
        assertClickable(initial, in: host)
        // The reveal action is the only medium-width control in this fixture.
        let reveal = initial.first { $0.bounds.width > 100 && $0.bounds.width < 200 }!
        reveal.performClick(nil)
        settle(host)
        let expanded = buttons(in: host)
        precondition(expanded.count == 3, "Expected repeat, recall and exclude buttons")
        assertClickable(expanded, in: host)
        let actions = expanded.filter { $0.bounds.width > 100 && $0.bounds.width < 200 }
            .sorted { $0.convert($0.bounds, to: host).minX < $1.convert($1.bounds, to: host).minX }
        precondition(actions.count == 2)
        actions.forEach { $0.performClick(nil) }
        expanded.first { $0.bounds.width > 250 }!.performClick(nil)
        precondition(VocabManager.shared.answers == [false, true], "Both review actions must reach the model")
        precondition(VocabManager.shared.masteredCount == 1, "Exclude must reach the model")
        let measurements = VocabManager.shared.reportedHeights.count
        VocabManager.shared.currentPrompt = nil
        settle(host)
        precondition(VocabManager.shared.reportedHeights.count == measurements,
                     "Removing the old word must not cache the empty stack height")
        print("Vocab prompt passed: hit testing before/after reveal and all three learning actions")
    }

    @MainActor private static func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
    }

    @MainActor private static func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    @MainActor private static func assertClickable(_ buttons: [NSButton], in host: NSView) {
        for button in buttons {
            let rect = button.convert(button.bounds, to: host.superview)
            for xFraction: CGFloat in [0.25, 0.5, 0.75] {
                let point = NSPoint(x: rect.minX + rect.width * xFraction, y: rect.midY)
                precondition(host.hitTest(point) === button,
                             "Visible button is outside the interactive panel: \(rect), point \(point)")
            }
        }
    }
}
