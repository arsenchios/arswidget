import Foundation

struct VocabSessionAvailability {
    enum Suspension: Hashable { case screenLocked, screensAsleep, systemAsleep }
    private var suspensions: Set<Suspension> = []
    var permitsPrompts: Bool { suspensions.isEmpty }

    /// Resume only after every overlapping sleep/lock condition has ended.
    mutating func setSuspended(_ reason: Suspension, suspended: Bool) -> Bool {
        let wasAvailable = permitsPrompts
        if suspended { suspensions.insert(reason) }
        else { suspensions.remove(reason) }
        return wasAvailable != permitsPrompts
    }
}

/// Optional additions preserve progress written by every earlier app version.
struct VocabWord: Identifiable, Codable, Equatable {
    var id: String { ru }
    let ru: String
    var uk: String
    var isActive: Bool = false
    var isCustom: Bool = false
    var box: Int = 0
    var timesShown: Int = 0
    var timesKnown: Int = 0
    var reviewDueAt: Date?
    var reviewAfterNewWords: Int?
    var lastAnsweredAt: Date?
    var reviewStage: Int?
    var isExcluded: Bool?
    var isPaused: Bool?
    var category: String?
    var example: String?
    var exampleTranslation: String?
    var priority: Int?
}

struct VocabLevelWord: Codable {
    let ru: String
    let target: String
    let level: String
    var category: String?
    var example: String?
    var exampleTranslation: String?
    var priority: Int?
}

struct VocabLevelPackFile: Codable {
    let language: String
    let words: [VocabLevelWord]
}

/// A transparent, deterministic schedule, not an unvalidated claim of optimal
/// intervals: retrieval after 30 minutes, then 1 / 7 / 21 / 60 / 120 days.
enum VocabReviewSchedule {
    static let intervals: [TimeInterval] = [30 * 60, 86400, 7 * 86400, 21 * 86400, 60 * 86400, 120 * 86400]

    static func answer(_ word: inout VocabWord, recalled: Bool, now: Date) {
        word.lastAnsweredAt = now
        word.reviewAfterNewWords = nil
        word.isExcluded = false
        word.isPaused = false
        if recalled {
            word.timesKnown += 1
            let previous = word.reviewStage ?? min(2, max(0, word.box))
            let stage = min(intervals.count, previous + 1)
            word.reviewStage = stage
            word.box = stage >= 3 ? 4 : stage
            word.isActive = stage < 3
            word.reviewDueAt = now.addingTimeInterval(intervals[stage - 1])
        } else {
            word.reviewStage = 0
            word.box = 0
            word.isActive = true
            word.reviewDueAt = now.addingTimeInterval(10 * 60)
        }
    }

    static func exclude(_ word: inout VocabWord) {
        word.isExcluded = true
        word.isActive = false
        word.box = 4
        word.reviewDueAt = nil
        word.reviewAfterNewWords = nil
    }

    static func isDue(_ word: VocabWord, now: Date) -> Bool {
        guard word.isExcluded != true, word.isPaused != true else { return false }
        if let due = word.reviewDueAt { return due <= now }
        return word.isActive && word.box < 4
    }

    static func maskedExample(for word: VocabWord) -> String? {
        guard let example = word.example,
              let range = example.range(of: word.uk, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        return example.replacingCharacters(in: range, with: "____")
    }

    static func applyMetadata(_ entry: VocabLevelWord, to word: inout VocabWord) {
        if !word.isCustom { word.uk = entry.target }
        word.category = entry.category
        word.example = entry.example
        word.exampleTranslation = entry.exampleTranslation
        word.priority = entry.priority
    }
}

/// Refill only due slots. Waiting cards keep their schedule; manually paused,
/// deleted and excluded cards cannot sneak back in through automatic refill.
enum VocabStudyQueue {
    static func currentStage(catalog: [VocabLevelWord], words: [VocabWord],
                             levels: [String], deleted: Set<String>) -> [VocabLevelWord] {
        let saved = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for level in levels {
            let entries = catalog.filter { $0.level == level }
            let unfinished = entries.contains { entry in
                guard !deleted.contains(entry.ru) else { return false }
                guard let word = saved[entry.ru] else { return true }
                return word.box < 4 && word.isExcluded != true && word.isPaused != true
            }
            if unfinished { return entries }
        }
        return []
    }

    static func refill(_ words: inout [VocabWord], catalog: [VocabLevelWord],
                       deleted: Set<String>, target: Int, now: Date) -> Int {
        let due = words.filter { VocabReviewSchedule.isDue($0, now: now) }.count
        var needed = max(0, min(20, max(0, target)) - due)
        var byID = Dictionary(words.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var introduced = 0
        for entry in catalog where needed > 0 && !deleted.contains(entry.ru) {
            if let i = byID[entry.ru] {
                guard !words[i].isActive, words[i].box < 4,
                      words[i].reviewDueAt == nil,
                      words[i].isExcluded != true, words[i].isPaused != true else { continue }
                words[i].isActive = true
                VocabReviewSchedule.applyMetadata(entry, to: &words[i])
            } else {
                var word = VocabWord(ru: entry.ru, uk: entry.target, isActive: true)
                VocabReviewSchedule.applyMetadata(entry, to: &word)
                byID[entry.ru] = words.count
                words.append(word)
            }
            needed -= 1
            introduced += 1
        }
        return introduced
    }
}

/// Presentation lifetime belongs to the window model, not a transient SwiftUI branch.
struct VocabPromptPresentation {
    enum Effect: Equatable { case present, restoreOpen, fold }
    private(set) var isPresented = false
    private var restoreOpen = false

    mutating func synchronize(visible: Bool, hasWord: Bool, windowWasOpen: Bool) -> Effect? {
        let shouldPresent = visible && hasWord
        if shouldPresent && !isPresented {
            restoreOpen = windowWasOpen
            isPresented = true
            return .present
        }
        if !shouldPresent && isPresented {
            isPresented = false
            return restoreOpen ? .restoreOpen : .fold
        }
        return nil
    }

    mutating func cancel() {
        isPresented = false
        restoreOpen = false
    }
}
