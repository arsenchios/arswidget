//
//  GoalsManager.swift
//  ArsWidget
//
//  Личные цели живут отдельно от Apple Reminders и привычек.
//  Напоминания = конкретные дела, привычки = повторяемые действия,
//  цели = направления и результаты, которые не хочется терять из виду.
//

import Foundation
import SwiftUI

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
        // Сейчас — не всё важное в жизни, а то, что стоит реально двигать ближайшим фокусом.
        GoalItem(title: "Купить Мартину годовую визу", horizon: .now, area: .family),
        GoalItem(title: "Выпустить Charlie и получить 5 продаж", horizon: .now, area: .work),
        GoalItem(title: "Взять ещё 3 клиентов на психологию", horizon: .now, area: .work),
        GoalItem(title: "Выстроить систему контента и сторителлинга: Charlie, аффирмации, таролог, тесты и воронки", horizon: .now, area: .content),
        GoalItem(title: "Развивать Volux и клиентские проекты мощнее", horizon: .now, area: .work),
        GoalItem(title: "Регулярно снимать Reels, подкасты и YouTube", horizon: .now, area: .content),

        // Дальше — конкретные направления, которые не нужно тащить в ежедневный фокус одновременно.
        GoalItem(title: "YouTube: 10 000 подписчиков и 10 000 просмотров длинного ролика", horizon: .next, area: .content),
        GoalItem(title: "Instagram: 20 000 подписчиков", horizon: .next, area: .content),
        GoalItem(title: "Большой теннис с тренером", horizon: .next, area: .sport),
        GoalItem(title: "Падел с тренером", horizon: .next, area: .sport),
        GoalItem(title: "Снимать Мартину хорошую виллу / жильё", horizon: .next, area: .family),
        GoalItem(title: "Переехать с Яной в хорошую виллу у природы, с тенью и деревьями", horizon: .next, area: .family),
        GoalItem(title: "Регулярно делать Яне приятные и интересные подарки", horizon: .next, area: .relationship),

        // Мечты — сохраняем, но не превращаем их в чувство долга на сегодня.
        GoalItem(title: "Путешествие в Китай", horizon: .dream, area: .travel),
        GoalItem(title: "Путешествие на Комодо", horizon: .dream, area: .travel),
        GoalItem(title: "Путешествие ещё в одну новую страну", horizon: .dream, area: .travel),
        GoalItem(title: "Новый iPhone", horizon: .dream, area: .purchase),
        GoalItem(title: "Новый MacBook Air", horizon: .dream, area: .purchase),
        GoalItem(title: "Байк Honda DV", horizon: .dream, area: .purchase)
    ]
}
