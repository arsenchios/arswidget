//
//  PomodoroView.swift
//  ArsWidget
//
//  Personal fork: a task-driven Pomodoro workspace with review flow and
//  expandable statistics for the current day.
//

import SwiftUI

struct PomodoroView: View {
    @EnvironmentObject var vm: ArsWidgetViewModel
    @ObservedObject var pomodoro = PomodoroManager.shared
    @State private var pulse = false
    @State private var newTaskTitle = ""
    @FocusState private var taskFieldFocused: Bool

    private var isRunningOutOfTime: Bool {
        pomodoro.isRunning && pomodoro.secondsRemaining <= 10 && pomodoro.secondsRemaining > 0
    }

    var body: some View {
        VStack(spacing: 10) {
            headerCard

            if pomodoro.awaitingReview {
                reviewCard
            }

            if pomodoro.showStatistics {
                ScrollView {
                    expandedWorkspace
                }
                .frame(maxHeight: 455)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .onAppear {
            vm.updateOpenSizeIfNeeded()
        }
        .onChange(of: pomodoro.showStatistics) { _, _ in
            vm.updateOpenSizeIfNeeded()
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 16) {
            timerRing

            VStack(alignment: .leading, spacing: 7) {
                Text(phaseLabel)
                    .font(.caption)
                    .foregroundStyle(.gray)

                Text(pomodoro.activeTask?.title ?? "Выбери задачу перед стартом")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 14) {
                    Button {
                        pomodoro.isRunning ? pomodoro.pause() : pomodoro.start()
                    } label: {
                        Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(phaseColor.opacity(0.24)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!pomodoro.isRunning && !pomodoro.canStartFocus && pomodoro.phase == .idle)
                    .opacity((!pomodoro.isRunning && !pomodoro.canStartFocus && pomodoro.phase == .idle) ? 0.35 : 1)

                    if pomodoro.phase == .work {
                        Button {
                            pomodoro.stopAndReview()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 17, weight: .bold))
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!pomodoro.isRunning || pomodoro.awaitingReview)
                        .opacity((!pomodoro.isRunning || pomodoro.awaitingReview) ? 0.35 : 1)
                    } else if pomodoro.phase == .shortBreak || pomodoro.phase == .longBreak {
                        Button {
                            pomodoro.skip()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(Color.cyan.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .opacity(pomodoro.awaitingReview ? 0.35 : 1)
                    }

                    Button {
                        pomodoro.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if !pomodoro.showStatistics {
                            pomodoro.toggleStatistics()
                        }
                        DispatchQueue.main.async {
                            taskFieldFocused = true
                        }
                    } label: {
                        Label(
                            "Задача",
                            systemImage: "plus"
                        )
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))

                    Button {
                        pomodoro.toggleStatistics()
                    } label: {
                        Label(
                            pomodoro.showStatistics ? "Скрыть" : "Статистика",
                            systemImage: pomodoro.showStatistics ? "chevron.up" : "chart.bar.xaxis"
                        )
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.95))
                .font(.system(size: 14))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 5)

            Circle()
                .trim(from: 0, to: max(pomodoro.progress, 0.001))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [phaseColor.opacity(0.45), phaseColor]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: phaseColor.opacity(0.55), radius: 4)
                .animation(.easeInOut(duration: 0.4), value: pomodoro.progress)
                .animation(.easeInOut(duration: 0.4), value: phaseColor)

            VStack(spacing: 1) {
                Image(systemName: phaseIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(phaseColor)
                Text(pomodoro.formattedTimeRemaining)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .frame(width: 68, height: 68)
        .scaleEffect(isRunningOutOfTime && pulse ? 1.08 : 1.0)
        .animation(
            isRunningOutOfTime
                ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                : .default,
            value: pulse
        )
        .onChange(of: isRunningOutOfTime) { _, isLow in
            pulse = isLow
        }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Фокус завершён")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text(pomodoro.reviewTaskTitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))

            TextField("Что ещё сделал за это время?", text: $pomodoro.reviewComment, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
                .foregroundStyle(.white)

            TextField("Новая задача, если нужна", text: $pomodoro.reviewNextTaskTitle)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                Button("Сделано") {
                    pomodoro.submitReview(completedTask: true, continuation: .breakFirst)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.green.opacity(0.32)))

                Button("Не сделано") {
                    pomodoro.submitReview(completedTask: false, continuation: .breakFirst)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.orange.opacity(0.28)))

                Spacer(minLength: 0)

                Button("К следующей задаче") {
                    pomodoro.submitReview(completedTask: false, continuation: .nextFocus)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.cyan.opacity(0.3)))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.98))
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var expandedWorkspace: some View {
        VStack(spacing: 12) {
            plannerCard
            statsCard
            weeklyStatsCard
            sessionLogCard
        }
        .padding(12)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var plannerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Задачи")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(pomodoro.pendingTasks.count) в работе")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            HStack(spacing: 8) {
                TextField("Новая задача...", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .focused($taskFieldFocused)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                    .foregroundStyle(.white)
                    .onSubmit(addTask)

                Button {
                    addTask()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(trimmedNewTask.isEmpty ? 0.35 : 0.9))
                .disabled(trimmedNewTask.isEmpty)
            }

            if pomodoro.pendingTasks.isEmpty && pomodoro.completedTasksToday.isEmpty {
                Text("Добавь первую задачу. Таймер стартует по выбранной задаче.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pomodoro.pendingTasks) { task in
                        PomodoroPendingTaskRow(task: task)
                    }

                    if !pomodoro.completedTasksToday.isEmpty {
                        Divider().overlay(Color.white.opacity(0.08))
                            .padding(.vertical, 2)

                        Text("Сделано сегодня")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))

                        ForEach(pomodoro.completedTasksToday) { task in
                            completedTaskRow(task)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Статистика за сегодня")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                statChip(title: "Фокус", value: "\(pomodoro.todaysFocusMinutes) мин")
                statChip(title: "Перерывы", value: "\(pomodoro.todaysBreakMinutes) мин")
                statChip(title: "Завершено", value: "\(pomodoro.todaysCompletedTaskCount)")
                statChip(title: "Сессий", value: "\(pomodoro.todaysFocusEntries.count)")
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var sessionLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Сегодня")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            if pomodoro.todaysEntries.isEmpty {
                Text("Пока пусто. После первой сессии тут появится журнал.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pomodoro.todaysEntries.prefix(8)) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var weeklyStatsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Последние 7 дней")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(pomodoro.last7DaysSummary) { day in
                    HStack(spacing: 10) {
                        Text(day.dayStart.formatted(.dateTime.weekday(.abbreviated).day().month()))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 86, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(day.focusMinutes)м фокус • \(day.focusSessions) сесс.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)

                            Text("\(day.completedTasks) задач завершено • \(day.breakMinutes)м перерывы")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.45))
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func completedTaskRow(_ task: PomodoroTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green.opacity(0.8))

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)

