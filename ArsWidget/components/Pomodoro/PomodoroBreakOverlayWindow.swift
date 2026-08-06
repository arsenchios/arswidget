//
//  PomodoroBreakOverlayWindow.swift
//  ArsWidget
//
//  Added in personal fork: full-screen dimming overlay shown during Pomodoro
//  breaks. By default it's purely visual (clicks pass through). Turn on
//  PomodoroManager.lockDuringBreak for "strict mode", where it also blocks
//  clicks/keys so a break is actually enforced.
//

import Cocoa
import SwiftUI

final class PomodoroBreakOverlayWindow: NSPanel {

    convenience init() {
        let screenFrame = NSScreen.main?.frame ?? .zero
        self.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        level = .screenSaver // above regular app windows and the notch window
        alphaValue = 0
        contentView = NSHostingView(rootView: PomodoroBreakOverlayView())
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func showOverlay(blocksInput: Bool) {
        if let screenFrame = NSScreen.main?.frame {
            setFrame(screenFrame, display: true)
        }
        ignoresMouseEvents = !blocksInput
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.6
            animator().alphaValue = 1
        }
    }

    func hideOverlay() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}

private struct PomodoroBreakOverlayView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.85))
                Text(pomodoro.phase == .longBreak ? "Длинный перерыв" : "Перерыв")
                    .font(.title)
                    .bold()
                    .foregroundStyle(.white)
                Text(pomodoro.formattedTimeRemaining)
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Отдохни чуток, разомнись, да завари чаёк")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                Button("Пропустить перерыв") {
                    pomodoro.skip()
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .foregroundStyle(.white.opacity(0.6))
                .underline()
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}
