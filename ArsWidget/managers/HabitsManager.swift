//
//  HabitsManager.swift
//  ArsWidget
//
//  Трекер привычек под напоминаниями. Напоминание — про одно дело в один
//  день, привычка — про то, что повторяется: смысл в непрерывности, а не в
//  отдельной галочке. Поэтому здесь хранятся не задачи, а отмеченные дни.
//
//  Всё лежит на этом Mac, в настройках приложения. Никуда не отправляется.
//

import Foundation
import SwiftUI

struct Habit: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    /// План: сколько дней хочется продержаться.
    var goalDays: Int = 21
    /// Отмеченные дни в виде «2026-08-09» — календарная дата, а не момент
    /// времени: отметка в 23:59 и в 00:01 не должны попадать в один день.
    var doneDays: Set<String> = []
    var createdAt: Date = Date()
}

@MainActor
final class HabitsManager: ObservableObject {
    static let shared = HabitsManager()

    /// Сколько дней видно в строке привычки.
    static let visibleDays = 7
    static let goalOptions = [7, 14, 21, 30, 66]

    @Published private(set) var habits: [Habit] = []

    private let storageKey = "arswidgetHabitsV1"

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private init() {
        load()
    }

    // MARK: Дни

    static func key(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Последние дни, от старого к сегодняшнему.
    var recentDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<Self.visibleDays).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    func isDone(_ habit: Habit, on date: Date) -> Bool {
        habit.doneDays.contains(Self.key(for: date))
    }

    // MARK: Изменения

    func add(title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !habits.contains(where: { $0.title.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        habits.append(Habit(title: String(clean.prefix(60))))
        save()
    }

    func remove(_ habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        save()
    }

    func toggle(_ habit: Habit, on date: Date) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        let key = Self.key(for: date)
        if habits[index].doneDays.contains(key) {
            habits[index].doneDays.remove(key)
        } else {
            habits[index].doneDays.insert(key)
        }
        save()
    }

    func setGoal(_ habit: Habit, days: Int) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index].goalDays = max(1, days)
        save()
    }

    // MARK: Показатели

    /// Сколько дней подряд отмечено. Сегодня ещё не отмечено — цепочка
    /// считается по вчерашний день, иначе она обнулялась бы каждое утро.
    func streak(for habit: Habit) -> Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        if !habit.doneDays.contains(Self.key(for: day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while habit.doneDays.contains(Self.key(for: day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    func progress(for habit: Habit) -> Double {
        guard habit.goalDays > 0 else { return 0 }
        return min(1, Double(habit.doneDays.count) / Double(habit.goalDays))
    }

    // MARK: Хранение

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Habit].self, from: data)
        else { return }
        habits = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(habits) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
