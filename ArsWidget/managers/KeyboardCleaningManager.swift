//
//  KeyboardCleaningManager.swift
//  ArsWidget
//
//  A short, reversible input lock for safely cleaning the keyboard and trackpad.
//

import AppKit
import SwiftUI

final class KeyboardCleaningManager: ObservableObject {
    static let shared = KeyboardCleaningManager()

    enum StartResult {
        case started
        case inputMonitoringRequired
        case eventTapUnavailable
    }

    @Published private(set) var isActive = false
    @Published private(set) var secondsRemaining = 0

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var countdownTimer: Timer?
    private var overlayWindows: [KeyboardCleaningOverlayWindow] = []

    private init() {}

    deinit {
        stop()
    }

    @discardableResult
    func start(duration: Int = 30) -> StartResult {
        guard !isActive else { return .started }

        // A CGEvent tap on current macOS needs Input Monitoring. Request it
        // explicitly so the app appears in the right Privacy pane instead of
        // reporting the unrelated Accessibility permission as the problem.
        guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else {
            return .inputMonitoringRequired
        }

        let mask = eventMask
        guard let tap = CGEvent.tapCreate(
            // .cghidEventTap is reserved for root processes and returned nil
            // for ArsWidget even when Accessibility was enabled. A session tap
            // is the supported level for a normal desktop app.
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return .eventTapUnavailable
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)

        secondsRemaining = max(5, duration)
        isActive = true
        showOverlays()
        startCountdown()
        return .started
    }

    func stop() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil

        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        secondsRemaining = 0
        isActive = false
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.secondsRemaining <= 1 {
                self.stop()
            } else {
                self.secondsRemaining -= 1
            }
        }
        if let countdownTimer {
            RunLoop.main.add(countdownTimer, forMode: .common)
        }
    }

    private func showOverlays() {
        overlayWindows = NSScreen.screens.map { screen in
            let window = KeyboardCleaningOverlayWindow(screen: screen)
            window.orderFrontRegardless()
            return window
        }
    }

    private var eventMask: CGEventMask {
        let events: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .mouseMoved, .leftMouseDragged,
            .rightMouseDragged, .otherMouseDragged,
            .scrollWheel
        ]
        return events.reduce(CGEventMask(0)) { mask, event in
            mask | (CGEventMask(1) << CGEventMask(event.rawValue))
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<KeyboardCleaningManager>.fromOpaque(userInfo).takeUnretainedValue()
        return manager.handleEvent(type: type, event: event)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Control-Option-Command-K is deliberately the only manual way out so
        // ordinary cleaning does not accidentally cancel the mode.
        if type == .keyDown,
           event.getIntegerValueField(.keyboardEventKeycode) == 40,
           event.flags.contains([.maskControl, .maskCommand, .maskAlternate]) {
            DispatchQueue.main.async { [weak self] in
                self?.stop()
            }
        }

        return nil
    }
}

private final class KeyboardCleaningOverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        level = .screenSaver
        contentView = NSHostingView(rootView: KeyboardCleaningOverlayView())
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct KeyboardCleaningOverlayView: View {
    @ObservedObject private var cleaner = KeyboardCleaningManager.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(.white)

                Text("Режим очистки")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text("Клавиатура и трекпад временно отключены")
                    .foregroundStyle(.white.opacity(0.7))

                Text(timeText)
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text("Ввод включится автоматически")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))

                Text("Аварийный выход: ⌃⌥⌘K")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(36)
        }
    }

    private var timeText: String {
        String(format: "0:%02d", cleaner.secondsRemaining)
    }
}
