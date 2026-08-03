//
//  SessionTimerManager.swift
//  ArsWidget
//
//  Added in personal fork: a quiet, standalone timer for therapy sessions
//  (P5 in ROADMAP.md). Unlike PomodoroManager this has no phases, no
//  dimming overlay and no notifications by default — the whole point is to
//  discreetly track session time without drawing attention to the screen.
//  Just one countdown that can be started, paused and reset.
//

import Foundation
import Combine
import SwiftUI
import UserNotifications
import AppKit

@MainActor
final class SessionTimerManager: ObservableObject {
    static let shared = SessionTimerManager()

    @Published private(set) var secondsRemaining: Int
    @Published private(set) var isRunning: Bool = false
    /// True once the countdown has reached zero while running, until reset.
    @Published private(set) var isFinished: Bool = false

    // MARK: Settings (persisted)

    @AppStorage("sessionTimerMinutes") var sessionMinutes: Int = 50 {
        didSet {
            if !isRunning && !isFinished {
                secondsRemaining = sessionMinutes * 60
            }
        }
    }
    // Kept deliberately subtle — a single soft sound at the end, no
    // notification banner by default, so it doesn't pull attention away
    // from a session in progress.
    @AppStorage("sessionTimerChimeEnabled") var chimeEnabled: Bool = true

    private var timerCancellable: AnyCancellable?

    private init() {
        secondsRemaining = 50 * 60
    }

    var totalSeconds: Int {
        max(sessionMinutes * 60, 1)
    }

    var progress: Double {
        1 - (Double(secondsRemaining) / Double(totalSeconds))
    }

    var formattedTimeRemaining: String {
        let s = max(secondsRemaining, 0)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }

    // MARK: Controls

    func start() {
        if isFinished { reset() }
        isRunning = true
        startTicking()
    }

    func pause() {
        isRunning = false
        timerCancellable?.cancel()
    }

    func reset() {
        timerCancellable?.cancel()
        isRunning = false
        isFinished = false
        secondsRemaining = sessionMinutes * 60
    }

    // MARK: Internals

    private func startTicking() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard isRunning else { return }
        if secondsRemaining > 0 {
            secondsRemaining -= 1
        } else {
            finish()
        }
    }

    private func finish() {
        timerCancellable?.cancel()
        isRunning = false
        isFinished = true
        if chimeEnabled {
            NSSound(named: "Tink")?.play()
        }
    }
}
