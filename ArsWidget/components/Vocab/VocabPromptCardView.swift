import SwiftUI

struct VocabPromptCardView: View {
    static let width: CGFloat = 400
    @ObservedObject var vocab = VocabManager.shared
    @State private var revealed = false
    let onSizeChange: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let word = vocab.currentPrompt {
                VStack(spacing: 5) {
                    Text(vocab.currentPromptIsGap ? "Вставь слово или выражение" : "Вспомни перевод")
                    if !vocab.currentPromptIsGap { promptLanguageLine }
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))

                Text(vocab.promptText(for: word))
                    .font(.system(size: vocab.currentPromptIsGap ? 21 : 24, weight: .bold, design: .rounded))
                    .foregroundStyle(vocab.currentPromptIsGap ? vocab.currentAnswerTextColor : vocab.currentPromptTextColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)

                if revealed {
                    Text(vocab.answerText(for: word))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(vocab.currentAnswerTextColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let example = word.example {
                        VStack(spacing: 2) {
                            Text(example).foregroundStyle(.white.opacity(0.9))
                            if let translation = word.exampleTranslation {
                                Text(translation).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Button { vocab.answer(knew: false) } label: {
                            Label("Повторить", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PromptActionButtonStyle(fill: .red.opacity(0.22), stroke: .red.opacity(0.5)))
                        .vocabHandCursor()
                        Button { vocab.answer(knew: true) } label: {
                            Label("Вспомнил", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PromptActionButtonStyle(fill: .green.opacity(0.22), stroke: .green.opacity(0.5)))
                        .vocabHandCursor()
                    }
                    .font(.system(size: 13, weight: .semibold))
                } else {
                    if vocab.currentPromptIsGap, let translation = word.exampleTranslation {
                        Text(translation)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }
                    Button("Показать ответ") {
                        withAnimation(.easeInOut(duration: 0.15)) { revealed = true }
                    }
                    .buttonStyle(PromptSecondaryButtonStyle())
                    .vocabHandCursor()
                    .font(.system(size: 13, weight: .semibold))
                }
                Button { vocab.markMastered(word) } label: {
                    VStack(spacing: 4) {
                        Label("Уже знаю", systemImage: "checkmark.seal")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Больше не спрашивать")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.045)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1))
                }
                    .buttonStyle(VocabNativeButtonStyle())
                    .vocabHandCursor()
                    .foregroundStyle(.white.opacity(0.8))
                    .help("Исключить навсегда. Вернуть можно через «Сбросить прогресс» в списке.")
            }
        }
        // The notch shape also cuts into both edges. Keep the buttons inside
        // those curved sides with room left around the actual visible frame.
        .frame(width: Self.width - 88)
        .padding(.horizontal, 44)
        .padding(.bottom, 24)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { reportHeight(geometry.size.height) }
                .onChange(of: geometry.size.height) { _, height in reportHeight(height) }
        })
        .textSelection(.disabled)
        .onChange(of: vocab.currentPrompt) { _, _ in revealed = false }
    }

    private func reportHeight(_ height: CGFloat) {
        // Delayed removal of a dismissed word must not leave the next card
        // with the height of an empty stack.
        guard vocab.currentPrompt != nil, height > 0 else { return }
        onSizeChange(height)
    }

    private var promptLanguageLine: some View {
        let pack = vocab.currentPromptPack ?? vocab.languagePack
        let colors = vocab.currentPromptPairColors
        let from = vocab.currentPromptIsRuToUk ? "Русский" : vocab.targetLabel(for: pack)
        let to = vocab.currentPromptIsRuToUk ? vocab.targetLabel(for: pack) : "Русский"

        return HStack(spacing: 0) {
            Text("с ")
            Text(from).foregroundStyle(colors.from)
            Text(" на ")
            Text(to).foregroundStyle(colors.to)
        }
    }
}

private struct PromptActionButtonStyle: PrimitiveButtonStyle {
    let fill: Color
    let stroke: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(stroke, lineWidth: 1)
            )
            .foregroundStyle(.white)
            .overlay(VocabNativeClickTarget(action: configuration.trigger))
    }
}

private struct PromptSecondaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .foregroundStyle(.white.opacity(0.9))
            .overlay(VocabNativeClickTarget(action: configuration.trigger))
    }
}

struct VocabNativeButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.overlay(VocabNativeClickTarget(action: configuration.trigger))
    }
}

private struct VocabNativeClickTarget: NSViewRepresentable {
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.click))
        button.isBordered = false
        button.isTransparent = true
        button.setButtonType(.momentaryPushIn)
        button.focusRingType = .none
        // Keep SwiftUI's descriptive accessibility label and action.
        button.setAccessibilityElement(false)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func click() { action() }
    }
}
