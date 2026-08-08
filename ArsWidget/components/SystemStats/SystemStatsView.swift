//
//  SystemStatsView.swift
//  ArsWidget
//
//  Added in personal fork: "Система" tab — CPU and memory usage at a
//  glance, so you can see if something's eating resources when you have
//  a lot of windows open.
//

import AppKit
import SwiftUI

struct SystemStatsView: View {
    @EnvironmentObject private var vm: ArsWidgetViewModel
    @ObservedObject var stats = SystemStatsManager.shared
    @ObservedObject private var aiUsage = AIUsageManager.shared
    @ObservedObject private var keyboardCleaner = KeyboardCleaningManager.shared
    @AppStorage("arswidgetDonationURL") private var donationURL = "https://app.lava.top/products/56eaa216-818d-458d-89ae-d3bc00c91247/5d9fb0e3-8189-49ad-8ddb-79dfb628d7e0?currency=USD"
    @AppStorage("arswidgetServicesURL") private var servicesURL = ""
    @State private var showFeedback = false
    @State private var feedbackText = ""
    @State private var feedbackContact = ""
    @State private var feedbackKind = "idea"
    @State private var feedbackState: FeedbackState = .idle
    @State private var copiedFeedback = false

    private enum FeedbackState { case idle, sending, sent, failed }
    @State private var showLinkSetupMessage = false
    @State private var showCleaningPermissionMessage = false
    @State private var showCleaningStartFailure = false
    @State private var showAILimitsSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: $stats.isEnabled) {
                    Text("Мониторинг системы")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Spacer()

                Stepper("каждые \(stats.intervalSeconds) сек", value: $stats.intervalSeconds, in: 1...30)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            if stats.isEnabled {
                statRow(
                    label: String(localized: "ЦП"),
                    icon: "cpu",
                    valueText: String(format: "%.0f%%", stats.usage.cpuPercent),
                    fraction: stats.usage.cpuPercent / 100,
                    color: color(for: stats.usage.cpuPercent)
                )

                statRow(
                    label: String(localized: "Память"),
                    icon: "memorychip",
                    valueText: String(
                        format: String(localized: "%.1f / %.0f ГБ"),
                        stats.usage.memoryUsedGB, stats.usage.memoryTotalGB
                    ),
                    fraction: stats.usage.memoryUsedPercent / 100,
                    color: color(for: stats.usage.memoryUsedPercent)
                )
            } else {
                Text("Мониторинг выключен")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Divider()
                .overlay(Color.white.opacity(0.12))

            aiLimitsSection

            Divider()
                .overlay(Color.white.opacity(0.12))

            cleaningControls

            Divider()
                .overlay(Color.white.opacity(0.12))

            HStack(spacing: 8) {
                Button {
                    SettingsWindowController.shared.showWindow()
                } label: {
                    Label("Настройки", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showFeedback = true
                } label: {
                    Label("Предложить улучшение", systemImage: "lightbulb")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)

                Button {
                    withAnimation(.smooth) {
                        stats.showSupport.toggle()
                    }
                } label: {
                    Label("Поддержать", systemImage: "heart.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if stats.showSupport {
                supportPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .onChange(of: stats.showSupport) {
            vm.updateOpenSizeIfNeeded()
        }
        .onChange(of: showAILimitsSetup) { _, isVisible in
            stats.isAILimitsSetupVisible = isVisible
            vm.updateOpenSizeIfNeeded()
        }
        .onChange(of: aiUsage.connectedMetrics.count) {
            // A limit that appears (or drops out) changes how tall the tab is.
            vm.updateOpenSizeIfNeeded()
        }
        .onChange(of: showFeedback) { _, isPresented in
            vm.isModalInteractionActive = isPresented
            if isPresented {
                feedbackState = .idle
                copiedFeedback = false
            }
        }
        .onDisappear {
            vm.isModalInteractionActive = false
            stats.isAILimitsSetupVisible = false
        }
        .popover(isPresented: $showFeedback, arrowEdge: .bottom) {
            feedbackPopover
        }
        .alert("Ссылка появится перед релизом", isPresented: $showLinkSetupMessage) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Сначала подключим публичные ссылки LavaTop и услуг автора.")
        }
        .alert("Нужен доступ к управлению компьютером", isPresented: $showCleaningPermissionMessage) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("macOS попросит разрешение «Универсальный доступ». Без него нельзя временно блокировать клавиатуру.")
        }
        .alert("Не удалось включить режим очистки", isPresented: $showCleaningStartFailure) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Проверь разрешение «Универсальный доступ» для ArsWidget в Системных настройках.")
        }
    }

    private var aiLimitsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label("Лимиты AI", systemImage: "chart.bar.xaxis")
                    .font(.caption.weight(.semibold))

                if let freshness = aiUsage.freshnessText {
                    Text(freshness)
                        .font(.caption2)
                        .foregroundStyle(aiUsage.isStale ? Color.orange : Color.white.opacity(0.4))
                        .help(aiUsage.isStale
                              ? Text("Chrome давно не присылал новые значения")
                              : Text("Когда значения обновлялись в последний раз"))
                }

                Spacer(minLength: 0)

                if aiUsage.hasData {
                    Toggle("Показывать сверху", isOn: $aiUsage.showInClosedNotch)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }

            let connected = aiUsage.connectedMetrics

            if connected.isEmpty {
                aiLimitsConnectButton
            } else {
                ForEach(connected) { metric in
                    aiLimitRow(metric)
                }

                let missing = aiUsage.missingProviders
                if !missing.isEmpty {
                    Text("Ещё можно подключить: \(missing.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if showAILimitsSetup {
                aiLimitsSetupPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var aiLimitsConnectButton: some View {
        Button {
            withAnimation(.smooth) {
                showAILimitsSetup.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 13, weight: .medium))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Подключить лимиты AI")
                        .font(.caption.weight(.semibold))
                    Text("Claude, Codex, DeepSeek, Gemini")
                        .font(.caption2)
                }
                Spacer(minLength: 0)
                Image(systemName: showAILimitsSetup ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func aiLimitRow(_ metric: AIUsageMetric) -> some View {
        let value = aiUsage.value(for: metric) ?? 0
        let fraction = min(max(value / 100, 0), 1)
        // Nearly-exhausted limits go red; everything else keeps the vendor
        // colour so a row stays recognisable at a glance.
        let accent = AIUsageManager.isLow(value) ? Color.red : metric.tint
        let dimmed = aiUsage.isStale

        return HStack(spacing: 7) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)

            Text(metric.title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(dimmed ? 0.45 : 0.75))

            Spacer(minLength: 6)

            // Slim remaining-bar, same visual language as the CPU/memory rows.
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(accent.opacity(dimmed ? 0.4 : 1))
                    .frame(width: 46 * fraction)
                    .animation(.easeInOut(duration: 0.4), value: fraction)
            }
            .frame(width: 46, height: 4)

            Text("\(Int(value.rounded()))%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(accent.opacity(dimmed ? 0.5 : 1))
                .frame(width: 36, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }

    private var cleaningControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(keyboardCleaner.isActive ? .orange : .white.opacity(0.8))

            VStack(alignment: .leading, spacing: 2) {
                Text(keyboardCleaner.isActive ? "Идёт очистка" : "Очистить клавиатуру")
                    .font(.caption.weight(.semibold))
                Text(keyboardCleaner.isActive
                     ? "Ввод вернётся через \(keyboardCleaner.secondsRemaining) с"
                     : "Блокирует клавиатуру и трекпад на 30 секунд")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Spacer(minLength: 0)

            if keyboardCleaner.isActive {
                Text("⌃⌥⌘K")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Button("Начать") {
                    startKeyboardCleaning()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func startKeyboardCleaning() {
        Task {
            let authorized = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            guard authorized else {
                showCleaningPermissionMessage = true
                return
            }
            if !keyboardCleaner.start() {
                showCleaningStartFailure = true
            }
        }
    }

    private func statRow(label: String, icon: String, valueText: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                        .animation(.easeInOut(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 5)
        }
    }

    private func color(for percent: Double) -> Color {
        switch percent {
        case ..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    private var feedbackPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Предложить улучшение")
                .font(.title3.bold())

            Text("Напишите любую идею, проблему или пожелание. Я читаю все предложения и добавляю полезные улучшения в ArsWidget.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $feedbackKind) {
                Text("Идея").tag("idea")
                Text("Проблема").tag("bug")
                Text("Отзыв").tag("review")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextEditor(text: $feedbackText)
                .font(.body)
                .frame(width: 420, height: 130)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            TextField("Как ответить — почта или телеграм (необязательно)", text: $feedbackContact)
                .textFieldStyle(.roundedBorder)

            Text("Отправляется только текст сообщения и версия приложения.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                switch feedbackState {
                case .sending:
                    ProgressView().controlSize(.small)
                case .sent:
                    Label("Отправлено, спасибо", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failed:
                    // Nothing typed is ever lost: it goes to the clipboard so
                    // it can be sent by hand.
                    Label("Не удалось отправить — текст скопирован", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .idle:
                    if copiedFeedback {
                        Text("Скопировано").font(.caption).foregroundStyle(.green)
                    }
                }

                Spacer(minLength: 0)

                Button("Закрыть") {
                    showFeedback = false
                }

                Button("Отправить") {
                    submitFeedback()
                }
                .buttonStyle(.borderedProminent)
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
                          || feedbackState == .sending)
            }

            Divider()

            HStack(spacing: 8) {
                Text("ArsWidget бесплатный. Поддержка помогает делать его дальше.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Поддержать") { openSupportPage() }
                    .controlSize(.small)
            }
        }
        .padding(18)
        .frame(width: 456)
    }

    private func submitFeedback() {
        let text = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        feedbackState = .sending

        Task {
            let delivered = await AppTelemetryManager.shared.sendFeedback(
                kind: feedbackKind,
                message: text,
                contact: feedbackContact
            )
            feedbackState = delivered ? .sent : .failed
            if delivered {
                feedbackText = ""
                feedbackContact = ""
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if feedbackState == .sent { showFeedback = false }
            } else {
                copyFeedback()
            }
        }
    }

    private func copyFeedback() {
        let text = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedFeedback = true
    }

    private func openSupportPage() {
        guard let url = URL(string: donationURL),
              url.scheme?.lowercased() == "https"
        else {
            showLinkSetupMessage = true
            return
        }
        NSWorkspace.shared.open(url)
    }

    private var aiLimitsSetupPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Два шага")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    withAnimation(.smooth) { showAILimitsSetup = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 5) {
                setupStep(1, "Поставь расширение ArsWidget для Chrome")
                setupStep(2, "Открой страницы Usage и закрепи вкладки")
            }

            Button {
                openExtensionStore()
            } label: {
                Label("Установить расширение", systemImage: "puzzlepiece.extension")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Label("Только проценты. Без паролей, cookies и переписок — всё остаётся на этом Mac.", systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func setupStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 15, height: 15)
                .background(Color.white.opacity(0.12), in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openExtensionStore() {
        guard let url = URL(string: "https://chromewebstore.google.com/search/ArsWidget%20AI%20Limits"),
              url.scheme?.lowercased() == "https"
        else { return }
        NSWorkspace.shared.open(url)
    }

    private var supportPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Поддержать разработчика")
                .font(.headline)

            Text("ArsWidget бесплатный и открытый. Поддержка помогает быстрее реализовывать пожелания и улучшения.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Можно поддержать проект напрямую или выбрать услугу автора в Telegram.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                supportButton(
                    "Поддержать ArsWidget",
                    icon: "heart.fill",
                    url: donationURL
                )
                supportButton(
                    "Услуги автора в Telegram",
                    icon: "paperplane.fill",
                    url: servicesURL
                )
            }

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/arsenchios/arswidget")!)
                } label: {
                    Label("Поставить звезду на GitHub", systemImage: "star")
                }
                .buttonStyle(.link)

                Button {
                    showFeedback = true
                } label: {
                    Label("Предложить улучшение", systemImage: "lightbulb")
                }
                .buttonStyle(.link)
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func supportButton(_ title: LocalizedStringKey, icon: String, url: String) -> some View {
        Button {
            guard let destination = URL(string: url),
                  let scheme = destination.scheme?.lowercased(),
                  ["https", "tg"].contains(scheme)
            else {
                showLinkSetupMessage = true
                return
            }
            NSWorkspace.shared.open(destination)
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

#Preview {
    SystemStatsView()
        .frame(width: 260, height: 100)
        .background(.black)
}
