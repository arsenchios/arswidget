//
//  VocabManager.swift
//  ArsWidget
//
//  Added in personal fork: a small "learn Ukrainian words" feature.
//  You pick which words to study from a built-in list (checkboxes in
//  VocabView), and every N minutes one of your active words pops up in a
//  small card near the notch. Mark "Знаю" / "Не знаю" — words you don't
//  know yet get shown more often, words you know well fade out (a simple
//  Leitner-box style spaced repetition: 5 levels, 0 = brand new,
//  4 = mastered and stops appearing).
//
//  Everything is stored in UserDefaults as plain JSON — no database, no
//  disk polling, and the background timer only fires once every few
//  minutes, so this is effectively free while idle.
//

import Foundation
import SwiftUI
import Combine

struct VocabWord: Identifiable, Codable, Equatable {
    var id: String { ru }
    let ru: String
    let uk: String
    var isActive: Bool = false
    var isCustom: Bool = false
    /// Simple Leitner box: 0 = new/hard, 4 = mastered (stops showing).
    var box: Int = 0
    var timesShown: Int = 0
    var timesKnown: Int = 0
}

enum VocabDirection: String, CaseIterable, Identifiable {
    case ruToUk = "RU → UK"
    case ukToRu = "UK → RU"
    case mixed = "Вперемешку"
    var id: String { rawValue }
}

enum VocabLanguagePack: String, CaseIterable, Identifiable {
    case ukrainian
    case english
    case indonesian
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ukrainian: return String(localized: "Украинский")
        case .english: return String(localized: "Английский")
        case .indonesian: return String(localized: "Индонезийский")
        case .custom: return String(localized: "Свой набор")
        }
    }

    var sourceCode: String { "RU" }

    var targetCode: String {
        switch self {
        case .ukrainian: return "UK"
        case .english: return "EN"
        case .indonesian: return "ID"
        case .custom: return "СВОЁ"
        }
    }

    var sourceLabel: String { String(localized: "Русский") }

    var targetLabel: String {
        switch self {
        case .ukrainian: return String(localized: "Украинский")
        case .english: return String(localized: "Английский")
        case .indonesian: return String(localized: "Индонезийский")
        case .custom: return String(localized: "Свой набор")
        }
    }
}

@MainActor
final class VocabManager: ObservableObject {
    static let shared = VocabManager()

    @Published private(set) var words: [VocabWord] = []
    @Published private(set) var currentPrompt: VocabWord?
    @Published private(set) var currentPromptPack: VocabLanguagePack?
    @Published private(set) var currentPromptIsRuToUk: Bool = true
    @Published var showPromptOverlay: Bool = false

