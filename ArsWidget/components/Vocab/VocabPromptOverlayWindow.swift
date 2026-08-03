//
//  VocabPromptOverlayWindow.swift
//  ArsWidget
//
//  Added in personal fork: small floating card near the top of the screen
//  that shows the current vocab word. Unlike the Pomodoro break overlay,
//  this one is small and never blocks clicks outside its own card.
//

import Cocoa
import Defaults
import SwiftUI

@MainActor
final class VocabPromptOverlayWindow: NSPanel {
    private let promptSize = CGSize(width: 320, height: 228)

    convenience init() {
        let size = CGSize(width: 320, height: 228)
        let origin = Self.defaultOrigin(for: size)

        self.init(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        level = .floating
        alphaValue = 0
        contentView = NSHostingView(rootView: VocabPromptCardView())
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        setFrameOrigin(Self.defaultOrigin(for: promptSize))
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.orderOut(nil)
            }
        })
    }

    private static func defaultOrigin(for size: CGSize) -> CGPoint {
        let appDelegate = NSApp.delegate as? AppDelegate
        let coordinator = ArsWidgetViewCoordinator.shared

        let targetViewModel: ArsWidgetViewModel? = {
            if Defaults[.showOnAllDisplays] {
                let uuid = coordinator.selectedScreenUUID
                return appDelegate?.viewModels[uuid]
            }
            return appDelegate?.vm
        }()

        let screenUUID = targetViewModel?.screenUUID ?? coordinator.selectedScreenUUID
        let screenFrame = getScreenFrame(screenUUID) ?? NSScreen.main?.frame ?? .zero
        let gap: CGFloat = 10
        let y: CGFloat

        if let targetViewModel, targetViewModel.notchState == .open {
            y = screenFrame.maxY - targetViewModel.notchSize.height - size.height - gap
        } else {
            y = screenFrame.maxY - size.height - 6
        }

        return CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: y
        )
    }
}

private struct VocabPromptCardView: View {
    @ObservedObject var vocab = VocabManager.shared
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 10) {
            if let word = vocab.currentPrompt {
                VStack(spacing: 2) {
                    Text("Переведи")
                    Text(vocab.currentPromptInstructionDetail)
                }
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

                Text(vocab.promptText(for: word))
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(vocab.currentPromptAccent)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if revealed {
                    Text(vocab.answerText(for: word))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(vocab.currentPromptAccent)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        Button {
                            vocab.answer(knew: false)
                            revealed = false
                        } label: {
                            Label("Не знаю", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PromptActionButtonStyle(fill: Color.red.opacity(0.22), stroke: Color.red.opacity(0.5)))

                        Button {
                            vocab.answer(knew: true)
                            revealed = false
                        } label: {
                            Label("Знаю", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PromptActionButtonStyle(fill: Color.green.opacity(0.22), stroke: Color.green.opacity(0.5)))
                    }
                    .font(.system(size: 14, weight: .semibold))

                    Button("Уже выучил") {
                        vocab.markMastered(word)
                        revealed = false
                    }
                    .buttonStyle(PromptSecondaryButtonStyle())
                    .font(.system(size: 12, weight: .medium))
                } else {
                    Button("Показать перевод") {
                        withAnimation(.easeInOut(duration: 0.2)) { revealed = true }
                    }
                    .buttonStyle(PromptSecondaryButtonStyle())
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 8)
                }
            }
        }
        .padding(18)
        .frame(width: 320, height: 228)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.92))
        )
        .onChange(of: vocab.currentPrompt) { _, _ in
            revealed = false
        }
    }
}

private struct PromptActionButtonStyle: ButtonStyle {
    let fill: Color
    let stroke: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(configuration.isPressed ? fill.opacity(0.7) : fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(stroke, lineWidth: 1)
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PromptSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .foregroundStyle(.white.opacity(0.9))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
