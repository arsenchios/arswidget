//
//  SessionTimerView.swift
//  ArsWidget
//
//  Added in personal fork: "Сессия" tab (P5 in ROADMAP.md) — a quiet timer
//  for therapy sessions, separate from Pomodoro. Deliberately plain: just a
//  thin progress bar and the time left, no bright colors or glow, so it's
//  easy to glance at without it looking like an alert.
//

import SwiftUI

struct SessionTimerView: View {
    @ObservedObject var timer = SessionTimerManager.shared

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(timer.formattedTimeRemaining)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(Color.white.opacity(timer.isFinished ? 0.75 : 0.55))
                            .frame(width: geo.size.width * min(max(timer.progress, 0), 1))
                            .animation(.easeInOut(duration: 0.4), value: timer.progress)
                    }
                }
                .frame(height: 5)
            }

            HStack(spacing: 12) {
                Button {
                    timer.isRunning ? timer.pause() : timer.start()
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                Button {
                    timer.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .font(.system(size: 14))
        }
        .padding(.horizontal, 8)
    }

    private var statusLabel: String {
        if timer.isFinished { return String(localized: "Время вышло") }
        if timer.isRunning { return String(localized: "Сессия идёт") }
        if timer.secondsRemaining == timer.totalSeconds { return String(localized: "Готово к старту") }
        return String(localized: "На паузе")
    }
}

#Preview {
    SessionTimerView()
        .frame(width: 300, height: 60)
        .background(.black)
}