    @AppStorage("vocabEnabled") var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                ensureStarterWordsIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self, self.isEnabled, self.totalActiveCount > 0, self.currentPrompt == nil else { return }
                    self.showRandomWord()
                }
            } else {
                dismissPrompt()
            }
            restartTimer()
        }
    }
    @AppStorage("vocabIntervalMinutes") var intervalMinutes: Int = 10 {
        didSet { restartTimer() }
    }
    @AppStorage("vocabDirectionRaw") private var directionRaw: String = VocabDirection.ruToUk.rawValue
    @AppStorage("vocabLanguagePackRaw") private var languagePackRaw: String = VocabLanguagePack.ukrainian.rawValue {
        didSet {
            dismissPrompt()
            loadWords()
            restartTimer()
        }
    }
    @AppStorage("vocabEnabledLanguagePacksRaw") private var enabledLanguagePacksRaw: String = VocabLanguagePack.ukrainian.rawValue {
        didSet {
            dismissPrompt()
            ensureStarterWordsIfNeeded()
            restartTimer()
        }
    }
    @AppStorage("vocabCustomPackName") var customPackName: String = "Свой набор" {
        didSet { objectWillChange.send() }
    }

    var direction: VocabDirection {
        get { VocabDirection(rawValue: directionRaw) ?? .ruToUk }
        set { directionRaw = newValue.rawValue }
    }

    var languagePack: VocabLanguagePack {
        get { VocabLanguagePack(rawValue: languagePackRaw) ?? .ukrainian }
        set { languagePackRaw = newValue.rawValue }
    }

    var enabledPacks: [VocabLanguagePack] {
        enabledLanguagePacksRaw
            .split(separator: ",")
            .compactMap { VocabLanguagePack(rawValue: String($0)) }
    }

    var sourceLanguageLabel: String { languagePack.sourceLabel }
    var targetLanguageLabel: String { targetLabel(for: languagePack) }
    var currentPromptInstructionDetail: String {
        let pack = currentPromptPack ?? languagePack
        let label = targetLabel(for: pack)
        let source = currentPromptIsRuToUk ? "русского" : label.lowercased()
        let target = currentPromptIsRuToUk ? label.lowercased() : "русский"
        return "с \(source) на \(target)"
    }

    func title(for pack: VocabLanguagePack) -> String {
        pack == .custom ? targetLabel(for: pack) : pack.title
    }

    func targetLabel(for pack: VocabLanguagePack) -> String {
        guard pack == .custom else { return pack.targetLabel }
        let name = customPackName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Свой набор" : name
    }

    var currentPromptAccent: Color {
        switch currentPromptPack ?? languagePack {
        case .ukrainian:
            return Color(red: 0.91, green: 0.70, blue: 0.22)
        case .english:
            return Color(red: 0.29, green: 0.60, blue: 0.91)
        case .indonesian:
            return Color(red: 0.84, green: 0.35, blue: 0.34)
        case .custom:
            return Color(red: 0.45, green: 0.72, blue: 0.65)
        }
    }

    func promptText(for word: VocabWord) -> String {
        displayText(currentPromptIsRuToUk ? word.ru : word.uk)
    }

    func answerText(for word: VocabWord) -> String {
        displayText(currentPromptIsRuToUk ? word.uk : word.ru)
    }

    var totalActiveCount: Int {
        enabledPacks.reduce(0) { $0 + activeCount(for: $1) }
    }

    func directionLabel(_ direction: VocabDirection) -> String {
        directionLabel(direction, for: languagePack)
    }

    func directionLabel(_ direction: VocabDirection, for pack: VocabLanguagePack) -> String {
        switch direction {
        case .ruToUk:
            return "\(pack.sourceCode) → \(pack.targetCode)"
        case .ukToRu:
            return "\(pack.targetCode) → \(pack.sourceCode)"
        case .mixed:
            return String(localized: "Вперемешку")
        }
    }

    private var timerCancellable: AnyCancellable?
    private lazy var overlay = VocabPromptOverlayWindow()

    private init() {
        loadWords()
        restartTimer()
    }

    var activeCount: Int { words.filter { $0.isActive }.count }
    var visibleWords: [VocabWord] { words.filter { $0.box < 4 || $0.isActive } }

    func activeCount(for pack: VocabLanguagePack) -> Int {
        loadWords(for: pack).filter(\.isActive).count
    }

    func isPackEnabled(_ pack: VocabLanguagePack) -> Bool {
        enabledPacks.contains(pack)
    }

    func setPackEnabled(_ pack: VocabLanguagePack, enabled: Bool) {
        var packs = enabledPacks
        if enabled {
            if !packs.contains(pack) {
                packs.append(pack)
            }
        } else {
            packs.removeAll { $0 == pack }
        }
        enabledLanguagePacksRaw = packs.map(\.rawValue).joined(separator: ",")
    }

    // MARK: Word list management

    func setActive(_ word: VocabWord, active: Bool) {
        guard let idx = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[idx].isActive = active
        saveWords()
    }

    func addWord(ru: String, uk: String) {
        let ru = ru.trimmingCharacters(in: .whitespacesAndNewlines)
        let uk = uk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ru.isEmpty, !uk.isEmpty else { return }

        if let idx = words.firstIndex(where: { $0.ru.caseInsensitiveCompare(ru) == .orderedSame }) {
            words[idx].isActive = true
            words[idx].box = min(words[idx].box, 3)
            saveWords()
            return
        }

        words.insert(
            VocabWord(ru: ru, uk: uk, isActive: true, isCustom: true),
            at: 0
        )
        saveWords()
    }

    func markMastered(_ word: VocabWord) {
        let pack = currentPrompt?.id == word.id ? (currentPromptPack ?? languagePack) : languagePack
        var packWords = loadWords(for: pack)
        guard let idx = packWords.firstIndex(where: { $0.id == word.id }) else { return }
        packWords[idx].box = 4
        packWords[idx].timesKnown += 1
        packWords[idx].isActive = false
        saveWords(packWords, for: pack)
        if pack == languagePack {
            words = packWords
        }
        if currentPrompt?.id == word.id {
            dismissPrompt()
        }
    }

    func resetProgress(for word: VocabWord) {
        guard let idx = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[idx].box = 0
        words[idx].timesShown = 0
        words[idx].timesKnown = 0
        saveWords()
    }

    func removeWord(_ word: VocabWord) {
        guard let idx = words.firstIndex(where: { $0.id == word.id }) else { return }
        words.remove(at: idx)
        saveWords()
        if currentPrompt?.id == word.id {
            dismissPrompt()
        }
    }

    private func loadWords() {
        words = loadWords(for: languagePack)
    }

    private func loadWords(for pack: VocabLanguagePack) -> [VocabWord] {
        let builtinWords = Self.builtinWords(for: pack)
        let builtinWordIDs = Self.builtinWordIDs(for: pack)

        if let data = UserDefaults.standard.data(forKey: storageKey(for: pack)),
           let saved = try? JSONDecoder().decode([VocabWord].self, from: data) {
            let savedByID = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
            // Merge saved progress with the built-in list, in case the
            // built-in list gained new words since last launch.
            var merged = builtinWords.map { savedByID[$0.id] ?? $0 }
            let customSavedWords = saved.filter { !builtinWordIDs.contains($0.id) }
            merged.insert(contentsOf: customSavedWords.reversed(), at: 0)
            return merged
        } else {
            return builtinWords
        }
    }

    private func saveWords() {
        saveWords(words, for: languagePack)
    }

    private func saveWords(_ words: [VocabWord], for pack: VocabLanguagePack) {
        guard let data = try? JSONEncoder().encode(words) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(for: pack))
    }

    private func ensureStarterWordsIfNeeded() {
        for pack in enabledPacks {
            ensureStarterWordsIfNeeded(for: pack)
        }
    }

    private func ensureStarterWordsIfNeeded(for pack: VocabLanguagePack) {
        var packWords = loadWords(for: pack)
        guard packWords.contains(where: \.isActive) == false else { return }

        let starterWords = Set(Self.builtinWords(for: pack).prefix(8).map(\.ru))
        var changed = false
        for index in packWords.indices {
            guard starterWords.contains(packWords[index].ru) else { continue }
            if !packWords[index].isActive {
                packWords[index].isActive = true
                changed = true
            }
        }

        guard changed else { return }
        saveWords(packWords, for: pack)
        if pack == languagePack {
            words = packWords
        }
    }

    // MARK: Timer

    private func restartTimer() {
        timerCancellable?.cancel()
        guard isEnabled else { return }
        ensureStarterWordsIfNeeded()
        guard enabledPacks.isEmpty == false else { return }
        let seconds = max(1, intervalMinutes) * 60
        timerCancellable = Timer.publish(every: TimeInterval(seconds), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.showRandomWord()
            }
    }

    // MARK: Showing a word

    /// Picks an active, not-yet-mastered word, weighted towards ones
    /// you know less well, and shows it in the overlay card.
    func showRandomWord() {
        struct PromptCandidate {
            let pack: VocabLanguagePack
            let word: VocabWord
        }

        let candidates: [PromptCandidate] = enabledPacks.flatMap { pack in
            loadWords(for: pack)
                .filter { $0.isActive && $0.box < 4 }
                .map { PromptCandidate(pack: pack, word: $0) }
        }
        guard !candidates.isEmpty else { return }

        let weighted = candidates.flatMap { candidate in
            Array(repeating: candidate, count: max(1, 5 - candidate.word.box))
        }
        guard let picked = weighted.randomElement() else { return }

        currentPromptIsRuToUk = {
            switch direction {
            case .ruToUk: return true
            case .ukToRu: return false
            case .mixed: return Bool.random()
            }
        }()

        currentPromptPack = picked.pack
        currentPrompt = picked.word
        markShown(picked.word, in: picked.pack)
        showPromptOverlay = true
        overlay.show()
    }

    private func markShown(_ word: VocabWord, in pack: VocabLanguagePack) {
        var packWords = loadWords(for: pack)
        guard let idx = packWords.firstIndex(where: { $0.id == word.id }) else { return }
        packWords[idx].timesShown += 1
        saveWords(packWords, for: pack)
        if pack == languagePack {
            words = packWords
        }
    }

    func answer(knew: Bool) {
        guard let word = currentPrompt, let pack = currentPromptPack else { return }
        var packWords = loadWords(for: pack)
        guard let idx = packWords.firstIndex(where: { $0.id == word.id }) else { return }
        if knew {
            packWords[idx].timesKnown += 1
            packWords[idx].box = min(4, packWords[idx].box + 1)
        } else {
            packWords[idx].box = max(0, packWords[idx].box - 1)
        }
        saveWords(packWords, for: pack)
        if pack == languagePack {
            words = packWords
        }
        dismissPrompt()
    }

    func dismissPrompt() {
        showPromptOverlay = false
        overlay.hide()
        currentPrompt = nil
        currentPromptPack = nil
    }

    private func displayText(_ text: String) -> String {
        // Capital letters are a readable fallback for the built-in words where stress matters.
        let marked: [String: String] = [
            "успеть": "успЕть", "отменить": "отменИть", "обсудить": "обсудИть",
            "вспомнить": "вспОмнить", "предложить": "предложИть", "привычка": "привЫчка",
            "решение": "решЕние", "возможность": "возмОжность", "внимание": "внимАние",
            "сегодня": "сегОдня", "завтра": "зАвтра", "пожалуйста": "пожАлуйста",
            "встигнути": "встигнУти", "скасувати": "скасувАти", "обговорити": "обговорИти",
            "згадати": "згАдати", "запропонувати": "запропонувАти", "звичка": "звИчка",
            "рішення": "рІшення", "можливість": "можлИвість", "увага": "увАга",
            "сьогодні": "сьогОдні", "будь ласка": "будь лАска"
        ]
        return marked[text] ?? text
    }

    private func storageKey(for pack: VocabLanguagePack) -> String {
        "vocabWordsStateV2_\(pack.rawValue)"
    }

    // MARK: Built-in starter list (common everyday words/phrases)

    private static let ukrainianWords: [VocabWord] = [
        .init(ru: "успеть", uk: "встигнути"),
        .init(ru: "отменить", uk: "скасувати"),
        .init(ru: "перенести встречу", uk: "перенести зустріч"),
        .init(ru: "напомни мне позже", uk: "нагадай мені пізніше"),
        .init(ru: "я опаздываю", uk: "я запізнююся"),
        .init(ru: "мне неудобно", uk: "мені незручно"),
        .init(ru: "это срочно", uk: "це терміново"),
        .init(ru: "мне подходит", uk: "мені підходить"),
        .init(ru: "свободное время", uk: "вільний час"),
        .init(ru: "расписание", uk: "розклад"),
        .init(ru: "дедлайн", uk: "кінцевий термін"),
        .init(ru: "привычка", uk: "звичка"),
        .init(ru: "сосредоточиться", uk: "зосередитися"),
        .init(ru: "отвлекаться", uk: "відволікатися"),
        .init(ru: "перерыв", uk: "перерва"),
        .init(ru: "нагрузка", uk: "навантаження"),
        .init(ru: "самочувствие", uk: "самопочуття"),
        .init(ru: "усталость", uk: "втома"),
        .init(ru: "спокойствие", uk: "спокій"),
        .init(ru: "обсудить", uk: "обговорити"),
        .init(ru: "договориться", uk: "домовитися"),
        .init(ru: "подтвердить", uk: "підтвердити"),
        .init(ru: "уточнить", uk: "уточнити"),
        .init(ru: "сравнить", uk: "порівняти"),
        .init(ru: "выбрать", uk: "обрати"),
        .init(ru: "решение", uk: "рішення"),
        .init(ru: "причина", uk: "причина"),
        .init(ru: "последствие", uk: "наслідок"),
        .init(ru: "сомнение", uk: "сумнів"),
        .init(ru: "поддержка", uk: "підтримка"),
        .init(ru: "доверие", uk: "довіра"),
        .init(ru: "впечатление", uk: "враження"),
        .init(ru: "поведение", uk: "поведінка"),
        .init(ru: "привычный", uk: "звичний"),
        .init(ru: "неожиданно", uk: "несподівано"),
        .init(ru: "вовремя", uk: "вчасно"),
        .init(ru: "примерно", uk: "приблизно"),
        .init(ru: "вместо этого", uk: "замість цього"),
        .init(ru: "впрочем", uk: "втім"),
        .init(ru: "поэтому", uk: "тому"),
        .init(ru: "кстати", uk: "до речі"),
        .init(ru: "окружение", uk: "оточення"),
        .init(ru: "пространство", uk: "простір"),
        .init(ru: "поверхность", uk: "поверхня"),
        .init(ru: "граница", uk: "межа"),
        .init(ru: "условие", uk: "умова"),
        .init(ru: "возможность", uk: "можливість"),
        .init(ru: "влияние", uk: "вплив"),
        .init(ru: "разрешение", uk: "дозвіл"),
        .init(ru: "запрос", uk: "запит"),
        .init(ru: "напоминание", uk: "нагадування"),
        .init(ru: "список дел", uk: "список справ"),
        .init(ru: "покупки", uk: "покупки"),
        .init(ru: "счёт", uk: "рахунок"),
        .init(ru: "оплата", uk: "оплата"),
        .init(ru: "доставка", uk: "доставка"),
        .init(ru: "наличные", uk: "готівка"),
        .init(ru: "карточка", uk: "картка"),
        .init(ru: "стоимость", uk: "вартість"),
        .init(ru: "скидка", uk: "знижка"),
        .init(ru: "аренда", uk: "оренда"),
        .init(ru: "сосед", uk: "сусід"),
        .init(ru: "подъезд", uk: "під'їзд"),
        .init(ru: "полотенце", uk: "рушник"),
        .init(ru: "постель", uk: "постіль"),
        .init(ru: "посуда", uk: "посуд"),
        .init(ru: "морозилка", uk: "морозильник"),
        .init(ru: "чайник", uk: "чайник"),
        .init(ru: "зарядка", uk: "зарядка"),
        .init(ru: "наушники", uk: "навушники"),
        .init(ru: "выключатель", uk: "вимикач"),
        .init(ru: "розетка", uk: "розетка"),
        .init(ru: "ремонт", uk: "ремонт"),
        .init(ru: "инструмент", uk: "інструмент"),
        .init(ru: "лекарство", uk: "ліки"),
        .init(ru: "аптека", uk: "аптека"),
        .init(ru: "симптом", uk: "симптом"),
        .init(ru: "давление", uk: "тиск"),
        .init(ru: "кашель", uk: "кашель"),
        .init(ru: "температура", uk: "температура"),
        .init(ru: "беспокоиться", uk: "хвилюватися"),
        .init(ru: "облегчение", uk: "полегшення"),
        .init(ru: "честно говоря", uk: "чесно кажучи"),
        .init(ru: "мне кажется", uk: "мені здається"),
        .init(ru: "имеет смысл", uk: "має сенс"),
        .init(ru: "не уверен", uk: "не впевнений"),
        .init(ru: "постараюсь", uk: "постараюся"),
        .init(ru: "получается", uk: "виходить"),
        .init(ru: "не получается", uk: "не виходить"),
        .init(ru: "я привык", uk: "я звик"),
        .init(ru: "мне важно", uk: "для мене важливо"),
        .init(ru: "я забыл", uk: "я забув"),
        .init(ru: "я вспомнил", uk: "я згадав"),
        .init(ru: "проверить", uk: "перевірити"),
        .init(ru: "исправить", uk: "виправити"),
        .init(ru: "обновить", uk: "оновити"),
        .init(ru: "сохранить", uk: "зберегти"),
        .init(ru: "поделиться", uk: "поділитися"),
        .init(ru: "удалить", uk: "видалити"),
    ]

    private static let englishWords: [VocabWord] = [
        .init(ru: "сосредоточиться", uk: "to focus"),
        .init(ru: "откладывать", uk: "to postpone"),
        .init(ru: "отвлекаться", uk: "to get distracted"),
        .init(ru: "дедлайн", uk: "deadline"),
        .init(ru: "обязательство", uk: "commitment"),
        .init(ru: "приоритет", uk: "priority"),
        .init(ru: "расписание", uk: "schedule"),
        .init(ru: "напоминание", uk: "reminder"),
        .init(ru: "обсудить", uk: "to discuss"),
        .init(ru: "подтвердить", uk: "to confirm"),
        .init(ru: "решение", uk: "decision"),
        .init(ru: "сомнение", uk: "doubt"),
        .init(ru: "окружение", uk: "environment"),
        .init(ru: "разрешение", uk: "permission"),
        .init(ru: "влияние", uk: "impact"),
        .init(ru: "привычка", uk: "habit"),
        .init(ru: "последствие", uk: "consequence"),
        .init(ru: "нагрузка", uk: "workload"),
        .init(ru: "самочувствие", uk: "well-being"),
        .init(ru: "уточнить", uk: "to clarify"),
        .init(ru: "сравнить", uk: "to compare"),
        .init(ru: "примерно", uk: "roughly"),
        .init(ru: "вовремя", uk: "on time"),
        .init(ru: "обновить", uk: "to update"),
        .init(ru: "исправить", uk: "to fix"),
        .init(ru: "поделиться", uk: "to share"),
        .init(ru: "удалить", uk: "to delete"),
        .init(ru: "перерыв", uk: "break"),
    ]

    private static let indonesianWords: [VocabWord] = [
        .init(ru: "привет", uk: "halo"),
        .init(ru: "спасибо", uk: "terima kasih"),
        .init(ru: "пожалуйста", uk: "tolong"),
        .init(ru: "да", uk: "ya"),
        .init(ru: "нет", uk: "tidak"),
        .init(ru: "вода", uk: "air"),
        .init(ru: "еда", uk: "makanan"),
        .init(ru: "дом", uk: "rumah"),
        .init(ru: "работа", uk: "kerja"),
        .init(ru: "время", uk: "waktu"),
        .init(ru: "сегодня", uk: "hari ini"),
        .init(ru: "завтра", uk: "besok"),
        .init(ru: "встреча", uk: "pertemuan"),
        .init(ru: "задача", uk: "tugas"),
        .init(ru: "перерыв", uk: "istirahat"),
        .init(ru: "магазин", uk: "toko"),
        .init(ru: "деньги", uk: "uang"),
        .init(ru: "дорога", uk: "jalan"),
        .init(ru: "лево", uk: "kiri"),
        .init(ru: "право", uk: "kanan"),
        .init(ru: "быстро", uk: "cepat"),
        .init(ru: "медленно", uk: "pelan"),
        .init(ru: "хорошо", uk: "bagus"),
        .init(ru: "плохо", uk: "buruk"),
        .init(ru: "понимать", uk: "mengerti"),
        .init(ru: "говорить", uk: "berbicara"),
        .init(ru: "слушать", uk: "mendengar"),
        .init(ru: "помочь", uk: "membantu"),
    ]

    static func builtinWords(for pack: VocabLanguagePack) -> [VocabWord] {
        switch pack {
        case .ukrainian:
            return ukrainianWords
        case .english:
            return englishWords
        case .indonesian:
            return indonesianWords
        case .custom:
            return []
        }
    }

    static func builtinWordIDs(for pack: VocabLanguagePack) -> Set<String> {
        Set(builtinWords(for: pack).map(\.id))
    }
}
