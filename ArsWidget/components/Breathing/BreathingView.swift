//
//  BreathingView.swift
//  ArsWidget
//
//  Added in personal fork: a small breathing-exercise widget — a circle
//  that smoothly grows on inhale and shrinks on exhale (4s in / 4s hold /
//  4s out). No timers polling in the background — it only animates while
//  actively started, using SwiftUI's own GPU-composited animations plus a
//  couple of scheduled callbacks per cycle, so it's effectively free when
//  idle.
//

import SwiftUI

private enum BreathPhase {
    case inhale, hold, exhale
}

struct BreathingView: View {
    @State private var isActive = false
    @State private var phase: BreathPhase = .inhale
    @State private var scale: CGFloat = 0.62

    private let inhaleSeconds: Double = 4
    private let holdSeconds: Double = 4
    private let exhaleSeconds: Double = 4

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.6), Color.blue.opacity(0.12)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 32
                        )
                    )
                    .frame(width: 56, height: 56)
                    .scaleEffect(scale)
                    .blur(radius: 1.5)

                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    .frame(width: 56, height: 56)
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 6) {
                Text(isActive ? phaseLabel : "Дыхательная пауза")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: phase)
                    .animation(.easeInOut(duration: 0.3), value: isActive)

                Button {
                    isActive ? stop() : start()
                } label: {
                    Image(systemName: isActive ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .font(.system(size: 14))
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .onDisappear { stop() }
    }

    private var phaseLabel: String {
        switch phase {
        case .inhale: return "Вдох..."
        case .hold: return "Задержи"
        case .exhale: return "Выдох..."
        }
    }

    private func start() {
        isActive = true
        runInhale()
    }

    private func stop() {
        isActive = false
        withAnimation(.easeInOut(duration: 0.6)) { scale = 0.62 }
    }

    private func runInhale() {
        guard isActive else { return }
        phase = .inhale
        withAnimation(.easeInOut(duration: inhaleSeconds)) { scale = 1.15 }
        DispatchQueue.main.asyncAfter(deadline: .now() + inhaleSeconds) {
            runHold()
        }
    }

    private func runHold() {
        guard isActive else { return }
        phase = .hold
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) {
            runExhale()
        }
    }

    private func runExhale() {
        guard isActive else { return }
        phase = .exhale
        withAnimation(.easeInOut(duration: exhaleSeconds)) { scale = 0.62 }
        DispatchQueue.main.asyncAfter(deadline: .now() + exhaleSeconds) {
            runInhale()
        }
    }
}

#Preview {
    BreathingView()
        .frame(width: 300, height: 80)
        .background(.black)
}
