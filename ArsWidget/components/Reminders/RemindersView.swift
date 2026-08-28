//
//  RemindersView.swift
//  ArsWidget
//
//  Added in personal fork: dedicated notch tab for Apple Reminders — view
//  reminders from selected lists, mark them done, and quickly add a new one.
//

import SwiftUI
import Defaults

struct RemindersView: View {
    @EnvironmentObject var vm: ArsWidgetViewModel
    @ObservedObject var calendarManager = CalendarManager.shared
    @Default(.remindersPrimaryListID) private var primaryListID
    @Default(.remindersSecondaryListID) private var secondaryListID
    @State private var primaryNewReminderTitle: String = ""
    @State private var secondaryNewReminderTitle: String = ""
    @State private var primaryReminders: [EventModel] = []
    @State private var secondaryReminders: [EventModel] = []
    @FocusState private var focusedField: ReminderField?

    private enum ReminderField: Hashable {
        case primary
        case secondary
    }

    private var reminderLists: [CalendarModel] {
        calendarManager.reminderLists
    }

    private var resolvedPrimaryListID: String? {
        if let primaryListID, reminderLists.contains(where: { $0.id == primaryListID }) {
            return primaryListID
        }
        return reminderLists.first?.id
    }

    private var resolvedSecondaryListID: String? {
        guard let secondaryListID, reminderLists.contains(where: { $0.id == secondaryListID }) else {
            return nil
        }
        return secondaryListID
    }

    private var secondaryColumnEnabled: Bool {
        resolvedSecondaryListID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if calendarManager.reminderAuthorizationStatus != .fullAccess {
                permissionPrompt
            } else {
                remindersColumns
            }

            Divider().overlay(Color.white.opacity(0.1))
            HabitsView()

            Divider().overlay(Color.white.opacity(0.1))
            GoalsView()
        }
        .padding(.horizontal, 8)
        .task {
            await calendarManager.checkReminderAuthorization()
            initializeSelectionsIfNeeded()
            await reloadReminders()
        }
        .task(id: resolvedPrimaryListID) {
            guard calendarManager.reminderAuthorizationStatus == .fullAccess else { return }
            await reloadReminders()
        }
        .task(id: resolvedSecondaryListID) {
            guard calendarManager.reminderAuthorizationStatus == .fullAccess else { return }
            await reloadReminders()
        }
        .onChange(of: calendarManager.events) { _, _ in
            Task {
                guard calendarManager.reminderAuthorizationStatus == .fullAccess else { return }
                await reloadReminders()
            }
        }
        .onAppear {
            vm.updateOpenSizeIfNeeded()
        }
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Нет доступа к Напоминаниям")
                .font(.caption)
                .foregroundStyle(.gray)

