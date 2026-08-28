//
//  GoalsView.swift
//  ArsWidget
//
//  Три горизонта вместо одного бесконечного списка: «Сейчас» держит фокус,
//  «Дальше» сохраняет следующие направления, «Мечты» не дают потерять желания.
//

import SwiftUI

struct GoalsView: View {
    @EnvironmentObject private var vm: ArsWidgetViewModel
    @ObservedObject private var goals = GoalsManager.shared

    @State private var selectedHorizon: GoalHorizon = .now
    @State private var newGoalTitle = ""
    @State private var newGoalArea: GoalArea = .personal
    @FocusState private var isFieldFocused: Bool

    private var visibleGoals: [GoalItem] {
        goals.goals
            .filter { $0.horizon == selectedHorizon }
            .sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                return $0.createdAt < $1.createdAt
            }
    }

    private var completedCount: Int {
        visibleGoals.filter(\.isCompleted).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            addGoalRow

            if visibleGoals.isEmpty {
                Text("Здесь пока пусто.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 5)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(visibleGoals) { goal in
                            GoalRow(goal: goal)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: 190)
            }
        }
        .padding(.top, 2)
        .onAppear {
            vm.updateOpenSizeIfNeeded()
        }
        .onChange(of: selectedHorizon) { _, _ in
            vm.updateOpenSizeIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Цели")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 4) {
                ForEach(GoalHorizon.allCases) { horizon in
                    Button {
                        withAnimation(.smooth(duration: 0.18)) {
                            selectedHorizon = horizon
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: horizon.symbol)
                                .font(.system(size: 8, weight: .semibold))
                            Text(horizon.title)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(selectedHorizon == horizon ? .black.opacity(0.78) : .white.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(selectedHorizon == horizon ? horizon.color.opacity(0.9) : Color.white.opacity(0.055))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Text("\(completedCount)/\(visibleGoals.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
        }
    }

    private var addGoalRow: some View {
        HStack(spacing: 7) {
            Menu {
                ForEach(GoalArea.allCases) { area in
                    Button {
                        newGoalArea = area
                    } label: {
                        Label(area.title, systemImage: area.symbol)
                    }
                }
            } label: {
                Image(systemName: newGoalArea.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selectedHorizon.color.opacity(0.8))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.055), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .help(Text(newGoalArea.title))

            TextField("Новая цель в «\(selectedHorizon.title)»", text: $newGoalTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .focused($isFieldFocused)
                .onSubmit(addGoal)

            Button(action: addGoal) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(cleanNewGoal.isEmpty ? 0.22 : 0.72))
            }
            .buttonStyle(.plain)
            .disabled(cleanNewGoal.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private var cleanNewGoal: String {
        newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addGoal() {
        guard !cleanNewGoal.isEmpty else { return }
        goals.add(title: cleanNewGoal, horizon: selectedHorizon, area: newGoalArea)
        newGoalTitle = ""
        isFieldFocused = false
        vm.updateOpenSizeIfNeeded()
    }
}

private struct GoalRow: View {
    let goal: GoalItem
    @ObservedObject private var manager = GoalsManager.shared
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                manager.toggle(goal)
            } label: {
                Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(goal.isCompleted ? .green : goal.horizon.color.opacity(0.75))
            }
            .buttonStyle(.plain)

            Image(systemName: goal.area.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .frame(width: 13)
                .help(Text(goal.area.title))

            Text(goal.title)
                .font(.system(size: 11))
                .foregroundStyle(goal.isCompleted ? .white.opacity(0.34) : .white.opacity(0.88))
                .strikethrough(goal.isCompleted)
                .lineLimit(2)

            Spacer(minLength: 6)

            Text(goal.area.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.28))
                .lineLimit(1)

            Menu {
                ForEach(GoalHorizon.allCases) { horizon in
                    Button {
                        manager.setHorizon(goal, horizon: horizon)
                    } label: {
                        Label(horizon.title, systemImage: horizon.symbol)
                    }
                }

                Divider()

                ForEach(GoalArea.allCases) { area in
                    Button {
                        manager.setArea(goal, area: area)
                    } label: {
                        Label(area.title, systemImage: area.symbol)
                    }
                }

                Divider()

                Button(role: .destructive) {
                    manager.remove(goal)
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(isHovering ? 0.65 : 0.24))
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
    }
}

#Preview {
    GoalsView()
        .frame(width: 620)
        .padding()
        .background(.black)
        .environmentObject(ArsWidgetViewModel())
}
