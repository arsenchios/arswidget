import Foundation

@main
struct VocabLearningTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldJSON = """
        [{"ru":"почему","uk":"чому","isActive":true,"isCustom":false,"box":1,"timesShown":2,"timesKnown":1}]
        """
        var legacy = try JSONDecoder().decode([VocabWord].self, from: Data(oldJSON.utf8))[0]
        precondition(legacy.timesKnown == 1 && legacy.reviewStage == nil)
        VocabReviewSchedule.answer(&legacy, recalled: true, now: now)
        precondition(legacy.reviewStage == 2 && legacy.timesKnown == 2)
        precondition(legacy.reviewDueAt == now.addingTimeInterval(86400))

        var word = VocabWord(ru: "зачем", uk: "навіщо", isActive: true,
                             example: "Навіщо це потрібно?", exampleTranslation: "Зачем это нужно?")
        precondition(VocabReviewSchedule.maskedExample(for: word) == "____ це потрібно?")
        var answeredAt = now
        for stage in 1...6 {
            VocabReviewSchedule.answer(&word, recalled: true, now: answeredAt)
            precondition(word.reviewStage == stage)
            precondition(!VocabReviewSchedule.isDue(word, now: answeredAt))
            precondition(word.reviewDueAt == answeredAt.addingTimeInterval(VocabReviewSchedule.intervals[stage-1]))
            answeredAt = word.reviewDueAt!
            precondition(VocabReviewSchedule.isDue(word, now: answeredAt))
            if stage == 3 { precondition(word.box == 4 && !word.isActive) }
        }
        VocabReviewSchedule.answer(&word, recalled: false, now: answeredAt)
        precondition(word.box == 0 && word.reviewStage == 0 && word.isActive)
        precondition(word.reviewDueAt == answeredAt.addingTimeInterval(600))
        VocabReviewSchedule.exclude(&word)
        precondition(!VocabReviewSchedule.isDue(word, now: answeredAt.addingTimeInterval(365 * 86400)))
        precondition(word.reviewDueAt == nil)
        let restored = try JSONDecoder().decode(VocabWord.self, from: JSONEncoder().encode(word))
        precondition(restored == word && restored.isExcluded == true)

        let path = CommandLine.arguments.dropFirst().first ?? "ArsWidget/Resources/vocab-ukrainian.json"
        let pack = try JSONDecoder().decode(VocabLevelPackFile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        precondition(pack.words.count == 189)
        precondition(Set(pack.words.map(\.ru)).count == pack.words.count)
        precondition(Set(pack.words.map(\.priority)).count == pack.words.count)
        for entry in pack.words {
            var item = VocabWord(ru: entry.ru, uk: entry.target)
            VocabReviewSchedule.applyMetadata(entry, to: &item)
            precondition(item.example?.isEmpty == false && item.exampleTranslation?.isEmpty == false)
            precondition(VocabReviewSchedule.maskedExample(for: item) != nil, "Missing answer in example: \(entry.ru)")
        }
        let ukrainianTokens = try NSRegularExpression(pattern: "[А-Яа-яІіЇїЄєҐґ\\u0301]+(?:['’][А-Яа-яІіЇїЄєҐґ\\u0301]+)*")
        let vowels = Set("аеєиіїоуюяАЕЄИІЇОУЮЯ")
        for entry in pack.words {
            for text in [entry.target, entry.example ?? ""] {
                for match in ukrainianTokens.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let token = String(text[Range(match.range, in: text)!])
                    let scalars = Array(token.unicodeScalars)
                    if scalars.contains(where: { vowels.contains(Character(String($0))) }) {
                        precondition(scalars.filter { $0.value == 0x301 }.count == 1, "Missing/ambiguous stress: \(token)")
                    }
                    for i in scalars.indices where scalars[i].value == 0x301 {
                        precondition(i > 0 && vowels.contains(Character(String(scalars[i - 1]))))
                    }
                }
            }
        }
        // Adding pronunciation must preserve identity, scheduling and exclusion.
        var accentedLegacy = restored
        accentedLegacy.uk = "навіщо"
        VocabReviewSchedule.applyMetadata(pack.words[0], to: &accentedLegacy)
        precondition(accentedLegacy.id == restored.id && accentedLegacy.isExcluded == true)
        precondition(accentedLegacy.reviewStage == restored.reviewStage)
        precondition(accentedLegacy.uk == "наві́що")
        precondition(VocabReviewSchedule.maskedExample(for: accentedLegacy) == "____ це́ потрі́бно?")
        precondition(pack.words.first?.ru == "зачем")
        precondition(pack.words.contains { $0.ru == "подскажите, пожалуйста" })
        precondition(pack.words.contains { $0.ru == "пешеходный переход" })
        precondition(!pack.words.contains { $0.ru == "ли" || $0.target == "лі́" })

        var queue = [word, VocabWord(ru: "почему", uk: "чому", isPaused: true)]
        let deleted: Set<String> = ["что именно"]
        let count = VocabStudyQueue.refill(&queue, catalog: pack.words, deleted: deleted, target: 6, now: now)
        precondition(count == 6 && queue.filter { VocabReviewSchedule.isDue($0, now: now) }.count == 6)
        precondition(!queue.contains { $0.ru == "что именно" })
        precondition(queue.first?.isExcluded == true && queue[1].isPaused == true)
        precondition(VocabStudyQueue.refill(&queue, catalog: pack.words, deleted: deleted, target: 6, now: now) == 0)
        let i = queue.firstIndex { VocabReviewSchedule.isDue($0, now: now) }!
        VocabReviewSchedule.answer(&queue[i], recalled: true, now: now)
        precondition(VocabStudyQueue.refill(&queue, catalog: pack.words, deleted: deleted, target: 6, now: now) == 1)
        let waiting = queue[i].reviewDueAt
        _ = VocabStudyQueue.refill(&queue, catalog: pack.words, deleted: deleted, target: 6, now: now)
        precondition(queue[i].reviewDueAt == waiting)
        let saved = try JSONDecoder().decode([VocabWord].self, from: JSONEncoder().encode(queue))
        precondition(saved == queue)
        let firstStage = VocabStudyQueue.currentStage(catalog: pack.words, words: [], levels: ["A1", "A2", "B1", "B2"], deleted: [])
        precondition(firstStage.allSatisfy { $0.level == "A1" })
        var completed = firstStage.map { VocabWord(ru: $0.ru, uk: $0.target, box: 4, isExcluded: true) }
        let nextStage = VocabStudyQueue.currentStage(catalog: pack.words, words: completed, levels: ["A1", "A2", "B1", "B2"], deleted: [])
        precondition(!nextStage.isEmpty && nextStage.allSatisfy { $0.level == "A2" })
        completed[0].box = 1; completed[0].isExcluded = false; completed[0].reviewDueAt = now.addingTimeInterval(86400)
        precondition(VocabStudyQueue.currentStage(catalog: pack.words, words: completed, levels: ["A1", "A2", "B1", "B2"], deleted: []).allSatisfy { $0.level == "A1" })
        print("Vocab schedule, migration, exclusions, queue, persistence and 189 fully accented contextual cards: PASS")
    }
}
