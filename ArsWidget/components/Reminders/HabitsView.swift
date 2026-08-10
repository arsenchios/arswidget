//
//  HabitsView.swift
//  ArsWidget
//
//  Недельный трекер привычек с понедельника: буквы и кружки используют одну
//  сетку, поэтому отметка всегда стоит ровно под своим днём.
//

import SwiftUI

private enum HabitLayout {
    static let daySize: CGFloat = 20
    static let daySpacing: CGFloat = 8
    static let weekWidth = daySize * 7 + daySpacing * 6
    static let trailingControlsWidth: CGFloat = 144
}

struct HabitsView: View {
    @EnvironmentObject private var vm: ArsWidgetViewModel
    @ObservedObject private var habits = HabitsManager.shared
    @State private var newHabitTitle = ""
    @State private var newHabitColor: HabitColor = .green
    @FocusState private var isFieldFocused: Bool

    private var days: [Date] { habits.weekDays }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            if habits.habits.isEmpty {
                Text("Пока нет привычек. Напишите ту, которую хотите держать каждый день.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.vertical, 6)
            } else {
                weekdayHeader
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(habits.habits) { habit in
                            HabitRow(
                                habit: habit,
                                days: days,
                                isMonthExpanded: habits.expandedMonthHabitID == habit.id,
                                onToggleMonth: {
                                    withAnimation(.smooth) {
                                        habits.expandedMonthHabitID = habits.expandedMonthHabitID == habit.id ? nil : habit.id
                                    }
                                }
                            )

                            if habits.expandedMonthHabitID == habit.id {
                                HabitMonthGrid(habit: habit)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: habits.expandedMonthHabitID == nil ? 128 : 292)
            }
        }
        .padding(.top, 2)
        .onChange(of: habits.expandedMonthHabitID) { _, _ in
            vm.updateOpenSizeIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Привычки")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            TextField("Новая привычка", text: $newHabitTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($isFieldFocused)
                .onSubmit(addHabit)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.06))
                )
                .frame(maxWidth: 220)

            Menu {
                ForEach(HabitColor.allCases) { color in
                    Button {
                        newHabitColor = color
                    } label: {
                        Label(color.title, systemImage: color == newHabitColor ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                Circle()
                    .fill(newHabitColor.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .help(Text("Цвет новой привычки"))

            Button(action: addHabit) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.white.opacity(newHabitTitle.isEmpty ? 0.25 : 0.75))
            }
            .buttonStyle(.plain)
            .disabled(newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer(minLength: 0)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            HStack(spacing: HabitLayout.daySpacing) {
                ForEach(days, id: \.self) { day in
                    Text(Self.weekdayLetter(day))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(width: HabitLayout.daySize)
                }
            }
            .frame(width: HabitLayout.weekWidth)
            Color.clear.frame(width: HabitLayout.trailingControlsWidth, height: 1)
        }
        .padding(.horizontal, 8)
    }

    private static func weekdayLetter(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        return ["В", "П", "В", "С", "Ч", "П", "С"][max(0, min(6, weekday - 1))]
    }

    private func addHabit() {
        habits.add(title: newHabitTitle, color: newHabitColor)
        newHabitTitle = ""
        isFieldFocused = false
    }
}

private struct HabitRow: View {
    let habit: Habit
    let days: [Date]
    let isMonthExpanded: Bool
    let onToggleMonth: () -> Void
    @ObservedObject private var manager = HabitsManager.shared
    @State private var isHovering = false

    private var doneCount: Int { habit.doneDays.count }
    private var streak: Int { manager.streak(for: habit) }
    private var isGoalReached: Bool { doneCount >= habit.goalDays }

    var body: some View {
        HStack(spacing: 8) {
            Text(habit.title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 6)

            HStack(spacing: HabitLayout.daySpacing) {
                ForEach(days, id: \.self) { day in
                    dayCircle(day)
                }
            }
            .frame(width: HabitLayout.weekWidth)

            trailingControls
                .frame(width: HabitLayout.trailingControlsWidth, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
        .onHover { isHovering = $0 }
    }

    private var trailingControls: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(HabitColor.allCases) { color in
                    Button(color.title) { manager.setColor(habit, color: color) }
                }
            } label: {
                Circle()
                    .fill(habit.color.color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .help(Text("Изменить цвет привычки"))

            Button(action: onToggleMonth) {
                Image(systemName: isMonthExpanded ? "calendar.badge.minus" : "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(isMonthExpanded ? 0.9 : 0.55))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(Text(isMonthExpanded ? "Скрыть месяц" : "Показать месяц"))

            Menu {
                ForEach(HabitsManager.goalOptions, id: \.self) { option in
                    Button("План \(option) дней") { manager.setGoal(habit, days: option) }
                }
            } label: {
                Text("\(doneCount)/\(habit.goalDays)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isGoalReached ? .green : .white.opacity(0.7))
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(Text("Нажмите, чтобы изменить план"))

            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
                Text("\(streak)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(streak > 0 ? .orange : .white.opacity(0.25))
            .frame(width: 30, alignment: .leading)
            .help(Text("Дней подряд"))

            Button {
                manager.remove(habit)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(isHovering ? 0.75 : 0.25))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Удалить привычку"))
        }
    }

    private func dayCircle(_ day: Date) -> some View {
        let isDone = manager.isDone(habit, on: day)
        let isToday = Calendar.current.isDateInToday(day)

        return Button {
            manager.toggle(habit, on: day)
        } label: {
            ZStack {
                Circle()
                    .fill(isDone ? habit.color.color.opacity(0.9) : Color.white.opacity(0.09))
                if isToday {
                    Circle()
                        .stroke(habit.color.color.opacity(isDone ? 0.85 : 0.7), lineWidth: 1.3)
                }
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.black.opacity(0.65))
                }
            }
            .frame(width: HabitLayout.daySize, height: HabitLayout.daySize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(day.formatted(.dateTime.day().month(.wide))))
    }
}

private struct HabitMonthGrid: View {
    let habit: Habit
    @ObservedObject private var manager = HabitsManager.shared
    @State private var month = Date()

    private let columns = Array(repeating: GridItem(.fixed(HabitLayout.daySize), spacing: HabitLayout.daySpacing), count: 7)

    private var calendar: Calendar { Calendar.current }

    private var dates: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }

        let weekday = calendar.component(.weekday, from: first)
        let leadingEmptyDays = (weekday + 5) % 7
        var result = Array<Date?>(repeating: nil, count: leadingEmptyDays)
        result += range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Button {
                    month = calendar.date(byAdding: .month, value: -1, to: month) ?? month
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 130)

                Button {
                    month = calendar.date(byAdding: .month, value: 1, to: month) ?? month
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                Spacer()
                Text("Месяц")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Array(["П", "В", "С", "Ч", "П", "С", "В"].enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.38))
                        .frame(width: HabitLayout.daySize)
                }

                ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                    if let date {
                        monthDay(date)
                    } else {
                        Color.clear.frame(width: HabitLayout.daySize, height: HabitLayout.daySize)
                    }
                }
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private func monthDay(_ day: Date) -> some View {
        let done = manager.isDone(habit, on: day)
        let today = calendar.isDateInToday(day)
        return Button {
            manager.toggle(habit, on: day)
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(done ? .black.opacity(0.72) : .white.opacity(0.65))
                .frame(width: HabitLayout.daySize, height: HabitLayout.daySize)
                .background(done ? habit.color.color.opacity(0.92) : Color.white.opacity(0.08), in: Circle())
                .overlay {
                    if today {
                        Circle().stroke(habit.color.color.opacity(0.9), lineWidth: 1.2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(Text(day.formatted(.dateTime.day().month(.wide).year())))
    }
}

#Preview {
    HabitsView()
        .frame(width: 620)
        .padding()
        .background(.black)
        .environmentObject(ArsWidgetViewModel())
}
