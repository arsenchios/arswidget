import SwiftUI

struct FirstRunTourStep {
    let view: NotchViews
    let icon: String
    let title: String
    let text: String
    let location: String
    let accent: Color
    let illustration: Illustration
    enum Illustration { case music, focus, reminders, words, clipboard, shelf, system, awake, keyboard, games }

    static let all: [FirstRunTourStep] = [
        .init(view: .home, icon: "music.note.list", title: "Ваша музыка — рядом",
              text: "Управляйте воспроизведением Apple Music, Spotify и поддерживаемых плееров. Настройте кнопки под себя. Для Apple Music доступна громкость приложения, в том числе выбранной AirPlay-колонки.",
              location: "Вкладка «Музыка» · Настройки → Музыка", accent: .pink, illustration: .music),
        .init(view: .pomodoro, icon: "timer", title: "Одно нажатие — и фокус",
              text: "Выберите длительность и нажмите запуск. Можно начать сразу или выбрать задачу. После работы — перерыв и итог сессии; задачи, журнал и статистика находятся в «Задачи и итоги».",
              location: "Вкладка «Помодоро» · Настройки → Помодоро", accent: .orange, illustration: .focus),
        .init(view: .reminders, icon: "checklist", title: "Дела и привычки",
              text: "Работайте со списками Apple «Напоминания» прямо в виджете. Отмечайте дела и следите за привычками. Для доступа к спискам разрешите приложению пользоваться Напоминаниями.",
              location: "Вкладка «Напоминания»", accent: .orange, illustration: .reminders),
        .init(view: .vocab, icon: "textformat.abc", title: "Языки в своём темпе",
              text: "Готовые наборы: украинский, английский и индонезийский. Включайте нужные по отдельности, выбирайте уровень и интервал карточек. Для другого языка добавьте свои слова и переводы в «Свой набор».",
              location: "Настройки → Словарь · Активные языки", accent: .yellow, illustration: .words),
        .init(view: .clipboard, icon: "doc.on.clipboard", title: "Текст, который уже копировали",
              text: "История запоминает до 30 последних текстов в памяти. Нажмите запись, чтобы скопировать её снова. Фото и файлы не сохраняются в текстовую историю. После выхода из приложения история очищается.",
              location: "Вкладка «Буфер обмена» · переключатель истории", accent: .teal, illustration: .clipboard),
        .init(view: .shelf, icon: "tray.fill", title: "Полка файлов и AirDrop",
              text: "Перетащите файлы на виджет, чтобы держать их под рукой и переносить между приложениями. Через меню «Поделиться» можно отправить их по AirDrop. Полка хранит добавленные файлы; AirDrop — способ отправки, а не отдельное хранилище.",
              location: "Вкладка с лотком · меню файла → Поделиться", accent: .blue, illustration: .shelf),
        .init(view: .systemStats, icon: "gauge", title: "Что происходит на Mac",
              text: "Следите за процессором, памятью и скоростью сети. Нажмите на процессор или память, чтобы увидеть самые затратные приложения. Лимиты AI подключаются отдельно; без подключения показаний не будет.",
              location: "Вкладка «Система» · подключение лимитов AI", accent: .green, illustration: .system),
        .init(view: .systemStats, icon: "moon.zzz", title: "Не засыпать — на время",
              text: "«Не усыплять Mac» оставит задачи работать, даже если экран погаснет. «Не гасить экран» удержит и экран, и Mac от автоматического сна. Выберите 30 минут, час или два; отменить можно крестиком.",
              location: "Система → Бодрствование · подробности под ⓘ", accent: .cyan, illustration: .awake),
        .init(view: .systemStats, icon: "keyboard", title: "Пауза для уборки",
              text: "Режим очистки временно блокирует клавиатуру и трекпад. Если macOS попросит доступ к мониторингу ввода, разрешите его для этой функции. Досрочный выход: Control + Option + Command + K.",
              location: "Система → Очистка клавиатуры", accent: .mint, illustration: .keyboard),
        .init(view: .games, icon: "gamecontroller.fill", title: "Маленький перерыв",
              text: "В виджете есть небольшие игры для короткой паузы. Функции и их параметры можно менять в настройках. Этот тур всегда доступен повторно — не нужно запоминать всё с первого раза.",
              location: "Настройки → Общие → Знакомство → Показать", accent: .purple, illustration: .games)
    ]
}

