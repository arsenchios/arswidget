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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var newTaskTitle = ""
    @FocusState private var taskFieldFocused: Bool

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }

    var body: some View {
        VStack(spacing: 12) {
            headerCard
            workspaceToggle

            if pomodoro.showStatistics || pomodoro.awaitingReview {
                ScrollView {
                    VStack(spacing: 12) {
                        if pomodoro.awaitingReview { reviewCard }
                        if pomodoro.showStatistics { expandedWorkspace }
                    }
                    .padding(.bottom, 4)
                }
                .frame(height: 264)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
        .onAppear {
            vm.updateOpenSizeIfNeeded()
            updateBreathing()
        }
        .onChange(of: pomodoro.showStatistics) { _, _ in resize() }
        .onChange(of: pomodoro.awaitingReview) { _, _ in resize() }
        .onChange(of: pomodoro.isRunning) { _, _ in updateBreathing() }
        .onChange(of: reduceMotion) { _, _ in updateBreathing() }
        .onDisappear { breathing = false }
    }

    private var headerCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: phaseIcon)
                    .foregroundStyle(phaseColor)
                Text(phaseLabel.uppercased())
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(phaseColor.opacity(0.9))
                Menu {
                    Button("Сбросить таймер", systemImage: "arrow.counterclockwise") { pomodoro.reset() }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .menuIndicator(.hidden)
                .help("Действия с таймером")
                .accessibilityLabel("Действия с таймером")
            }
            .font(.system(size: 10, weight: .semibold))

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(pomodoro.awaitingReview ? "Итог" : pomodoro.formattedTimeRemaining)
                        .font(.system(size: pomodoro.awaitingReview ? 64 : 76, weight: .medium, design: .rounded))
                        .tracking(-3)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: pomodoro.secondsRemaining)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .accessibilityLabel(pomodoro.awaitingReview ? "Итог сессии" : "Осталось \(pomodoro.formattedTimeRemaining)")
                    taskPicker
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    Button(action: primaryAction) {
                        ZStack {
                            Circle()
                                .stroke(phaseColor.opacity(breathing ? 0.08 : 0.28), lineWidth: 1)
                                .scaleEffect(breathing ? 1.2 : 1.06)
                            Circle()
                                .fill(LinearGradient(colors: [phaseColor, phaseColor.opacity(0.83)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: pomodoro.awaitingReview ? "checkmark" : (pomodoro.isRunning ? "pause.fill" : "play.fill"))
                                .font(.system(size: 25, weight: .semibold))
                                .offset(x: pomodoro.isRunning || pomodoro.awaitingReview ? 0 : 2)
                                .foregroundStyle(.black.opacity(0.88))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .frame(width: 74, height: 74)
                        .contentShape(Circle())
                    }
                    .buttonStyle(PomodoroPressStyle())
                    .disabled(pomodoro.awaitingReview)
                    .opacity(pomodoro.awaitingReview ? 0.65 : 1)
                    .accessibilityLabel(primaryLabel)
                    .help(primaryLabel)

                    Text(primaryLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: 100)
            }

            if pomodoro.phase == .idle && !pomodoro.awaitingReview {
                HStack(spacing: 6) {
                    ForEach([25, 45, 60], id: \.self) { minutes in
                        Button {
                            withAnimation(motion) { pomodoro.workMinutes = minutes }
                        } label: {
                            Text("\(minutes) мин")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .foregroundStyle(pomodoro.workMinutes == minutes ? phaseColor : .white.opacity(0.5))
                                .background(Capsule().fill(pomodoro.workMinutes == minutes ? phaseColor.opacity(0.13) : .white.opacity(0.04)))
                                .overlay(Capsule().stroke(pomodoro.workMinutes == minutes ? phaseColor.opacity(0.22) : .clear, lineWidth: 1))
                        }
                        .buttonStyle(PomodoroPressStyle())
                        .accessibilityAddTraits(pomodoro.workMinutes == minutes ? .isSelected : [])
                    }
                    Spacer(minLength: 4)
                    Text("Отдых \(pomodoro.shortBreakMinutes) мин")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            } else {
                progressTrack
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [phaseColor.opacity(0.105), Color.white.opacity(0.025), Color.white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(LinearGradient(colors: [phaseColor.opacity(0.2), .white.opacity(0.05), .white.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
    }

    private var taskPicker: some View {
        HStack(spacing: 6) {
            if let task = pomodoro.activeTask {
                Menu {
                    ForEach(pomodoro.pendingTasks) { candidate in
                        Button {
                            pomodoro.setActiveTask(candidate.id)
                        } label: {
                            if candidate.id == task.id { Label(candidate.title, systemImage: "checkmark") }
                            else { Text(candidate.title) }
                        }
                    }
                    Divider()
                    Button("Новая задача…", systemImage: "plus") { revealTaskField() }
                } label: {
                    Text(task.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
                .disabled(pomodoro.awaitingReview)
            } else {
                Image(systemName: "pencil.line")
                    .foregroundStyle(phaseColor.opacity(0.6))
                TextField("На чём сосредоточимся?", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(primaryAction)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.58))
        .frame(height: 22)
    }

    private var progressTrack: some View {
        VStack(spacing: 9) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    Capsule().fill(phaseColor)
                        .frame(width: geometry.size.width * min(1, max(0, pomodoro.progress)))
                }
            }
            .frame(height: 3)
            .animation(reduceMotion ? nil : .linear(duration: 0.8), value: pomodoro.progress)
            HStack(spacing: 5) {
                ForEach(0..<min(8, max(1, pomodoro.sessionsBeforeLongBreak)), id: \.self) { index in
                    Capsule()
                        .fill(index < pomodoro.completedWorkSessions % max(1, pomodoro.sessionsBeforeLongBreak) ? phaseColor : .white.opacity(0.14))
                        .frame(width: 14, height: 3)
                }
                Text("Сессия \(pomodoro.completedWorkSessions % max(1, pomodoro.sessionsBeforeLongBreak) + 1)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.leading, 4)
                Spacer()
                if pomodoro.phase == .work && !pomodoro.awaitingReview {
                    Button("Завершить", systemImage: "stop.fill") { withAnimation(motion) { pomodoro.stopAndReview() } }
                        .disabled(!pomodoro.isRunning || pomodoro.awaitingReview)
                } else if (pomodoro.phase == .shortBreak || pomodoro.phase == .longBreak) && !pomodoro.awaitingReview {
                    Button("Пропустить", systemImage: "forward.end.fill") { withAnimation(motion) { pomodoro.skip() } }
                        .disabled(pomodoro.awaitingReview)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
        }
        .frame(height: 30)
    }

    private var workspaceToggle: some View {
        HStack {
            Button {
                withAnimation(motion) { pomodoro.toggleStatistics() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "list.bullet.rectangle")
                    Text("Задачи и итоги")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(pomodoro.showStatistics ? 180 : 0))
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(PomodoroPressStyle())
            Spacer()
            Text("Сегодня \(pomodoro.todaysFocusMinutes) мин в фокусе")
                .foregroundStyle(.white.opacity(0.35))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 8)
    }

    private var primaryLabel: String {
        if pomodoro.awaitingReview { return "Сессия окончена" }
        if pomodoro.isRunning { return "Пауза" }
        return pomodoro.phase == .idle ? "Начать фокус" : "Продолжить"
    }

    private var statusLabel: String {
        if pomodoro.awaitingReview { return "Готово" }
        if pomodoro.isRunning { return "В процессе" }
        return pomodoro.phase == .idle ? "Готов к старту" : "На паузе"
    }

    private func primaryAction() {
        guard !pomodoro.awaitingReview else { return }
        withAnimation(motion) {
            if pomodoro.isRunning { pomodoro.pause() }
            else {
                if pomodoro.phase == .idle && !trimmedNewTask.isEmpty { addTask() }
                pomodoro.start()
            }
        }
    }

    private func revealTaskField() {
        withAnimation(motion) { pomodoro.showStatistics = true }
        DispatchQueue.main.async { taskFieldFocused = true }
    }

    private func resize() {
        withAnimation(motion) { vm.updateOpenSizeIfNeeded() }
    }

    private func updateBreathing() {
        breathing = false
        guard pomodoro.isRunning, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathing = true }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pomodoro.reviewAfterBreak ? "Перерыв завершён" : "Фокус остановлен")
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
                if pomodoro.reviewAfterBreak {
                    Button("Сделано") {
                        pomodoro.submitReview(completedTask: true, continuation: .idle)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.green.opacity(0.32)))

                    Button("Продолжить") {
                        pomodoro.submitReview(completedTask: false, continuation: .continueCurrentTask)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.orange.opacity(0.28)))
                } else {
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
                }

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
                Text("Можно добавить задачу или просто начать фокус.")
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
        if pomodoro.awaitingReview { return "Подведём итог" }
        switch pomodoro.phase {
        case .idle: return "Время для важного"
        case .work: return "Фокус"
        case .shortBreak: return "Короткий перерыв"
        case .longBreak: return "Длинный перерыв"
        }
    }

    private var phaseIcon: String {
        switch pomodoro.phase {
        case .idle: return "scope"
        case .work: return "bolt.fill"
        case .shortBreak, .longBreak: return "cup.and.saucer.fill"
        }
    }

    private var phaseColor: Color {
        switch pomodoro.phase {
        case .work, .idle: return Color(red: 1.0, green: 0.69, blue: 0.40)
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
        case .work, .idle: return Color(red: 1.0, green: 0.69, blue: 0.40)
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

private struct PomodoroPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
