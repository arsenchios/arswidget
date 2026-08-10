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

enum HabitColor: String, CaseIterable, Codable, Identifiable {
    case green, blue, purple, orange, pink, teal

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .orange: .orange
        case .pink: .pink
        case .teal: .teal
        }
    }

    var title: String {
        switch self {
        case .green: "Зелёный"
        case .blue: "Синий"
        case .purple: "Фиолетовый"
        case .orange: "Оранжевый"
        case .pink: "Розовый"
        case .teal: "Бирюзовый"
        }
    }
}

struct Habit: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    /// План: сколько дней хочется продержаться.
    var goalDays: Int = 21
    /// Отмеченные дни в виде «2026-08-09» — календарная дата, а не момент
    /// времени: отметка в 23:59 и в 00:01 не должны попадать в один день.
    var doneDays: Set<String> = []
    var createdAt: Date = Date()
    var color: HabitColor = .green

    private enum CodingKeys: String, CodingKey {
        case id, title, goalDays, doneDays, createdAt, color
    }

    init(
        id: UUID = UUID(),
        title: String,
        goalDays: Int = 21,
        doneDays: Set<String> = [],
        createdAt: Date = Date(),
        color: HabitColor = .green
    ) {
        self.id = id
        self.title = title
        self.goalDays = goalDays
        self.doneDays = doneDays
        self.createdAt = createdAt
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        goalDays = try container.decodeIfPresent(Int.self, forKey: .goalDays) ?? 21
        doneDays = try container.decodeIfPresent(Set<String>.self, forKey: .doneDays) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        color = try container.decodeIfPresent(HabitColor.self, forKey: .color) ?? .green
    }
}

@MainActor
final class HabitsManager: ObservableObject {
    static let shared = HabitsManager()

    /// Сколько дней видно в строке привычки.
    static let visibleDays = 7
    static let goalOptions = [7, 14, 21, 30, 66]

    @Published private(set) var habits: [Habit] = []
    @Published var expandedMonthHabitID: Habit.ID?

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

    /// Текущая неделя всегда начинается в понедельник, независимо от региона
    /// macOS. Так буквы, кружки и недельная статистика совпадают.
    var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // Calendar: 1 = воскресенье, 2 = понедельник.
        let daysSinceMonday = (weekday + 5) % Self.visibleDays
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) else { return [] }
        return (0..<Self.visibleDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: monday)
        }
    }

    func isDone(_ habit: Habit, on date: Date) -> Bool {
        habit.doneDays.contains(Self.key(for: date))
    }

    // MARK: Изменения

    func add(title: String, color: HabitColor = .green) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !habits.contains(where: { $0.title.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        habits.append(Habit(title: String(clean.prefix(60)), color: color))
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

    func setColor(_ habit: Habit, color: HabitColor) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index].color = color
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
