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
    var goalDays: Int = 21
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

    static let visibleDays = 7
    static let goalOptions = [7, 14, 21, 30, 66]

    @Published private(set) var habits: [Habit] = []
    @Published var expandedMonthHabitID: Habit.ID?

    private let storageKey = "arswidgetHabitsV1"
    private let personalSeedKey = "arswidgetPersonalHabitsSeedV1"

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private init() {
        load()
        seedPersonalHabitsIfNeeded()
    }

    static func key(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % Self.visibleDays
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) else { return [] }
        return (0..<Self.visibleDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: monday)
        }
    }

    func isDone(_ habit: Habit, on date: Date) -> Bool {
        habit.doneDays.contains(Self.key(for: date))
    }

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

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Habit].self, from: data)
        else { return }
        habits = decoded
    }

    private func seedPersonalHabitsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: personalSeedKey) else { return }

        let suggested: [(String, HabitColor)] = [
            ("Украинский — 10 минут", .blue),
            ("Голос / дикция — 10 минут", .purple),
            ("Отжимания + растяжка — 10 минут", .green),
            ("Медитация / чистое состояние — 10 минут", .teal),
            ("Порядок и опрятность — 5 минут", .orange)
        ]

        for (title, color) in suggested where !habits.contains(where: {
            $0.title.caseInsensitiveCompare(title) == .orderedSame
        }) {
            habits.append(Habit(title: title, color: color))
        }

        UserDefaults.standard.set(true, forKey: personalSeedKey)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(habits) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - Личные цели

enum GoalHorizon: String, CaseIterable, Codable, Identifiable {
    case now
    case next
    case dream

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: "Сейчас"
        case .next: "Дальше"
        case .dream: "Мечты"
        }
    }

    var symbol: String {
        switch self {
        case .now: "bolt.fill"
        case .next: "arrow.right.circle.fill"
        case .dream: "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .now: .orange
        case .next: .blue
        case .dream: .purple
        }
    }
}

enum GoalArea: String, CaseIterable, Codable, Identifiable {
    case work
    case content
    case family
    case sport
    case travel
    case purchase
    case relationship
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: "Работа"
        case .content: "Контент"
        case .family: "Семья"
        case .sport: "Спорт"
        case .travel: "Путешествия"
        case .purchase: "Покупки"
        case .relationship: "Отношения"
        case .personal: "Личное"
        }
    }

    var symbol: String {
        switch self {
        case .work: "briefcase.fill"
        case .content: "play.rectangle.fill"
        case .family: "house.fill"
        case .sport: "figure.run"
        case .travel: "airplane"
        case .purchase: "bag.fill"
        case .relationship: "heart.fill"
        case .personal: "person.fill"
        }
    }
}

struct GoalItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var horizon: GoalHorizon
    var area: GoalArea
    var isCompleted: Bool = false
    var createdAt: Date = Date()
}

@MainActor
final class GoalsManager: ObservableObject {
    static let shared = GoalsManager()

    @Published private(set) var goals: [GoalItem] = []

    private let storageKey = "arswidgetGoalsV1"

    private init() {
        loadOrSeed()
    }

    func add(title: String, horizon: GoalHorizon, area: GoalArea = .personal) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !goals.contains(where: { $0.title.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        goals.append(GoalItem(title: String(clean.prefix(120)), horizon: horizon, area: area))
        save()
    }

    func toggle(_ goal: GoalItem) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index].isCompleted.toggle()
        save()
    }

    func setHorizon(_ goal: GoalItem, horizon: GoalHorizon) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index].horizon = horizon
        save()
    }

    func setArea(_ goal: GoalItem, area: GoalArea) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index].area = area
        save()
    }

    func remove(_ goal: GoalItem) {
        goals.removeAll { $0.id == goal.id }
        save()
    }

    private func loadOrSeed() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([GoalItem].self, from: data) {
            goals = decoded
            return
        }

        goals = Self.initialGoals
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static let initialGoals: [GoalItem] = [
        GoalItem(title: "Купить Мартину годовую визу", horizon: .now, area: .family),
        GoalItem(title: "Выпустить Charlie и получить 5 продаж", horizon: .now, area: .work),
        GoalItem(title: "Взять ещё 3 клиентов на психологию", horizon: .now, area: .work),
        GoalItem(title: "Выстроить систему контента и сторителлинга: Charlie, аффирмации, таролог, тесты и воронки", horizon: .now, area: .content),
        GoalItem(title: "Развивать Volux и клиентские проекты мощнее", horizon: .now, area: .work),
        GoalItem(title: "Регулярно снимать Reels, подкасты и YouTube", horizon: .now, area: .content),

        GoalItem(title: "YouTube: 10 000 подписчиков и 10 000 просмотров длинного ролика", horizon: .next, area: .content),
        GoalItem(title: "Instagram: 20 000 подписчиков", horizon: .next, area: .content),
        GoalItem(title: "Большой теннис с тренером", horizon: .next, area: .sport),
        GoalItem(title: "Падел с тренером", horizon: .next, area: .sport),
        GoalItem(title: "Снимать Мартину хорошую виллу / жильё", horizon: .next, area: .family),
        GoalItem(title: "Переехать с Яной в хорошую виллу у природы, с тенью и деревьями", horizon: .next, area: .family),
        GoalItem(title: "Регулярно делать Яне приятные и интересные подарки", horizon: .next, area: .relationship),

        GoalItem(title: "Путешествие в Китай", horizon: .dream, area: .travel),
        GoalItem(title: "Путешествие на Комодо", horizon: .dream, area: .travel),
        GoalItem(title: "Путешествие ещё в одну новую страну", horizon: .dream, area: .travel),
        GoalItem(title: "Новый iPhone", horizon: .dream, area: .purchase),
        GoalItem(title: "Новый MacBook Air", horizon: .dream, area: .purchase),
        GoalItem(title: "Байк Honda DV", horizon: .dream, area: .purchase)
    ]
}
