import SwiftUI

struct KeepAwakeControlsView: View {
    @ObservedObject var manager = KeepAwakeManager.shared
    private let tint = Color(red: 0.44, green: 0.76, blue: 1)
    static let information = "Временный режим: настройки macOS не меняются. По окончании таймера или при выходе из виджета Mac вернётся к обычным правилам сна. Любой режим можно отменить крестиком. «Не гасить экран» также удерживает Mac от автоматического сна. Закрытие крышки и ручной сон работают как обычно."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Бодрствование").font(.system(size: 12, weight: .semibold))
                Image(systemName: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    .help(Self.information)
                    .accessibilityLabel(Self.information)
                Spacer()
                if manager.errorMessage != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help(manager.errorMessage ?? "")
                }
            }
            ForEach(KeepAwakeMode.allCases) { mode in
                VStack(spacing: 9) {
                    HStack(spacing: 8) {
                        Image(systemName: mode.icon).foregroundStyle(tint)
                            .frame(width: 18)
                        Text(mode.title).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(manager.remainingLabel(for: mode))
                            .font(.system(size: 10, weight: .medium)).monospacedDigit()
                            .foregroundStyle(manager.sessions[mode] == nil ? .white.opacity(0.3) : tint)
                        Button { manager.stop(mode) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                                .foregroundStyle(.white.opacity(manager.sessions[mode] == nil ? 0.15 : 0.5))
                                .frame(width: 22, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(manager.sessions[mode] == nil)
                        .help("Отменить: \(mode.title.lowercased())")
                        .accessibilityLabel("Отменить: \(mode.title.lowercased())")
                    }
                    .help(mode.explanation)
                    HStack(spacing: 8) {
                        ForEach([30, 60, 120], id: \.self) { minutes in
                            let selected = manager.sessions[mode]?.minutes == minutes
                            Button { manager.start(mode, minutes: minutes) } label: {
                                Text(minutes == 30 ? "30 мин" : "\(minutes / 60) ч")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity).frame(height: 34)
                                    .foregroundStyle(selected ? tint : .white.opacity(0.85))
                                    .background(RoundedRectangle(cornerRadius: 10).fill(selected ? tint.opacity(0.16) : .white.opacity(0.055)))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? tint.opacity(0.45) : .white.opacity(0.06), lineWidth: 1))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .help("\(mode.title) на \(minutes) минут. Повторное нажатие начинает отсчёт заново.")
                            .accessibilityLabel("\(mode.title) на \(minutes) минут")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 15).fill(.white.opacity(0.025)))
            }
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}
