//
//  SettingsView.swift
//  ArsWidget
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab = "General"
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil, initialTab: String = "General") {
        self.updaterController = updaterController
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label("Общие", systemImage: "gear")
                }
                NavigationLink(value: "Media") {
                    Label("Музыка", systemImage: "play.laptopcomputer")
                }
                NavigationLink(value: "Calendar") {
                    Label("Календарь", systemImage: "calendar")
                }
                NavigationLink(value: "Vocab") {
                    Label("Словарь", systemImage: "text.book.closed")
                }
                NavigationLink(value: "Pomodoro") {
                    Label("Помодоро", systemImage: "timer")
                }
                NavigationLink(value: "About") {
                    Label("О приложении", systemImage: "info.circle")
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Media":
                    Media()
                case "Calendar":
                    CalendarSettings()
                case "Vocab":
                    VocabSettings()
                case "Pomodoro":
                    PomodoroSettings()
                case "About":
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        About(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                default:
                    GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }
}

struct GeneralSettings: View {
    @ObservedObject var coordinator = ArsWidgetViewCoordinator.shared

    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.openNotchOnHover) var openNotchOnHover


    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Показывать значок в строке меню")
                }
                .tint(.effectiveAccent)
                LaunchAtLogin.Toggle("Запускать при входе в macOS")
            } header: {
                Text("Системные функции")
            }

            NotchBehaviour()
        }
        .toolbar {
            Button("Закрыть приложение") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Общие")
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Открывать при наведении")
            }
            Toggle("Запоминать последнюю вкладку", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Задержка наведения")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Поведение виджета")
        }
    }
}

struct Charge: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("Показывать индикатор батареи")
                }
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Показывать уведомления о питании")
                }
            } header: {
                Text("Общее")
            }
            Section {
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("Показывать процент заряда")
                }
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("Показывать значки состояния питания")
                }
            } header: {
                Text("Информация о батарее")
            }
        }
        .onAppear {
            Task { @MainActor in
                await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Батарея")
    }
}

struct HUD: View {
    @EnvironmentObject var vm: ArsWidgetViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @ObservedObject var coordinator = ArsWidgetViewCoordinator.shared
    @State private var accessibilityAuthorized = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Заменить системные индикаторы")
                            .font(.headline)
                        Text("Заменяет стандартные индикаторы громкости, яркости экрана и клавиатуры в macOS.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!accessibilityAuthorized)
                }

                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Для замены системных индикаторов нужен доступ «Универсальный доступ».")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Запросить доступ") {
                                XPCHelperClient.shared.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 6)
                }
            }

            Section {
                Picker("Действие с клавишей Option", selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }

                Picker("Стиль шкалы", selection: $enableGradient) {
                    Text("Однотонный")
                        .tag(false)
                    Text("Градиент")
                        .tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Включить свечение")
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Окрашивать шкалу акцентным цветом")
                }
            } header: {
                Text("Общее")
            }
            .disabled(!hudReplacement)

            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text("Показывать индикатор в открытом виджете")
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text("Показывать процент")
                }
                .disabled(!Defaults[.showOpenNotchHUD])
            } header: {
                HStack {
                    Text("Открытый виджет")
                    customBadge(text: "Beta")
                }
            }
            .disabled(!hudReplacement)

            Section {
                Picker("Стиль индикатора", selection: $inlineHUD) {
                    Text("Обычный")
                        .tag(false)
                    Text("В строке")
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }

                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("Показывать процент")
                }
            } header: {
                Text("Свёрнутый виджет")
            }
            .disabled(!Defaults[.hudReplacement])
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Индикаторы")
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = ArsWidgetViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics

    var body: some View {
        Form {
            Section {
                Picker("Источник музыки", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Источник")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("Для YouTube Music нужно установить стороннее приложение: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)  // Ensures it's visibly a link
                    }
                } else {
                    Text(
                        "«Сейчас играет» работает со всеми музыкальными приложениями."
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }

            Section {
                Toggle(
                    "Показывать музыку в свёрнутом виджете",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("Показывать карточку при смене трека", isOn: $enableSneakPeek)
                Picker("Стиль карточки", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Скрывать после бездействия")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") сек.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker(
                    selection: $hideNotchOption,
                    label:
                        HStack {
                            Text("Поведение в полноэкранном режиме")
                        }
                ) {
                    Text("Скрывать для всех приложений").tag(HideNotchOption.always)
                    Text("Скрывать только для плеера").tag(
                        HideNotchOption.nowPlayingOnly)
                    Text("Не скрывать").tag(HideNotchOption.never)
                }
            } header: {
                Text("Музыка в свёрнутом виджете")
            }

            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text("Показывать текст песни под исполнителем")
                    }
                }
            } header: {
                Text("Управление музыкой")
            }  footer: {
                Text("Выбери элементы управления в плеере. Громкость разворачивается при использовании.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Музыка")
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

// Added in personal fork: editable Pomodoro settings.
struct PomodoroSettings: View {
    @AppStorage("pomodoroWorkMinutes") private var workMinutes: Int = 25
    @AppStorage("pomodoroShortBreakMinutes") private var shortBreakMinutes: Int = 5
    @AppStorage("pomodoroLongBreakMinutes") private var longBreakMinutes: Int = 15
    @AppStorage("pomodoroSessionsBeforeLongBreak") private var sessionsBeforeLongBreak: Int = 4
    @AppStorage("pomodoroDimOnBreak") private var dimOnBreak: Bool = true
    @AppStorage("pomodoroLockDuringBreak") private var lockDuringBreak: Bool = false
    @AppStorage("pomodoroSoundEnabled") private var soundEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                Stepper("Работа: \(workMinutes) мин", value: $workMinutes, in: 5...90, step: 5)
                Stepper("Короткий перерыв: \(shortBreakMinutes) мин", value: $shortBreakMinutes, in: 1...30)
                Stepper("Длинный перерыв: \(longBreakMinutes) мин", value: $longBreakMinutes, in: 5...45, step: 5)
                Stepper("Долгий перерыв каждые \(sessionsBeforeLongBreak) сессий", value: $sessionsBeforeLongBreak, in: 2...8)
            } header: {
                Text("Длительность")
            }
            Section {
                Toggle("Затемнять экран на перерыве", isOn: $dimOnBreak)
                Toggle("Строгий режим (блокирует клики на перерыве)", isOn: $lockDuringBreak)
                    .disabled(!dimOnBreak)
                Toggle("Звук при смене фазы", isOn: $soundEnabled)
            } header: {
                Text("Перерыв")
            } footer: {
                Text("Строгий режим не даёт кликать по другим окнам, пока перерыв не закончится — включай, если короткие перерывы обычно пропускаешь.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Помодоро")
    }
}

