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
//  4 = consolidated; scheduled reviews continue unless explicitly excluded).
//
//  Everything is stored in UserDefaults as plain JSON — no database, no
//  disk polling, and the background timer only fires once every few
//  minutes, so this is effectively free while idle.
//

import Foundation
import SwiftUI
import Combine

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
    @Published private(set) var currentPromptIsGap = false
    @Published var showPromptOverlay: Bool = false

    @AppStorage("vocabEnabled") var isEnabled: Bool = false {
        willSet { objectWillChange.send() }
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
    // @AppStorage внутри класса сам не сообщает виду об изменении, поэтому
    // каждому свойству нужен явный objectWillChange — без него вкладка языка
    // и направление перевода на экране не перерисовываются.
    @AppStorage("vocabIntervalMinutes") var intervalMinutes: Int = 10 {
        willSet { objectWillChange.send() }
        didSet { restartTimer() }
    }
    @AppStorage("vocabDirectionRaw") private var directionRaw: String = VocabDirection.ruToUk.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("vocabLanguagePackRaw") private var languagePackRaw: String = VocabLanguagePack.ukrainian.rawValue {
        willSet { objectWillChange.send() }
        didSet {
            dismissPrompt()
            ensureStudyQueueIfNeeded(for: languagePack)
            loadWords()
            restartTimer()
        }
    }
    @AppStorage("vocabEnabledLanguagePacksRaw") private var enabledLanguagePacksRaw: String = VocabLanguagePack.ukrainian.rawValue {
        willSet { objectWillChange.send() }
        didSet {
            dismissPrompt()
            ensureStarterWordsIfNeeded()
            restartTimer()
        }
    }
    @AppStorage("vocabCustomPackName") var customPackName: String = "Свой набор" {
        didSet { objectWillChange.send() }
    }
    @AppStorage("vocabAutoFill") var autoFillEnabled: Bool = true {
        willSet { objectWillChange.send() }
        didSet { ensureStudyQueuesIfNeeded() }
    }
    @AppStorage("vocabActiveTarget") var activeTarget: Int = 6 {
        willSet { objectWillChange.send() }
        didSet { ensureStudyQueuesIfNeeded() }
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

    /// Цвет русского — он всегда одна из двух сторон перевода.
    static let sourceColor = Color(red: 0.29, green: 0.60, blue: 0.91)

    /// Цвет языка. Украинский жёлтый, индонезийский красный — как флаги, так
    /// пара «синий → жёлтый» читается без чтения подписи. Английский —
    /// насыщенно-синий, как попросил пользователь.
    static func color(for pack: VocabLanguagePack) -> Color {
        switch pack {
        case .ukrainian:
            return Color(red: 0.91, green: 0.70, blue: 0.22)
        case .english:
            return Color(red: 0.30, green: 0.52, blue: 0.96)
        case .indonesian:
            return Color(red: 0.84, green: 0.35, blue: 0.34)
        case .custom:
            return Color(red: 0.45, green: 0.72, blue: 0.65)
        }
    }

    var currentPromptAccent: Color {
        Self.color(for: currentPromptPack ?? languagePack)
    }

    var currentPromptTextColor: Color { currentPromptPairColors.from }
    var currentAnswerTextColor: Color { currentPromptPairColors.to }

    /// Цвета той пары, которая сейчас на карточке: слева то, что спрашивают.
    var currentPromptPairColors: (from: Color, to: Color) {
        let packColor = Self.color(for: currentPromptPack ?? languagePack)
        return currentPromptIsRuToUk
            ? (Self.sourceColor, packColor)
            : (packColor, Self.sourceColor)
    }

    func promptText(for word: VocabWord) -> String {
        if currentPromptIsGap, let text = VocabReviewSchedule.maskedExample(for: word) { return text }
        return displayText(currentPromptIsRuToUk ? word.ru : word.uk)
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

    private var wordCache: [VocabLanguagePack: [VocabWord]] = [:]
    private var lastPromptID: String?
    private var timerCancellable: AnyCancellable?
    private var fullscreenCancellable: AnyCancellable?
    private var sessionAvailability = VocabSessionAvailability()

    private var shouldPauseForFullscreenApp: Bool {
        let pausesInFullscreen = UserDefaults.standard.object(forKey: "vocabPauseInFullscreen") as? Bool ?? true
        guard pausesInFullscreen else {
            return false
        }
        return FullscreenMediaDetector.shared.hasFullscreenApp
    }

    private init() {
        prepareConversationCourseIfNeeded()
        loadWords()
        fullscreenCancellable = FullscreenMediaDetector.shared.$hasFullscreenApp
            .removeDuplicates()
            .sink { [weak self] isFullscreen in
                guard isFullscreen, self?.shouldPauseForFullscreenApp == true else { return }
                self?.dismissPrompt()
            }
        restartTimer()
    }

    var activeCount: Int { words.filter { VocabReviewSchedule.isDue($0, now: Date()) }.count }

    func selectedLevel(for pack: VocabLanguagePack) -> VocabLevel {
        let key = selectedLevelKey(for: pack)
        return VocabLevel(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .a1
    }

    func setSelectedLevel(_ level: VocabLevel, for pack: VocabLanguagePack) {
        UserDefaults.standard.set(level.rawValue, forKey: selectedLevelKey(for: pack))
        objectWillChange.send()
        ensureStudyQueueIfNeeded(for: pack)
    }

    func availableCount(level: VocabLevel, for pack: VocabLanguagePack) -> Int {
        let existing = Set(loadWords(for: pack).map(\.id))
        return Self.levelPack(for: pack)
            .filter { $0.level == level.rawValue && !existing.contains($0.ru) }
            .count
    }

    func totalPackCount(for pack: VocabLanguagePack) -> Int {
        Self.levelPack(for: pack).count
    }

    func reviewCount(for pack: VocabLanguagePack) -> Int {
        loadWords(for: pack).filter { $0.reviewDueAt != nil || $0.reviewAfterNewWords != nil }.count
    }

    /// Выученные раньше просто исчезали из списка: «Уже знаю» ставит box = 4 и
    /// снимает активность, а список показывал только неизученные — вернуть
    /// слово было нечем. Теперь видно всё, выученное уходит вниз.
    var visibleWords: [VocabWord] {
        words.enumerated()
            .sorted { left, right in
                let leftDone = left.element.box >= 4
                let rightDone = right.element.box >= 4
                if leftDone != rightDone { return !leftDone }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    var masteredCount: Int { words.filter { $0.box >= 4 }.count }

    func activeCount(for pack: VocabLanguagePack) -> Int {
        loadWords(for: pack).filter { VocabReviewSchedule.isDue($0, now: Date()) }.count
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
        if enabled {
            ensureStudyQueueIfNeeded(for: pack)
        }
    }

    // MARK: Word list management

    func setActive(_ word: VocabWord, active: Bool) {
        guard let idx = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[idx].isActive = active
        words[idx].isPaused = !active
        if active {
            words[idx].isExcluded = false
            if words[idx].box >= 4 { words[idx].box = 0; words[idx].reviewStage = 0 }
            words[idx].reviewDueAt = nil
        }
        saveWords()
    }

    func addWord(ru: String, uk: String) {
        let ru = ru.trimmingCharacters(in: .whitespacesAndNewlines)
        let uk = uk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ru.isEmpty, !uk.isEmpty else { return }

        if let idx = words.firstIndex(where: { $0.ru.caseInsensitiveCompare(ru) == .orderedSame }) {
            words[idx].isActive = true
            words[idx].box = 0
            words[idx].reviewStage = 0
            words[idx].reviewDueAt = nil
            words[idx].isExcluded = false
            words[idx].isPaused = false
            saveWords()
            return
        }

        words.insert(
            VocabWord(ru: ru, uk: uk, isActive: true, isCustom: true),
            at: 0
        )
        noteIntroducedWords(1, for: languagePack)
        saveWords()
    }

    func markMastered(_ word: VocabWord) {
        let pack = currentPrompt?.id == word.id ? (currentPromptPack ?? languagePack) : languagePack
        var packWords = loadWords(for: pack)
        guard let idx = packWords.firstIndex(where: { $0.id == word.id }) else { return }
        VocabReviewSchedule.exclude(&packWords[idx])
        saveWords(packWords, for: pack)
        if pack == languagePack {
            words = packWords
        }
        if currentPrompt?.id == word.id {
            dismissPrompt()
        }
        ensureStudyQueueIfNeeded(for: pack)
    }

    func resetProgress(for word: VocabWord) {
        guard let idx = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[idx].box = 0
        words[idx].timesShown = 0
        words[idx].timesKnown = 0
        words[idx].reviewDueAt = nil
        words[idx].reviewAfterNewWords = nil
        words[idx].reviewStage = 0
        words[idx].lastAnsweredAt = nil
        words[idx].isExcluded = false
        words[idx].isPaused = false
        words[idx].isActive = true
        saveWords()
    }

    /// Удаляет слово навсегда — в том числе встроенное. Встроенные при каждой
    /// загрузке подмешиваются обратно из кода, поэтому их id запоминается
    /// отдельно, иначе удалённое слово возвращалось бы после перезапуска.
    func removeWord(_ word: VocabWord) {
        guard let idx = words.firstIndex(where: { $0.id == word.id }) else { return }
        words.remove(at: idx)
        if Self.builtinWordIDs(for: languagePack).contains(word.id) {
            var deleted = deletedIDs(for: languagePack)
            deleted.insert(word.id)
            saveDeletedIDs(deleted, for: languagePack)
        }
        saveWords()
        if currentPrompt?.id == word.id {
            dismissPrompt()
        }
    }

    var deletedCount: Int { deletedIDs(for: languagePack).count }

    /// Страховка от случайного нажатия: вернуть всё удалённое во вкладке.
    func restoreDeletedWords() {
        saveDeletedIDs([], for: languagePack)
        loadWords()
    }

    private func deletedIDs(for pack: VocabLanguagePack) -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: deletedKey(for: pack)) ?? []
        return Set(raw)
    }

    private func saveDeletedIDs(_ ids: Set<String>, for pack: VocabLanguagePack) {
        wordCache[pack] = nil
        UserDefaults.standard.set(Array(ids), forKey: deletedKey(for: pack))
    }

    private func deletedKey(for pack: VocabLanguagePack) -> String {
        "vocabDeletedV1_\(pack.rawValue)"
    }

    private func loadWords() {
        words = loadWords(for: languagePack)
    }

    private func loadWords(for pack: VocabLanguagePack) -> [VocabWord] {
        if let cached = wordCache[pack] { return cached }
        let deleted = deletedIDs(for: pack)
        let builtinWords = Self.builtinWords(for: pack).filter { !deleted.contains($0.id) }
        let builtinIDs = Self.builtinWordIDs(for: pack)
        var merged = builtinWords
        if let data = UserDefaults.standard.data(forKey: storageKey(for: pack)),
           let saved = try? JSONDecoder().decode([VocabWord].self, from: data) {
            let savedByID = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            merged = builtinWords.map { builtin in
                guard var savedWord = savedByID[builtin.id] else { return builtin }
                if pack == .ukrainian, !savedWord.isCustom { savedWord.uk = builtin.uk }
                return savedWord
            }
            merged.insert(contentsOf: saved.filter { !builtinIDs.contains($0.id) && !deleted.contains($0.id) }, at: 0)
        }
        let metadata = Dictionary(Self.levelPack(for: pack).map { ($0.ru, $0) }, uniquingKeysWith: { first, _ in first })
        for i in merged.indices {
            if let entry = metadata[merged[i].id] { VocabReviewSchedule.applyMetadata(entry, to: &merged[i]) }
        }
        wordCache[pack] = merged
        return merged
    }

    private func saveWords() {
        saveWords(words, for: languagePack)
    }

    private func saveWords(_ words: [VocabWord], for pack: VocabLanguagePack) {
        wordCache[pack] = words
        guard let data = try? JSONEncoder().encode(words) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(for: pack))
    }

    private func ensureStarterWordsIfNeeded() {
        for pack in enabledPacks {
            ensureStudyQueueIfNeeded(for: pack)
        }
    }

    private func ensureStarterWordsIfNeeded(for pack: VocabLanguagePack) {
        guard !autoFillEnabled else {
            ensureStudyQueueIfNeeded(for: pack)
            return
        }
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

    func setSessionSuspended(_ reason: VocabSessionAvailability.Suspension, suspended: Bool) {
        guard sessionAvailability.setSuspended(reason, suspended: suspended) else { return }
        if sessionAvailability.permitsPrompts {
            restartTimer()
        } else {
            timerCancellable?.cancel()
            timerCancellable = nil
            dismissPrompt()
        }
    }

    private func restartTimer() {
        timerCancellable?.cancel()
        guard isEnabled, sessionAvailability.permitsPrompts else { return }
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

        // A full-screen app is usually a film, presentation or game. Do not
        // put a study card over it; the next timer tick will try again.
        guard sessionAvailability.permitsPrompts, currentPrompt == nil, !shouldPauseForFullscreenApp else { return }

        ensureStudyQueuesIfNeeded()
        let candidates: [PromptCandidate] = enabledPacks.flatMap { pack in
            loadWords(for: pack)
                .filter { VocabReviewSchedule.isDue($0, now: Date()) }
                .map { PromptCandidate(pack: pack, word: $0) }
        }
        guard !candidates.isEmpty else { return }

        // Oldest due review first, then new conversation items in curriculum
        // order. No random weighted-array allocation and no immediate repeat.
        let ordered = candidates.sorted { left, right in
            let l = left.word.reviewDueAt ?? .distantFuture
            let r = right.word.reviewDueAt ?? .distantFuture
            if l != r { return l < r }
            return (left.word.priority ?? Int.max) < (right.word.priority ?? Int.max)
        }
        guard let picked = ordered.first(where: { $0.word.id != lastPromptID }) ?? ordered.first else { return }
        lastPromptID = picked.word.id

        currentPromptIsRuToUk = {
            switch direction {
            case .ruToUk: return true
            case .ukToRu: return false
            case .mixed: return Bool.random()
            }
        }()

        currentPromptIsGap = picked.pack == .ukrainian && currentPromptIsRuToUk
            && picked.word.timesShown % 3 == 1 && VocabReviewSchedule.maskedExample(for: picked.word) != nil
        currentPromptPack = picked.pack
        currentPrompt = picked.word
        markShown(picked.word, in: picked.pack)
        showPromptOverlay = true
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
        VocabReviewSchedule.answer(&packWords[idx], recalled: knew, now: Date())
        saveWords(packWords, for: pack)
        if pack == languagePack {
            words = packWords
        }
        dismissPrompt()
        ensureStudyQueueIfNeeded(for: pack)
    }

    func dismissPrompt() {
        let dismissing = currentPrompt
        showPromptOverlay = false
        // Keep text visible while the panel folds upward. A newer prompt must
        // never be cleared by completion of the previous card's dismissal.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !self.showPromptOverlay, self.currentPrompt == dismissing else { return }
            self.currentPrompt = nil
            self.currentPromptPack = nil
        }
    }

    /// Ударение показывается надстрочным знаком: «успі́х», а не «успИх».
    /// Заглавная буква посреди слова читается как опечатка и ломает вид строки;
    /// комбинируемый акут (U+0301) — то, чем ударение обозначают в словарях.
    /// В таблице ниже ударный гласный записан заглавной, а превращает его в
    /// знак этот код — так таблицу проще пополнять руками.
    private static func withStressMark(_ marked: String) -> String {
        var result = ""
        for character in marked {
            if character.isUppercase, character.isLetter {
                result += character.lowercased()
                result += "\u{0301}"
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Ударения, расставленные один раз и проверенные `tools/stress_helper.py`.
    /// Файла может не быть — тогда работает маленькая таблица ниже.
    private static let stressedWords: [String: String] = {
        guard let url = Bundle.main.url(forResource: "vocab-stress", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return [:] }
        return decoded["stressed"] ?? [:]
    }()

    private func displayText(_ text: String) -> String {
        if let stressed = Self.stressedWords[text] { return stressed }

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
        guard let stressed = marked[text] else { return text }
        return Self.withStressMark(stressed)
    }

    // MARK: Automatic study queue and reviews

    private func selectedLevelKey(for pack: VocabLanguagePack) -> String {
        "vocabSelectedLevelV1_\(pack.rawValue)"
    }

    private func introducedWordCount(for pack: VocabLanguagePack) -> Int {
        UserDefaults.standard.integer(forKey: "vocabIntroducedWordCountV1_\(pack.rawValue)")
    }

    private func noteIntroducedWords(_ count: Int, for pack: VocabLanguagePack) {
        guard count > 0 else { return }
        let key = "vocabIntroducedWordCountV1_\(pack.rawValue)"
        UserDefaults.standard.set(introducedWordCount(for: pack) + count, forKey: key)
    }

    private func ensureStudyQueuesIfNeeded() {
        for pack in enabledPacks {
            ensureStudyQueueIfNeeded(for: pack)
        }
    }

    private func ensureStudyQueueIfNeeded(for pack: VocabLanguagePack) {
        guard isEnabled, isPackEnabled(pack) else { return }
        var packWords = loadWords(for: pack)
        let now = Date()
        var changed = false
        // Migrate old schedules when due, preserving completed/excluded words.
        for i in packWords.indices where packWords[i].reviewStage == nil && packWords[i].box >= 4 {
            let dueByDate = packWords[i].reviewDueAt.map { $0 <= now } ?? false
            let dueByCount = packWords[i].reviewAfterNewWords.map { introducedWordCount(for: pack) >= $0 } ?? false
            if dueByDate || dueByCount {
                packWords[i].reviewStage = 3
                packWords[i].reviewDueAt = now
                packWords[i].reviewAfterNewWords = nil
                changed = true
            }
        }
        if autoFillEnabled, pack != .custom {
            let selected = selectedLevel(for: pack)
            let levels = VocabLevel.allCases
            let first = levels.firstIndex(of: selected) ?? 0
            // Exhaust the curated stage before advancing to a harder one.
            let entries = pack == .ukrainian
                ? VocabStudyQueue.currentStage(catalog: Self.levelPack(for: pack), words: packWords,
                    levels: levels.dropFirst(first).map(\.rawValue), deleted: deletedIDs(for: pack))
                : Self.levelPack(for: pack).filter { $0.level == selected.rawValue }
            let introduced = VocabStudyQueue.refill(&packWords, catalog: entries,
                deleted: deletedIDs(for: pack), target: activeTarget, now: now)
            changed = changed || introduced > 0
            noteIntroducedWords(introduced, for: pack)
        }
        if changed { saveWords(packWords, for: pack) }
        if pack == languagePack && words != packWords { words = packWords }
    }

    /// Start the requested conversational path once; never reset answers or
    /// discard custom words. Old untouched built-ins remain available in lists.
    private func prepareConversationCourseIfNeeded() {
        let key = "vocabConversationCourseV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        var packWords = loadWords(for: .ukrainian)
        for i in packWords.indices where packWords[i].box < 4 && packWords[i].reviewDueAt == nil {
            packWords[i].isActive = false
        }
        saveWords(packWords, for: .ukrainian)
        UserDefaults.standard.set(VocabLevel.a1.rawValue, forKey: selectedLevelKey(for: .ukrainian))
        UserDefaults.standard.set(true, forKey: key)
    }

    private static let reviewDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter
    }()

    func studyStatus(for word: VocabWord) -> String {
        if word.isExcluded == true { return "Уже знаю · больше не спрашивать" }
        if let due = word.reviewDueAt {
            let formatter = Self.reviewDateFormatter
            let prefix = word.box >= 4 ? "Закрепление" : "Повторение"
            return "\(prefix) \(formatter.localizedString(for: due, relativeTo: Date()))"
        }
        return word.box >= 4 ? "Выучено" : "\(min(3, word.reviewStage ?? word.box))/3 успешных повторений"
    }

    private func storageKey(for pack: VocabLanguagePack) -> String {
        "vocabWordsStateV2_\(pack.rawValue)"
    }

    // MARK: Built-in starter list (common everyday words/phrases)

    private static let ukrainianWords: [VocabWord] = [
        .init(ru: "успеть", uk: "всти́гнути"),
        .init(ru: "отменить", uk: "скасува́ти"),
        .init(ru: "перенести встречу", uk: "перенести́ зу́стріч"),
        .init(ru: "напомни мне позже", uk: "нагада́й мені́ пізні́ше"),
        .init(ru: "я опаздываю", uk: "я́ запі́знююся"),
        .init(ru: "мне неудобно", uk: "мені́ незру́чно"),
        .init(ru: "это срочно", uk: "це́ терміно́во"),
        .init(ru: "мне подходит", uk: "мені́ підхо́дить"),
        .init(ru: "свободное время", uk: "ві́льний ча́с"),
        .init(ru: "расписание", uk: "ро́зклад"),
        .init(ru: "дедлайн", uk: "кінце́вий те́рмін"),
        .init(ru: "привычка", uk: "зви́чка"),
        .init(ru: "сосредоточиться", uk: "зосере́дитися"),
        .init(ru: "отвлекаться", uk: "відволіка́тися"),
        .init(ru: "перерыв", uk: "пере́рва"),
        .init(ru: "нагрузка", uk: "наванта́ження"),
        .init(ru: "самочувствие", uk: "самопочуття́"),
        .init(ru: "усталость", uk: "вто́ма"),
        .init(ru: "спокойствие", uk: "спо́кій"),
        .init(ru: "обсудить", uk: "обговори́ти"),
        .init(ru: "договориться", uk: "домо́витися"),
        .init(ru: "подтвердить", uk: "підтве́рдити"),
        .init(ru: "уточнить", uk: "уточни́ти"),
        .init(ru: "сравнить", uk: "порівня́ти"),
        .init(ru: "выбрать", uk: "обра́ти"),
        .init(ru: "решение", uk: "рі́шення"),
        .init(ru: "причина", uk: "причи́на"),
        .init(ru: "последствие", uk: "на́слідок"),
        .init(ru: "сомнение", uk: "су́мнів"),
        .init(ru: "поддержка", uk: "підтри́мка"),
        .init(ru: "доверие", uk: "дові́ра"),
        .init(ru: "впечатление", uk: "вра́ження"),
        .init(ru: "поведение", uk: "поведі́нка"),
        .init(ru: "привычный", uk: "зви́чний"),
        .init(ru: "неожиданно", uk: "несподі́вано"),
        .init(ru: "вовремя", uk: "вча́сно"),
        .init(ru: "примерно", uk: "прибли́зно"),
        .init(ru: "вместо этого", uk: "за́мість цього́"),
        .init(ru: "впрочем", uk: "вті́м"),
        .init(ru: "поэтому", uk: "тому́"),
        .init(ru: "кстати", uk: "до́ ре́чі"),
        .init(ru: "окружение", uk: "ото́чення"),
        .init(ru: "пространство", uk: "про́стір"),
        .init(ru: "поверхность", uk: "пове́рхня"),
        .init(ru: "граница", uk: "межа́"),
        .init(ru: "условие", uk: "умо́ва"),
        .init(ru: "возможность", uk: "можли́вість"),
        .init(ru: "влияние", uk: "впли́в"),
        .init(ru: "разрешение", uk: "до́звіл"),
        .init(ru: "запрос", uk: "за́пит"),
        .init(ru: "напоминание", uk: "нага́дування"),
        .init(ru: "список дел", uk: "спи́сок спра́в"),
        .init(ru: "покупки", uk: "поку́пки"),
        .init(ru: "счёт", uk: "раху́нок"),
        .init(ru: "оплата", uk: "опла́та"),
        .init(ru: "доставка", uk: "доста́вка"),
        .init(ru: "наличные", uk: "готі́вка"),
        .init(ru: "карточка", uk: "ка́ртка"),
        .init(ru: "стоимость", uk: "ва́ртість"),
        .init(ru: "скидка", uk: "зни́жка"),
        .init(ru: "аренда", uk: "оре́нда"),
        .init(ru: "сосед", uk: "сусі́д"),
        .init(ru: "подъезд", uk: "під'ї́зд"),
        .init(ru: "полотенце", uk: "рушни́к"),
        .init(ru: "постель", uk: "по́стіль"),
        .init(ru: "посуда", uk: "по́суд"),
        .init(ru: "морозилка", uk: "морози́льник"),
        .init(ru: "чайник", uk: "ча́йник"),
        .init(ru: "зарядка", uk: "заря́дка"),
        .init(ru: "наушники", uk: "наву́шники"),
        .init(ru: "выключатель", uk: "вимика́ч"),
        .init(ru: "розетка", uk: "розе́тка"),
        .init(ru: "ремонт", uk: "ремо́нт"),
        .init(ru: "инструмент", uk: "інструме́нт"),
        .init(ru: "лекарство", uk: "лі́ки"),
        .init(ru: "аптека", uk: "апте́ка"),
        .init(ru: "симптом", uk: "симпто́м"),
        .init(ru: "давление", uk: "ти́ск"),
        .init(ru: "кашель", uk: "ка́шель"),
        .init(ru: "температура", uk: "температу́ра"),
        .init(ru: "беспокоиться", uk: "хвилюва́тися"),
        .init(ru: "облегчение", uk: "поле́гшення"),
        .init(ru: "честно говоря", uk: "че́сно ка́жучи"),
        .init(ru: "мне кажется", uk: "мені́ здає́ться"),
        .init(ru: "имеет смысл", uk: "ма́є се́нс"),
        .init(ru: "не уверен", uk: "не́ впе́внений"),
        .init(ru: "постараюсь", uk: "постара́юся"),
        .init(ru: "получается", uk: "вихо́дить"),
        .init(ru: "не получается", uk: "не́ вихо́дить"),
        .init(ru: "я привык", uk: "я́ зви́к"),
        .init(ru: "мне важно", uk: "для́ мене́ важли́во"),
        .init(ru: "я забыл", uk: "я́ забу́в"),
        .init(ru: "я вспомнил", uk: "я́ згада́в"),
        .init(ru: "проверить", uk: "переві́рити"),
        .init(ru: "исправить", uk: "ви́правити"),
        .init(ru: "обновить", uk: "онови́ти"),
        .init(ru: "сохранить", uk: "зберегти́"),
        .init(ru: "поделиться", uk: "поділи́тися"),
        .init(ru: "удалить", uk: "ви́далити"),
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
        let list: [VocabWord]
        switch pack {
        case .ukrainian:
            list = ukrainianWords
        case .english:
            list = englishWords
        case .indonesian:
            list = indonesianWords
        case .custom:
            list = []
        }
        // Некоторые слова в украинском совпадают с русским буквально
        // («причина», «аптека», «температура»). Перевод верный, но карточка
        // бесполезна: вопрос и ответ одинаковые. В опрос такие не берём.
        return list.filter { $0.ru.caseInsensitiveCompare($0.uk.replacingOccurrences(of: "\u{0301}", with: "")) != .orderedSame }
    }

    static func builtinWordIDs(for pack: VocabLanguagePack) -> Set<String> {
        Set(builtinWords(for: pack).map(\.id))
    }

    // MARK: Наборы слов по темам

    /// Готовые тематические наборы — чтобы пополнять словарь не по одному
    /// слову. Всё лежит в приложении: без интернета, без ключей и без счёта
    /// за нейросеть, и перевод не меняется от запуска к запуску.
    static func topics(for pack: VocabLanguagePack) -> [VocabTopic] {
        switch pack {
        case .ukrainian:
            let catalog = levelPack(for: pack)
            var seen = Set<String>()
            let categories = catalog.compactMap(\.category).filter { seen.insert($0).inserted }
            return categories.map { category in
                let words = catalog.filter { $0.category == category }.map { entry in
                    var word = VocabWord(ru: entry.ru, uk: entry.target)
                    VocabReviewSchedule.applyMetadata(entry, to: &word)
                    return word
                }
                return VocabTopic(id: "uk-\(category)", title: category, words: words)
            }
        case .english:
            return [
                VocabTopic(id: "en-food", title: "Еда и кафе", words: [
                    .init(ru: "еда", uk: "food"),
                    .init(ru: "завтрак", uk: "breakfast"),
                    .init(ru: "обед", uk: "lunch"),
                    .init(ru: "ужин", uk: "dinner"),
                    .init(ru: "вкусно", uk: "tasty"),
                    .init(ru: "голодный", uk: "hungry"),
                    .init(ru: "счёт", uk: "the bill"),
                    .init(ru: "заказать", uk: "to order"),
                ]),
                VocabTopic(id: "en-city", title: "Город и дорога", words: [
                    .init(ru: "улица", uk: "street"),
                    .init(ru: "здание", uk: "building"),
                    .init(ru: "поезд", uk: "train"),
                    .init(ru: "самолёт", uk: "plane"),
                    .init(ru: "остановка", uk: "stop"),
                    .init(ru: "налево", uk: "left"),
                    .init(ru: "направо", uk: "right"),
                    .init(ru: "быстрее", uk: "faster"),
                ]),
                VocabTopic(id: "en-talk", title: "Разговор", words: [
                    .init(ru: "привет", uk: "hi"),
                    .init(ru: "спасибо", uk: "thank you"),
                    .init(ru: "пожалуйста", uk: "please"),
                    .init(ru: "извини", uk: "sorry"),
                    .init(ru: "как дела", uk: "how are you"),
                    .init(ru: "понимаю", uk: "I understand"),
                    .init(ru: "конечно", uk: "sure"),
                    .init(ru: "позже", uk: "later"),
                ]),
            ]
        case .indonesian:
            return [
                VocabTopic(id: "id-food", title: "Еда и кафе", words: [
                    .init(ru: "завтрак", uk: "sarapan"),
                    .init(ru: "обед", uk: "makan siang"),
                    .init(ru: "ужин", uk: "makan malam"),
                    .init(ru: "вкусно", uk: "enak"),
                    .init(ru: "голодный", uk: "lapar"),
                    .init(ru: "счёт", uk: "tagihan"),
                    .init(ru: "заказать", uk: "memesan"),
                    .init(ru: "рис", uk: "nasi"),
                ]),
                VocabTopic(id: "id-city", title: "Город и дорога", words: [
                    .init(ru: "поезд", uk: "kereta"),
                    .init(ru: "самолёт", uk: "pesawat"),
                    .init(ru: "остановка", uk: "halte"),
                    .init(ru: "аэропорт", uk: "bandara"),
                    .init(ru: "машина", uk: "mobil"),
                    .init(ru: "далеко", uk: "jauh"),
                    .init(ru: "близко", uk: "dekat"),
                    .init(ru: "сколько стоит", uk: "berapa harganya"),
                ]),
                VocabTopic(id: "id-talk", title: "Разговор", words: [
                    .init(ru: "доброе утро", uk: "selamat pagi"),
                    .init(ru: "добрый вечер", uk: "selamat malam"),
                    .init(ru: "извини", uk: "maaf"),
                    .init(ru: "как дела", uk: "apa kabar"),
                    .init(ru: "меня зовут", uk: "nama saya"),
                    .init(ru: "я не понимаю", uk: "saya tidak mengerti"),
                    .init(ru: "сколько", uk: "berapa"),
                    .init(ru: "где", uk: "di mana"),
                ]),
            ]
        case .custom:
            return []
        }
    }

    // MARK: Большие словари по уровням

    /// Словарь, собранный `tools/build_vocab_packs.py` из открытых источников
    /// и лежащий в приложении файлом. Уровень — это позиция русского слова в
    /// частотном списке: чем чаще слово в живой речи, тем раньше его учить.
    /// Читается один раз при первом обращении.
    private static var loadedPacks: [VocabLanguagePack: [VocabLevelWord]] = [:]

    static func levelPack(for pack: VocabLanguagePack) -> [VocabLevelWord] {
        if let cached = loadedPacks[pack] { return cached }

        let fileName: String?
        switch pack {
        case .ukrainian: fileName = "vocab-ukrainian"
        case .english: fileName = "vocab-english"
        case .indonesian: fileName = "vocab-indonesian"
        case .custom: fileName = nil
        }

        var words: [VocabLevelWord] = []
        if let fileName,
           let url = Bundle.main.url(forResource: fileName, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(VocabLevelPackFile.self, from: data) {
            words = decoded.words
        }
        loadedPacks[pack] = words
        return words
    }

    /// Сколько слов этого уровня ещё не добавлено.
    func availableCount(level: VocabLevel) -> Int {
        let existing = Set(words.map(\.id))
        return Self.levelPack(for: languagePack)
            .filter { $0.level == level.rawValue && !existing.contains($0.ru) }
            .count
    }

    /// Добавляет следующие `count` слов уровня — начиная с самых частых.
    @discardableResult
    func addWords(level: VocabLevel, count: Int) -> Int {
        var deleted = deletedIDs(for: languagePack)
        var existing = Set(words.map(\.id))
        var added: [VocabWord] = []

        for candidate in Self.levelPack(for: languagePack) where candidate.level == level.rawValue {
            guard added.count < count else { break }
            guard !existing.contains(candidate.ru) else { continue }
            var word = VocabWord(ru: candidate.ru, uk: candidate.target, isActive: true)
            VocabReviewSchedule.applyMetadata(candidate, to: &word)
            added.append(word)
            existing.insert(candidate.ru)
            deleted.remove(candidate.ru)
        }

        guard !added.isEmpty else { return 0 }
        saveDeletedIDs(deleted, for: languagePack)
        words.insert(contentsOf: added, at: 0)
        noteIntroducedWords(added.count, for: languagePack)
        saveWords()
        return added.count
    }

    /// Сколько слов темы ещё нет в текущем наборе.
    func newWordCount(in topic: VocabTopic) -> Int {
        let existing = Set(words.map(\.id))
        return topic.words.filter { !existing.contains($0.id) }.count
    }

    /// Добавляет недостающие слова темы и сразу берёт их в изучение.
    /// Уже удалённые вручную слова возвращаются: человек попросил их явно.
    func addTopic(_ topic: VocabTopic) {
        var deleted = deletedIDs(for: languagePack)
        var existing = Set(words.map(\.id))
        var added: [VocabWord] = []

        for word in topic.words where !existing.contains(word.id) {
            var addition = word
            addition.isActive = true
            added.append(addition)
            existing.insert(word.id)
            deleted.remove(word.id)
        }

        guard !added.isEmpty else { return }
        saveDeletedIDs(deleted, for: languagePack)
        words.insert(contentsOf: added, at: 0)
        noteIntroducedWords(added.count, for: languagePack)
        saveWords()
    }
}

struct VocabTopic: Identifiable {
    let id: String
    let title: String
    let words: [VocabWord]
}

/// Ukrainian labels are editorial course stages, not a CEFR certification.
/// Other packs retain their original approximate frequency-based grouping.
enum VocabLevel: String, CaseIterable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .a1: return String(localized: "самые частые")
        case .a2: return String(localized: "бытовые")
        case .b1: return String(localized: "уверенный уровень")
        case .b2: return String(localized: "редкие и точные")
        }
    }
}