            Button("Разрешить доступ") {
                Task { await calendarManager.checkReminderAuthorization() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }

    private func reminderListMenu(
        selection: Binding<String?>,
        fallbackTitle: String,
        includesNone: Bool
    ) -> some View {
        Menu {
            if includesNone {
                Button("Скрыть колонку") {
                    selection.wrappedValue = nil
                }
            }

            ForEach(reminderLists, id: \.id) { list in
                Button(list.title) {
                    selection.wrappedValue = list.id
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))

                Text(titleForList(selection.wrappedValue) ?? fallbackTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(listColor(for: selection.wrappedValue))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
    }

    private var remindersColumns: some View {
        HStack(alignment: .top, spacing: 12) {
            reminderColumn(
                listID: resolvedPrimaryListID,
                selection: Binding(
                    get: { resolvedPrimaryListID },
                    set: { primaryListID = $0 }
                ),
                title: titleForList(resolvedPrimaryListID) ?? "Напоминания",
                newReminderTitle: $primaryNewReminderTitle,
                field: .primary,
                includesNone: false,
                reminders: primaryReminders
            )

            if secondaryColumnEnabled {
                reminderColumn(
                    listID: resolvedSecondaryListID,
                    selection: $secondaryListID,
                    title: titleForList(resolvedSecondaryListID) ?? "Второй список",
                    newReminderTitle: $secondaryNewReminderTitle,
                    field: .secondary,
                    includesNone: true,
                    reminders: secondaryReminders
                )
            } else {
                addSecondListColumn
            }
        }
    }

    private var addSecondListColumn: some View {
        Button {
            secondaryListID = reminderLists.dropFirst().first?.id ?? reminderLists.first?.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Показать второй список")
                    .font(.caption)
                    .foregroundStyle(.white)

                Text("Нажми, чтобы вернуть вторую колонку.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))

                Image(systemName: "plus.circle")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    private func reminderColumn(
        listID: String?,
        selection: Binding<String?>,
        title: String,
        newReminderTitle: Binding<String>,
        field: ReminderField,
        includesNone: Bool,
        reminders: [EventModel]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            reminderListMenu(
                selection: selection,
                fallbackTitle: title,
                includesNone: includesNone
            )
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    addReminderField(
                        tint: listColor(for: listID),
                        text: newReminderTitle,
                        field: field,
                        onAdd: { addReminder(to: listID, text: newReminderTitle) }
                    )

                    if reminders.isEmpty {
                        Text("Пусто")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .padding(.top, 4)
                    } else {
                        ForEach(reminders) { reminder in
                            ReminderRow(reminder: reminder) {
                                Task { await reloadReminders() }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 208)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func addReminderField(
        tint: Color,
        text: Binding<String>,
        field: ReminderField,
        onAdd: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .foregroundStyle(.white)
                .font(.system(size: 14, weight: .semibold))

            TextField("Новое напоминание...", text: text)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: field)
                .onSubmit(onAdd)
                .foregroundStyle(.white.opacity(0.72))
                .font(.system(size: 15))

            Spacer(minLength: 0)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(trimmed(text.wrappedValue).isEmpty ? 0.35 : 0.9))
            }
            .buttonStyle(.plain)
            .disabled(trimmed(text.wrappedValue).isEmpty)
        }
        .padding(.leading, 0)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = field
        }
    }

    private func addReminder(to listID: String?, text: Binding<String>) {
        let title = trimmed(text.wrappedValue)
        guard !title.isEmpty else { return }
        guard listID != nil else { return }
        text.wrappedValue = ""
        focusedField = nil

        Task {
            let success = await calendarManager.createReminder(title: title, calendarID: listID)
            if success {
                await reloadReminders()
            }
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func initializeSelectionsIfNeeded() {
        guard !reminderLists.isEmpty else { return }

        if resolvedPrimaryListID == nil {
            primaryListID = reminderLists.first?.id
        }

        if secondaryListID == primaryListID {
            secondaryListID = reminderLists.dropFirst().first?.id
        }
    }

    private func reloadReminders() async {
        let primaryID = resolvedPrimaryListID
        let secondaryID = resolvedSecondaryListID

        if let primaryID {
            primaryReminders = await calendarManager.reminders(for: [primaryID])
        } else {
            primaryReminders = []
        }

        if let secondaryID {
            secondaryReminders = await calendarManager.reminders(for: [secondaryID])
        } else {
            secondaryReminders = []
        }
    }

    private func titleForList(_ id: String?) -> String? {
        reminderLists.first(where: { $0.id == id })?.title
    }

    private func listColor(for id: String?) -> Color {
        guard let id, let calendar = reminderLists.first(where: { $0.id == id }) else {
            return .white.opacity(0.7)
        }
        return Color(nsColor: calendar.color)
    }
}

private struct ReminderRow: View {
    let reminder: EventModel
    let onChanged: () -> Void
    @ObservedObject var calendarManager = CalendarManager.shared

    private var isCompleted: Bool {
        if case .reminder(let completed) = reminder.type { return completed }
        return false
    }

    private var hasDueDate: Bool {
        reminder.start != .distantFuture
    }

    private var dueText: String? {
        guard hasDueDate else { return nil }
        if reminder.isAllDay {
            return reminder.start.formatted(date: .abbreviated, time: .omitted)
        }
        return reminder.start.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await calendarManager.setReminderCompleted(
                        reminderID: reminder.id, completed: !isCompleted
                    )
                    onChanged()
                }
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCompleted ? .green : .white.opacity(0.6))

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isCompleted ? .gray : .white)
                    .strikethrough(isCompleted)
                    .lineLimit(1)

                if let dueText {
                    Text(dueText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    Text("Без даты")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            Spacer()
        }
    }
}

// MARK: - Goals

struct GoalsView: View {
    @EnvironmentObject private var vm: ArsWidgetViewModel
    @ObservedObject private var goals = GoalsManager.shared

    @State private var selectedHorizon: GoalHorizon = .now
    @State private var newGoalTitle = ""
    @State private var newGoalArea: GoalArea = .personal
    @FocusState private var isGoalFieldFocused: Bool

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
            goalsHeader
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

    private var goalsHeader: some View {
        HStack(spacing: 8) {
            Text("Цели")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 4) {
                ForEach(GoalHorizon.allCases) { horizon in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
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
                .focused($isGoalFieldFocused)
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
        isGoalFieldFocused = false
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
    RemindersView()
        .frame(width: 620, height: 720)
        .padding()
        .background(.black)
        .environmentObject(ArsWidgetViewModel())
}