struct FirstRunTourView: View {
    @EnvironmentObject private var vm: ArsWidgetViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var coordinator = ArsWidgetViewCoordinator.shared
    @State private var index = 0
    @State private var isPaused = false
    @State private var autoplay = true
    init(initialStep: Int = 0) {
        _index = State(initialValue: min(max(0, initialStep), FirstRunTourStep.all.count - 1))
    }
    private var step: FirstRunTourStep { FirstRunTourStep.all[index] }
    private var isLast: Bool { index == FirstRunTourStep.all.count - 1 }
    private struct Playback: Equatable { let index: Int; let enabled: Bool }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: step.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(step.accent)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12).fill(step.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("ЗНАКОМСТВО С ARSWIDGET")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                        .foregroundStyle(.white.opacity(0.35))
                    Text(step.title).font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("\(index + 1) / \(FirstRunTourStep.all.count)")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.35))
            }
            HStack(alignment: .center, spacing: 18) {
                TourIllustrationView(step: step)
                    .frame(width: 158, height: 138)
                    .id(index)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .accessibilityHidden(true)
                Text(step.text)
                    .font(.system(size: 13)).lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(index)
                    .transition(.opacity)
            }
            Text(step.location)
                .font(.system(size: 10, weight: .medium)).foregroundStyle(step.accent.opacity(0.85))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            footer
        }
        .padding(20)
        .frame(maxWidth: 560, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [step.accent.opacity(0.08), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .onAppear(perform: selectStep)
        .onHover { isPaused = $0 }
        // A single cancellable sleep per step; no 20 Hz timer or blur rendering.
        .task(id: Playback(index: index, enabled: autoplay && !isPaused)) {
            guard autoplay, !isPaused else { return }
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(FirstRunTourStep.all.indices, id: \.self) { position in
                    Button { goTo(position) } label: {
                        Capsule().fill(position == index ? step.accent : .white.opacity(position < index ? 0.3 : 0.1))
                            .frame(height: 4).padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Шаг \(position + 1)")
                }
            }
            HStack(spacing: 12) {
                Button("Закрыть") { finish() }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.45))
                Button { autoplay.toggle() } label: {
                    Image(systemName: autoplay ? "pause.circle" : "play.circle")
                        .font(.system(size: 16)).foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help(autoplay ? "Приостановить автоматический показ. При наведении тур также стоит на паузе." : "Включить автоматический показ")
                .accessibilityLabel(autoplay ? "Приостановить тур" : "Продолжить тур")
                Spacer()
                if index > 0 {
                    Button("Назад") { goTo(index - 1) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.65))
                }
                Button { advance() } label: {
                    Text(isLast ? "Готово" : "Дальше")
                        .foregroundStyle(.black).padding(.horizontal, 15).padding(.vertical, 8)
                        .background(Capsule().fill(step.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 12, weight: .medium))
        }
    }

    private func advance() { isLast ? finish() : goTo(index + 1) }
    private func goTo(_ next: Int) {
        guard FirstRunTourStep.all.indices.contains(next) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { index = next }
        selectStep()
    }
    private func selectStep() { coordinator.currentView = step.view; vm.updateOpenSizeIfNeeded() }
    private func finish() { coordinator.finishFirstRunTour(); vm.close() }
}

private struct TourIllustrationView: View {
    let step: FirstRunTourStep
    var body: some View {
        VStack(spacing: 10) {
            switch step.illustration {
            case .music:
                HStack(spacing: 10) {
                    Image(systemName: "music.note").font(.system(size: 26)).frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(step.accent.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ваша музыка").font(.system(size: 10, weight: .semibold))
                        Text("Ваш плеер").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 18) { Image(systemName: "backward.fill"); Image(systemName: "pause.fill"); Image(systemName: "forward.fill") }
            case .focus:
                Text("25:00").font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                Image(systemName: "play.fill").font(.system(size: 14)).foregroundStyle(.black)
                    .frame(width: 34, height: 34).background(Circle().fill(step.accent))
            case .words:
                Text("UK  ·  EN  ·  ID").font(.system(size: 9, weight: .semibold)).foregroundStyle(step.accent)
                Text("наві́що").font(.system(size: 25, weight: .semibold))
                Text("зачем").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            case .reminders:
                sampleRow("checkmark.circle.fill", "Сделать главное")
                sampleRow("circle", "Прогуляться")
                HStack(spacing: 5) { ForEach(0..<7) { day in Circle().fill(step.accent.opacity(day < 4 ? 0.8 : 0.15)).frame(width: 10, height: 10) } }
            case .clipboard:
                sampleRow("doc.on.clipboard", "Нужная мысль")
                sampleRow("doc.text", "Скопированный текст")
                sampleRow("doc.text", "Ещё одна запись")
            case .shelf:
                HStack(spacing: 12) { Image(systemName: "doc.fill"); Image(systemName: "photo.fill"); Image(systemName: "folder.fill") }.font(.system(size: 22))
                Image(systemName: "arrow.down").foregroundStyle(.white.opacity(0.4))
                Label("AirDrop", systemImage: "airplayvideo").font(.system(size: 11, weight: .medium))
            case .system:
                sampleRow("cpu", "Процессор   18%")
                Capsule().fill(step.accent.opacity(0.45)).frame(width: 100, height: 4)
                sampleRow("memorychip", "Память")
                sampleRow("network", "Скорость сети")
            case .awake:
                sampleRow("laptopcomputer", "Mac не уснёт")
                HStack { Text("30 мин"); Text("1 ч"); Text("2 ч") }
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(step.accent)
                sampleRow("display", "Экран включён")
            case .keyboard:
                Image(systemName: "keyboard").font(.system(size: 40, weight: .light))
                Text("Пауза для очистки").font(.system(size: 10))
                Text("⌃ ⌥ ⌘ K").font(.system(size: 12, weight: .medium)).foregroundStyle(step.accent)
            case .games:
                Image(systemName: "gamecontroller.fill").font(.system(size: 38))
                Text("Немного отдохнуть").font(.system(size: 10))
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white.opacity(0.85))
        .background(RoundedRectangle(cornerRadius: 18).fill(step.accent.opacity(0.065)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(step.accent.opacity(0.13), lineWidth: 1))
    }
    private func sampleRow(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(step.accent)
            Text(title).lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }.font(.system(size: 10))
    }
}