                if let completedAt = task.completedAt {
                    Text(completedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()

            Button("Вернуть") {
                pomodoro.reopenTask(task.id)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func entryRow(_ entry: PomodoroEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color(for: entry))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title(for: entry))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(entry.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }

                if let taskTitle = entry.taskTitle, entry.kind == .focus {
                    Text(taskTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                }

                if let comment = entry.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer()

            Text("\(entry.durationSeconds / 60)м")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func addTask() {
        let title = trimmedNewTask
        guard !title.isEmpty else { return }
        pomodoro.addTask(title: title, selectAfterAdding: true)
        newTaskTitle = ""
        taskFieldFocused = false
    }

    private var trimmedNewTask: String {
        newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func title(for entry: PomodoroEntry) -> String {
        switch entry.kind {
        case .focus:
            return entry.taskCompleted == true ? "Задача завершена" : "Фокус"
        case .shortBreak:
            return "Короткий перерыв"
        case .longBreak:
            return "Длинный перерыв"
        }
    }

    private func color(for entry: PomodoroEntry) -> Color {
        switch entry.kind {
        case .focus:
            return entry.taskCompleted == true ? .green : Color(red: 1.0, green: 0.35, blue: 0.35)
        case .shortBreak, .longBreak:
            return Color(red: 0.35, green: 0.85, blue: 0.55)
        }
    }

    private var phaseLabel: String {
        switch pomodoro.phase {
        case .idle: return "Готов к работе"
        case .work: return "Фокус"
        case .shortBreak: return "Короткий перерыв"
        case .longBreak: return "Длинный перерыв"
        }
    }

    private var phaseIcon: String {
        switch pomodoro.phase {
        case .idle: return "list.bullet.clipboard"
        case .work: return "bolt.fill"
        case .shortBreak, .longBreak: return "cup.and.saucer.fill"
        }
    }

    private var phaseColor: Color {
        switch pomodoro.phase {
        case .work, .idle: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .shortBreak, .longBreak: return Color(red: 0.35, green: 0.85, blue: 0.55)
        }
    }
}

private struct PomodoroPendingTaskRow: View {
    let task: PomodoroTask
    @ObservedObject private var pomodoro = PomodoroManager.shared
    @State private var isEditing = false
    @State private var draftTitle = ""
    @FocusState private var titleFocused: Bool

    private var isActive: Bool {
        pomodoro.activeTaskID == task.id
    }

    private var phaseColor: Color {
        switch pomodoro.phase {
        case .work, .idle: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .shortBreak, .longBreak: return Color(red: 0.35, green: 0.85, blue: 0.55)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? phaseColor : Color.white.opacity(0.18))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("", text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .focused($titleFocused)
                        .onSubmit(saveRename)
                } else {
                    Text(task.title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .onTapGesture(count: 2) {
                            beginEditing()
                        }
                }

                Text("\(task.focusSessions) кругов • \(task.totalFocusSeconds / 60) мин")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            if isEditing {
                Button {
                    saveRename()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.green.opacity(0.24)))
                }
                .buttonStyle(.plain)

                Button {
                    cancelEditing()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    Button("Переименовать") {
                        beginEditing()
                    }

                    Button("Удалить", role: .destructive) {
                        pomodoro.deleteTask(task.id)
                    }
                    .disabled(!pomodoro.canDeleteTask(task.id))
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    pomodoro.completeTask(task.id)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            guard !isEditing else { return }
            pomodoro.setActiveTask(task.id)
        }
        .onAppear {
            draftTitle = task.title
        }
        .onChange(of: task.title) { _, newValue in
            if !isEditing {
                draftTitle = newValue
            }
        }
    }

    private func beginEditing() {
        draftTitle = task.title
        isEditing = true
        DispatchQueue.main.async {
            titleFocused = true
        }
    }

    private func saveRename() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelEditing()
            return
        }
        pomodoro.renameTask(task.id, to: trimmed)
        isEditing = false
    }

    private func cancelEditing() {
        draftTitle = task.title
        isEditing = false
    }
}

#Preview {
    PomodoroView()
        .frame(width: 420)
        .background(.black)
}
