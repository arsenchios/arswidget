//
//  HabitsView.swift
//  ArsWidget
//
//  Живёт под напоминаниями на той же вкладке. Напоминание закрывается один
//  раз, привычка держится днями — поэтому здесь не список дел, а неделя
//  кружков: видно, где цепочка не прервалась, и сколько дней из плана уже
//  набрано.
//

import SwiftUI

struct HabitsView: View {
    @ObservedObject private var habits = HabitsManager.shared
    @State private var newHabitTitle = ""
    @FocusState private var isFieldFocused: Bool

    private var days: [Date] { habits.recentDays }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if habits.habits.isEmpty {
                Text("Пока нет привычек. Напишите ту, которую хотите держать каждый день.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.vertical, 6)
            } else {
                weekdayHeader
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(habits.habits) { habit in
                            HabitRow(habit: habit, days: days)
                        }
                    }
                }
                .frame(maxHeight: 118)
            }
        }
        .padding(.top, 2)
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

            Button(action: addHabit) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.white.opacity(newHabitTitle.isEmpty ? 0.25 : 0.75))
            }
            .buttonStyle(.plain)
            .disabled(newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer(minLength: 0)
        }
    }

    /// Буквы дней недели ровно над кружками, чтобы «сегодня» читалось без счёта.
    private var weekdayHeader: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(days, id: \.self) { day in
                    Text(Self.weekdayLetter(day))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 16)
                }
            }
            // Место под «12/21», цепочку и крестик в строках ниже.
            Color.clear.frame(width: 116, height: 1)
        }
    }

    private static func weekdayLetter(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        // 1 = воскресенье
        return ["В", "П", "В", "С", "Ч", "П", "С"][max(0, min(6, weekday - 1))]
    }

    private func addHabit() {
        habits.add(title: newHabitTitle)
        newHabitTitle = ""
        isFieldFocused = false
    }
}

private struct HabitRow: View {
    let habit: Habit
    let days: [Date]
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

            HStack(spacing: 5) {
                ForEach(days, id: \.self) { day in
                    dayCircle(day)
                }
            }

            // План: сколько дней уже набрано из задуманного.
            Menu {
                ForEach(HabitsManager.goalOptions, id: \.self) { option in
                    Button("План \(option) дней") { manager.setGoal(habit, days: option) }
                }
            } label: {
                Text("\(doneCount)/\(habit.goalDays)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isGoalReached ? .green : .white.opacity(0.7))
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("Нажмите, чтобы изменить план"))

            // Цепочка — то, ради чего трекер и нужен.
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
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
        .onHover { isHovering = $0 }
    }

    private func dayCircle(_ day: Date) -> some View {
        let isDone = manager.isDone(habit, on: day)
        let isToday = Calendar.current.isDateInToday(day)

        return Button {
            manager.toggle(habit, on: day)
        } label: {
            ZStack {
                Circle()
                    .fill(isDone ? Color.green.opacity(0.85) : Color.white.opacity(0.09))
                // Сегодняшний день обведён — чтобы не отметить вчерашний по ошибке.
                if isToday {
                    Circle()
                        .stroke(Color.white.opacity(isDone ? 0.55 : 0.35), lineWidth: 1.2)
                }
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black.opacity(0.65))
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(day.formatted(.dateTime.day().month(.wide))))
    }
}

#Preview {
    HabitsView()
        .frame(width: 620)
        .padding()
        .background(.black)
}
