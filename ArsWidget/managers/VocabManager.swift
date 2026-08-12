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
    /// A mastered word leaves the daily queue, then comes back as a review.
    /// Optional fields keep all existing on-device progress decodable.
    var reviewDueAt: Date?
    var reviewAfterNewWords: Int?
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
    private var fullscreenCancellable: AnyCancellable?
    private lazy var overlay = VocabPromptOverlayWindow()

    private var shouldPauseForFullscreenApp: Bool {
        let pausesInFullscreen = UserDefaults.standard.object(forKey: "vocabPauseInFullscreen") as? Bool ?? true
        guard pausesInFullscreen else {
            return false
        }
        return FullscreenMediaDetector.shared.hasFullscreenApp
    }

    private init() {
        loadWords()
        fullscreenCancellable = FullscreenMediaDetector.shared.$hasFullscreenApp
            .removeDuplicates()
            .sink { [weak self] isFullscreen in
                guard isFullscreen, self?.shouldPauseForFullscreenApp == true else { return }
                self?.dismissPrompt()
            }
        restartTimer()
    }

    var activeCount: Int { words.filter { $0.isActive }.count }

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
        if enabled {
            ensureStudyQueueIfNeeded(for: pack)
        }
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
        noteIntroducedWords(1, for: languagePack)
        saveWords()
    }

    func markMastered(_ word: VocabWord) {
        let pack = currentPrompt?.id == word.id ? (currentPromptPack ?? languagePack) : languagePack
        var packWords = loadWords(for: pack)
        guard let idx = packWords.firstIndex(where: { $0.id == word.id }) else { return }
        packWords[idx].box = 4
        packWords[idx].timesKnown += 1
        packWords[idx].isActive = false
        scheduleReview(for: &packWords[idx], in: pack)
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
        UserDefaults.standard.set(Array(ids), forKey: deletedKey(for: pack))
    }

    private func deletedKey(for pack: VocabLanguagePack) -> String {
        "vocabDeletedV1_\(pack.rawValue)"
    }

    private func loadWords() {
        words = loadWords(for: languagePack)
    }

    private func loadWords(for pack: VocabLanguagePack) -> [VocabWord] {
        let deleted = deletedIDs(for: pack)
        let builtinWords = Self.builtinWords(for: pack).filter { !deleted.contains($0.id) }
        let builtinWordIDs = Self.builtinWordIDs(for: pack)

        if let data = UserDefaults.standard.data(forKey: storageKey(for: pack)),
           let saved = try? JSONDecoder().decode([VocabWord].self, from: data) {
            let savedByID = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // Merge saved progress with the built-in list, in case the
            // built-in list gained new words since last launch.
            var merged = builtinWords.map { savedByID[$0.id] ?? $0 }
            let customSavedWords = saved.filter { !builtinWordIDs.contains($0.id) && !deleted.contains($0.id) }
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

        // A full-screen app is usually a film, presentation or game. Do not
        // put a study card over it; the next timer tick will try again.
        guard !shouldPauseForFullscreenApp else { return }

        ensureStudyQueuesIfNeeded()
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
            if packWords[idx].box >= 4 {
                packWords[idx].isActive = false
                scheduleReview(for: &packWords[idx], in: pack)
            }
        } else {
            packWords[idx].box = max(0, packWords[idx].box - 1)
        }
        saveWords(packWords, for: pack)
        if pack == languagePack {
            words = packWords
        }
        dismissPrompt()
        ensureStudyQueueIfNeeded(for: pack)
    }

    func dismissPrompt() {
        showPromptOverlay = false
        overlay.hide()
        currentPrompt = nil
        currentPromptPack = nil
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

    /// A word returns after three days, or sooner after ten newly introduced
    /// words in the same language — whichever happens first.
    private func scheduleReview(for word: inout VocabWord, in pack: VocabLanguagePack) {
        word.reviewDueAt = Date().addingTimeInterval(3 * 24 * 60 * 60)
        word.reviewAfterNewWords = introducedWordCount(for: pack) + 10
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
        let introducedCount = introducedWordCount(for: pack)
        var changed = false

        // Return only scheduled repetitions. Older mastered words with no
        // schedule remain completed, so an app update never floods the queue.
        for index in packWords.indices where packWords[index].box >= 4 {
            let dueByDate = packWords[index].reviewDueAt.map { $0 <= now } ?? false
            let dueByNewWords = packWords[index].reviewAfterNewWords.map { introducedCount >= $0 } ?? false
            guard dueByDate || dueByNewWords else { continue }
            packWords[index].box = 3
            packWords[index].isActive = true
            packWords[index].reviewDueAt = nil
            packWords[index].reviewAfterNewWords = nil
            changed = true
        }

        guard autoFillEnabled, pack != .custom else {
            if changed { saveWords(packWords, for: pack) }
            if pack == languagePack { words = packWords }
            return
        }

        let active = packWords.filter { $0.isActive && $0.box < 4 }.count
        let needed = max(0, activeTarget - active)
        guard needed > 0 else {
            if changed { saveWords(packWords, for: pack) }
            if pack == languagePack { words = packWords }
            return
        }

        let existing = Set(packWords.map(\.id))
        let level = selectedLevel(for: pack)
        let additions = Self.levelPack(for: pack)
            .filter { $0.level == level.rawValue && !existing.contains($0.ru) }
            .prefix(needed)
            .map { VocabWord(ru: $0.ru, uk: $0.target, isActive: true, isCustom: true) }

        guard additions.isEmpty == false else {
            if changed { saveWords(packWords, for: pack) }
            if pack == languagePack { words = packWords }
            return
        }

        packWords.insert(contentsOf: additions, at: 0)
        noteIntroducedWords(additions.count, for: pack)
        saveWords(packWords, for: pack)
        if pack == languagePack { words = packWords }
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
        return list.filter { $0.ru.caseInsensitiveCompare($0.uk) != .orderedSame }
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
            return [
                VocabTopic(id: "uk-food", title: "Еда и кафе", words: [
                    .init(ru: "еда", uk: "їжа"),
                    .init(ru: "завтрак", uk: "сніданок"),
                    .init(ru: "обед", uk: "обід"),
                    .init(ru: "ужин", uk: "вечеря"),
                    .init(ru: "вкусно", uk: "смачно"),
                    .init(ru: "голодный", uk: "голодний"),
                    .init(ru: "счёт", uk: "рахунок"),
                    .init(ru: "заказать", uk: "замовити"),
                ]),
                VocabTopic(id: "uk-city", title: "Город и дорога", words: [
                    .init(ru: "улица", uk: "вулиця"),
                    .init(ru: "здание", uk: "будівля"),
                    .init(ru: "поезд", uk: "потяг"),
                    .init(ru: "самолёт", uk: "літак"),
                    .init(ru: "остановка", uk: "зупинка"),
                    .init(ru: "налево", uk: "ліворуч"),
                    .init(ru: "направо", uk: "праворуч"),
                    .init(ru: "быстрее", uk: "швидше"),
                ]),
                VocabTopic(id: "uk-talk", title: "Разговор", words: [
                    .init(ru: "привет", uk: "привіт"),
                    .init(ru: "спасибо", uk: "дякую"),
                    .init(ru: "пожалуйста", uk: "будь ласка"),
                    .init(ru: "извини", uk: "вибач"),
                    .init(ru: "как дела", uk: "як справи"),
                    .init(ru: "понимаю", uk: "розумію"),
                    .init(ru: "конечно", uk: "звісно"),
                    .init(ru: "позже", uk: "пізніше"),
                ]),
            ]
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
            added.append(VocabWord(ru: candidate.ru, uk: candidate.target, isActive: true, isCustom: true))
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
            added.append(VocabWord(ru: word.ru, uk: word.uk, isActive: true, isCustom: true))
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

/// Уровень сложности. Считается не на глаз: это диапазон позиций слова в
/// частотном списке живой речи.
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

struct VocabLevelWord: Codable {
    let ru: String
    let target: String
    let level: String
}

struct VocabLevelPackFile: Codable {
    let language: String
    let words: [VocabLevelWord]
}