struct VocabSettings: View {
    @ObservedObject private var vocab = VocabManager.shared
    @AppStorage("vocabPauseInFullscreen") private var pauseInFullscreen = true
    @State private var sourceWord = ""
    @State private var translatedWord = ""

    var body: some View {
        Form {
            Section {
                Toggle("Включить карточки слов", isOn: $vocab.isEnabled)
                Stepper("Показывать каждые \(vocab.intervalMinutes) мин", value: $vocab.intervalMinutes, in: 1...120)
                Toggle("Не показывать в полноэкранном режиме", isOn: $pauseInFullscreen)
                Toggle("Автоматически пополнять очередь", isOn: $vocab.autoFillEnabled)
                Stepper("Слов в очереди каждого языка: \(vocab.activeTarget)", value: $vocab.activeTarget, in: 3...20)
                Picker("Направление", selection: Binding(get: { vocab.direction }, set: { vocab.direction = $0 })) {
                    ForEach(VocabDirection.allCases) { direction in
                        Text(vocab.directionLabel(direction)).tag(direction)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Активные языки")
                        .font(.headline)

                    ForEach(VocabLanguagePack.allCases) { pack in
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(isOn: Binding(
                                get: { vocab.isPackEnabled(pack) },
                                set: { vocab.setPackEnabled(pack, enabled: $0) }
                            )) {
                                HStack {
                                    Text(vocab.title(for: pack))
                                    Spacer()
                                    Text("\(vocab.activeCount(for: pack)) из \(vocab.activeTarget) в очереди")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if pack != .custom {
                                Picker("Уровень", selection: Binding(
                                    get: { vocab.selectedLevel(for: pack) },
                                    set: { vocab.setSelectedLevel($0, for: pack) }
                                )) {
                                    ForEach(VocabLevel.allCases) { level in
                                        Text("\(level.rawValue) — \(level.subtitle)").tag(level)
                                    }
                                }
                                .pickerStyle(.menu)
                                Text("В базе \(vocab.totalPackCount(for: pack)) слов · на повторении \(vocab.reviewCount(for: pack))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Словарь")
            } footer: {
                Text("Очередь пополняется следующими словами выбранного уровня. Выученное слово возвращается на повторение через 3 дня или после 10 новых слов — что наступит раньше.")
            }

            Section {
                Picker("Редактируемый язык", selection: Binding(get: { vocab.languagePack }, set: { vocab.languagePack = $0 })) {
                    ForEach(VocabLanguagePack.allCases) { pack in
                        Text(vocab.title(for: pack)).tag(pack)
                    }
                }

                Text("\(vocab.sourceLanguageLabel) → \(vocab.targetLanguageLabel)")
                    .foregroundStyle(.secondary)

                if vocab.languagePack == .custom {
                    TextField(
                        "Название языка или набора",
                        text: Binding(get: { vocab.customPackName }, set: { vocab.customPackName = $0 })
                    )
                    Text("Можно учить не только язык: добавь термины, фразы, названия или любые пары «вопрос — ответ».")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("Слово или фраза", text: $sourceWord)
                    TextField("Перевод", text: $translatedWord)
                    Button("Добавить") {
                        vocab.addWord(ru: sourceWord, uk: translatedWord)
                        sourceWord = ""
                        translatedWord = ""
                    }
                    .disabled(sourceWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || translatedWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Ручной ввод")
            }

            Section {
                Button("Показать слово сейчас") {
                    vocab.showRandomWord()
                }
                .disabled(!vocab.isEnabled || vocab.totalActiveCount == 0)

                Text("Сейчас активно \(vocab.totalActiveCount) слов")
                    .foregroundStyle(.secondary)

                Text("Можно учить языки, термины и фразы. Для наполнения попроси нейросеть выдать пары в формате: слово — перевод, затем добавь нужные пары сюда.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Быстрое действие")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Словарь")
    }
}

// Added in personal fork: editable Session Timer settings (P5 in ROADMAP.md).
struct SessionTimerSettings: View {
    @AppStorage("sessionTimerMinutes") private var sessionMinutes: Int = 50
    @AppStorage("sessionTimerChimeEnabled") private var chimeEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                Stepper("Длительность сессии: \(sessionMinutes) мин", value: $sessionMinutes, in: 10...120, step: 5)
            } header: {
                Text("Длительность")
            } footer: {
                Text("По умолчанию 50 минут — стандартная длительность терапевтической сессии.")
            }
            Section {
                Toggle("Тихий сигнал по окончании", isOn: $chimeEnabled)
            } header: {
                Text("Звук")
            } footer: {
                Text("Один негромкий системный звук в конце, без уведомлений на экране — чтобы не отвлекать во время сессии.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Сессия")
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent

    var body: some View {
        Form {
            Defaults.Toggle(key: .showCalendar) {
                Text("Показывать календарь")
            }
            Defaults.Toggle(key: .hideCompletedReminders) {
                Text("Скрывать выполненные напоминания")
            }
            Defaults.Toggle(key: .hideAllDayEvents) {
                Text("Скрывать события на весь день")
            }
            Defaults.Toggle(key: .autoScrollToNextEvent) {
                Text("Автопрокрутка к следующему событию")
            }
            Defaults.Toggle(key: .showFullEventTitles) {
                Text("Всегда показывать полные названия")
            }
            Section(header: Text("Календари")) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text("Нет доступа к календарям. Разреши его в настройках macOS.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Открыть настройки календаря") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                        }
                    }
                }
            }
            Section(header: Text("Напоминания")) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text("Нет доступа к напоминаниям. Разреши его в настройках macOS.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Открыть настройки напоминаний") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Календарь")
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0,0,0,0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Название сборки")
                        Spacer()
                        Text(Defaults[.releaseName])
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Версия")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "неизвестно")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("О версии")
                }

                UpdaterSettingsView(updater: updaterController.updater)

                Text("ArsWidget проверяет обновления автоматически. Когда новая версия готова, приложение предложит скачать её и перезапуститься.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        if let url = URL(string: "https://github.com/arsenchios/arswidget") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            VStack(spacing: 0) {
                Divider()
                Text("Сделано с заботой для ArsWidget")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
            //            Button("Welcome window") {
            //                openWindow(id: "onboarding")
            //            }
            //            .controlSize(.extraLarge)
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("О приложении")
    }
}

struct Shelf: View {

    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .shelfEnabled) {
                    Text("Включить полку файлов")
                }
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Открывать полку, если есть файлы")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Расширенная область перетаскивания")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Копировать файлы при перетаскивании")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Убирать файлы с полки после перетаскивания")
                }

            } header: {
                HStack {
                    Text("Общее")
                }
            }

            Section {
                Picker("Сервис быстрой отправки", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(width: 16, height: 16)
                            .foregroundColor(.accentColor)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)

                if let selectedProvider = selectedProvider {
                    HStack {
                        Group {
                            if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(width: 16, height: 16)
                        .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Выбрано: \(selectedProvider.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Файлы с полки будут отправляться через этот сервис")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Providers are always enabled; user can pick default service above.

            } header: {
                HStack {
                    Text("Быстрая отправка")
                }
            } footer: {
                Text("Выбери сервис для отправки файлов с полки. Нажми кнопку полки, чтобы выбрать файлы, или перетащи их на неё.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Файлы")
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = ArsWidgetViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor
    var body: some View {
        Form {
            Section {
                Toggle("Всегда показывать вкладки", isOn: $coordinator.alwaysShowTabs)

            } header: {
                Text("Общее")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Цветной эквалайзер")
                }
                Defaults
                    .Toggle("Тонировать плеер цветом обложки", key: .playerColorTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Размывать фон за обложкой")
                }
                Picker("Цвет ползунка", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
            } header: {
                Text("Музыка")
            }

            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Включить зеркало")
                }
                    .disabled(!checkVideoInput())
                Picker("Форма зеркала", selection: $mirrorShape) {
                    Text("Круг")
                        .tag(MirrorShapeEnum.circle)
                    Text("Квадрат")
                        .tag(MirrorShapeEnum.rectangle)
                }
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Показывать анимацию лица в ожидании")
                }
            } header: {
                HStack {
                    Text("Дополнительно")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Внешний вид")
    }

    func checkVideoInput() -> Bool {
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }

        return false
    }
}

struct Advanced: View {
    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.hideFromScreenRecording) var hideFromScreenRecording
    @ObservedObject private var telemetry = AppTelemetryManager.shared

    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil
    // macOS accent colors
    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"

        var id: String { self.rawValue }

        var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Знакомство с приложением")
                        Text("Короткий тур по вкладкам: что где лежит и зачем нужно.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Показать") {
                        ArsWidgetViewCoordinator.shared.replayFirstRunTour()
                    }
                }
            } header: {
                Text("Знакомство")
            }

            Section {
                Toggle(isOn: $telemetry.isEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Анонимная статистика использования")
                        Text("Раз в сутки уходит версия ArsWidget, версия macOS и сколько раз открывали каждую вкладку. Без имени, без содержимого заметок, буфера и словаря.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Приватность")
            }

            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Toggle between system and custom
                    Picker("Акцентный цвет", selection: $useCustomAccentColor) {
                        Text("Системный").tag(false)
                        Text("Свой").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if !useCustomAccentColor {
                        // System accent info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                AccentCircleButton(
                                    isSelected: true,
                                    color: .accentColor,
                                    isSystemDefault: true
                                ) {}

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Системный акцентный цвет")
                                        .font(.body)
                                    Text("Используется цвет из настроек macOS")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        // Custom color options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Готовые цвета")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                ForEach(PresetAccentColor.allCases) { preset in
                                    AccentCircleButton(
                                        isSelected: selectedPresetColor == preset,
                                        color: preset.color,
                                        isMulticolor: false
                                    ) {
                                        selectedPresetColor = preset
                                        customAccentColor = preset.color
                                        saveCustomColor(preset.color)
                                        forceUiUpdate()
                                    }
                                }
                                Spacer()
                            }

                            Divider()
                                .padding(.vertical, 4)

                            // Custom color picker
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Выбрать цвет")
                                        .font(.body)
                                    Text("Можно выбрать любой цвет")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                ColorPicker(selection: Binding(
                                    get: { customAccentColor },
                                    set: { newColor in
                                        customAccentColor = newColor
                                        selectedPresetColor = nil
                                        saveCustomColor(newColor)
                                        forceUiUpdate()
                                    }
                                ), supportsOpacity: false) {
                                    ZStack {
                                        Circle()
                                            .fill(customAccentColor)
                                            .frame(width: 32, height: 32)

                                        if selectedPresetColor == nil {
                                            Circle()
                                                .strokeBorder(.primary.opacity(0.3), lineWidth: 2)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Акцентный цвет")
            } footer: {
                Text("Используй системный акцентный цвет или выбери свой.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .onAppear {
                initializeAccentColorState()
            }

            Section {
                Defaults.Toggle(key: .enableShadow) {
                    Text("Показывать тень окна")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Скруглять углы при расширении")
                }
            } header: {
                Text("Окно")
            }

            Section {
                Defaults.Toggle(key: .hideTitleBar) {
                    Text("Скрыть строку заголовка")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Показывать виджет на экране блокировки")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Скрывать при записи экрана")
                }
            } header: {
                Text("Поведение окна")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Дополнительно")
        .onAppear {
            loadCustomColor()
        }
    }

    private func forceUiUpdate() {
        // Force refresh the UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }

    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }

    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)

            // Check if loaded color matches a preset
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }

    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)

        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }

    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil // Multicolor is selected when useCustomAccentColor is false
        } else {
            loadCustomColor()
        }
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)

                // Subtle border
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)

                // Apple-style highlight ring around the middle when selected
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "Использовать акцентный цвет macOS" : "")
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Показать карточку трека:", name: .toggleSneakPeek)
            } header: {
                Text("Музыка")
            } footer: {
                Text(
                    "Карточка трека ненадолго показывает название и исполнителя под виджетом."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Открыть или закрыть виджет:", name: .toggleNotchOpen)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Клавиши")
    }
}

func proFeatureBadge() -> some View {
    Text("Перейти на Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).stroke(
                Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Скоро")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    HUD()
}
