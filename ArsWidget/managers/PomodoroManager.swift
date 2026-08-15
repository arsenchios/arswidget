//
//  PomodoroManager.swift
//  ArsWidget
//
//  Personal fork: Pomodoro evolved from a simple timer into a small work log.
//  It tracks tasks, asks for a completion result after every focus session,
//  stores an optional comment, and keeps today's statistics in UserDefaults.
//

import Foundation
import Combine
import SwiftUI
import UserNotifications
import AppKit

enum PomodoroPhase {
    case idle
    case work
    case shortBreak
    case longBreak
}

enum PomodoroContinuation {
    case breakFirst
    case continueCurrentTask
    case nextFocus
    case idle
}

enum PomodoroEntryKind: String, Codable {
    case focus
    case shortBreak
    case longBreak
}

struct PomodoroTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var completedAt: Date?
    var totalFocusSeconds: Int
    var focusSessions: Int
    var lastComment: String?

    var isCompleted: Bool { completedAt != nil }
}

struct PomodoroEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: PomodoroEntryKind
    let taskID: UUID?
    let taskTitle: String?
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let taskCompleted: Bool?
    let comment: String?
}

struct PomodoroDaySummary: Identifiable, Equatable {
    let id: Date
    let dayStart: Date
    let focusMinutes: Int
    let breakMinutes: Int
    let completedTasks: Int
    let focusSessions: Int
}

private struct PendingPomodoroReview {
    let taskID: UUID?
    let taskTitle: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let shouldTriggerLongBreak: Bool
}

@MainActor
final class PomodoroManager: NSObject, ObservableObject {
    static let shared = PomodoroManager()

    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var secondsRemaining: Int = 25 * 60
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var completedWorkSessions: Int = 0
    @Published private(set) var tasks: [PomodoroTask] = []
    @Published private(set) var history: [PomodoroEntry] = []
    @Published private(set) var activeTaskID: UUID?
    @Published private(set) var awaitingReview: Bool = false
    @Published private(set) var reviewAfterBreak: Bool = false
    @Published var reviewComment: String = ""
    @Published var reviewNextTaskTitle: String = ""
    @Published var showStatistics: Bool = true

    @AppStorage("pomodoroWorkMinutes") var workMinutes: Int = 25 {
        didSet { if phase == .idle { secondsRemaining = workMinutes * 60 } }
    }
    @AppStorage("pomodoroShortBreakMinutes") var shortBreakMinutes: Int = 5
    @AppStorage("pomodoroLongBreakMinutes") var longBreakMinutes: Int = 15
    @AppStorage("pomodoroSessionsBeforeLongBreak") var sessionsBeforeLongBreak: Int = 4
    @AppStorage("pomodoroDimOnBreak") var dimOnBreak: Bool = true
    @AppStorage("pomodoroLockDuringBreak") var lockDuringBreak: Bool = false
    @AppStorage("pomodoroSoundEnabled") var soundEnabled: Bool = true
    @AppStorage("pomodoroStoredCompletedWorkSessions") private var storedCompletedWorkSessions: Int = 0
    @AppStorage("pomodoroStoredActiveTaskID") private var storedActiveTaskID: String = ""

    private let tasksStorageKey = "pomodoroTasksV2"
    private let historyStorageKey = "pomodoroHistoryV2"
    private var timerCancellable: AnyCancellable?
    private var overlayWindow: PomodoroBreakOverlayWindow?
    private var currentPhaseStartedAt: Date?
    private var pendingReview: PendingPomodoroReview?

    private override init() {
        super.init()
        completedWorkSessions = storedCompletedWorkSessions
        loadPersistedState()
        ensureActiveTask()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    var totalSeconds: Int {
        switch phase {
        case .idle, .work: return workMinutes * 60
        case .shortBreak: return shortBreakMinutes * 60
        case .longBreak: return longBreakMinutes * 60
        }
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - (Double(secondsRemaining) / Double(totalSeconds))
    }

    var formattedTimeRemaining: String {
        let m = max(secondsRemaining, 0) / 60
        let s = max(secondsRemaining, 0) % 60
        return String(format: "%02d:%02d", m, s)
    }

    var activeTask: PomodoroTask? {
        guard let activeTaskID else { return nil }
        return tasks.first(where: { $0.id == activeTaskID })
    }

    var pendingTasks: [PomodoroTask] {
        tasks.filter { !$0.isCompleted }
    }

    var completedTasksToday: [PomodoroTask] {
        tasks.filter {
            guard let completedAt = $0.completedAt else { return false }
            return Calendar.current.isDateInToday(completedAt)
        }
    }

    var todaysEntries: [PomodoroEntry] {
        history.filter { Calendar.current.isDateInToday($0.startedAt) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var todaysFocusEntries: [PomodoroEntry] {
        todaysEntries.filter { $0.kind == .focus }
    }

    var todaysBreakEntries: [PomodoroEntry] {
        todaysEntries.filter { $0.kind == .shortBreak || $0.kind == .longBreak }
    }

    var todaysFocusMinutes: Int {
        todaysFocusEntries.reduce(0) { $0 + ($1.durationSeconds / 60) }
    }

    var todaysBreakMinutes: Int {
        todaysBreakEntries.reduce(0) { $0 + ($1.durationSeconds / 60) }
    }

    var todaysCompletedTaskCount: Int {
        Set(todaysFocusEntries.filter { $0.taskCompleted == true }.compactMap(\.taskID)).count
    }

    var last7DaysSummary: [PomodoroDaySummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let entries = history.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            let focusEntries = entries.filter { $0.kind == .focus }
            let breakEntries = entries.filter { $0.kind == .shortBreak || $0.kind == .longBreak }

            return PomodoroDaySummary(
                id: day,
                dayStart: day,
                focusMinutes: focusEntries.reduce(0) { $0 + ($1.durationSeconds / 60) },
                breakMinutes: breakEntries.reduce(0) { $0 + ($1.durationSeconds / 60) },
                completedTasks: Set(focusEntries.filter { $0.taskCompleted == true }.compactMap(\.taskID)).count,
                focusSessions: focusEntries.count
            )
        }
    }

    var reviewTaskTitle: String {
        pendingReview?.taskTitle ?? activeTask?.title ?? "Фокус"
    }

    var canStartFocus: Bool {
        !awaitingReview && activeTask != nil
    }

    var nextPendingTask: PomodoroTask? {
        guard !pendingTasks.isEmpty else { return nil }
        guard let activeTaskID, let idx = pendingTasks.firstIndex(where: { $0.id == activeTaskID }) else {
            return pendingTasks.first
        }
        let nextIndex = pendingTasks.index(after: idx)
        if nextIndex < pendingTasks.endIndex {
            return pendingTasks[nextIndex]
        }
        return pendingTasks.first
    }

    func toggleStatistics() {
        showStatistics.toggle()
    }

    func addTask(title: String, selectAfterAdding: Bool = true) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = tasks.firstIndex(where: {
            !$0.isCompleted && $0.title.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            if selectAfterAdding {
                setActiveTask(tasks[existing].id)
            }
            return
        }

        let task = PomodoroTask(
            id: UUID(),
            title: trimmed,
            createdAt: Date(),
            completedAt: nil,
            totalFocusSeconds: 0,
            focusSessions: 0,
            lastComment: nil
        )
        tasks.insert(task, at: 0)
        if selectAfterAdding {
            activeTaskID = task.id
        }
        persistState()
    }

    func setActiveTask(_ id: UUID?) {
        if activeTaskID == id {
            return
        }

        if phase == .work && isRunning {
            commitPartialFocusEntry()
            activeTaskID = id
            beginWork()
            isRunning = true
            startTicking()
            persistState()
            return
        }

        activeTaskID = id
        persistState()
    }

    func reopenTask(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].completedAt = nil
        activeTaskID = id
        persistState()
    }

    func renameTask(_ id: UUID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].title = trimmed

        if pendingReview?.taskID == id, let pending = pendingReview {
            pendingReview = PendingPomodoroReview(
                taskID: pending.taskID,
                taskTitle: trimmed,
                startedAt: pending.startedAt,
                endedAt: pending.endedAt,
                durationSeconds: pending.durationSeconds,
                shouldTriggerLongBreak: pending.shouldTriggerLongBreak
            )
        }

        persistState()
    }

    func canDeleteTask(_ id: UUID) -> Bool {
        if activeTaskID == id && (isRunning || awaitingReview) {
            return false
        }
        return tasks.contains(where: { $0.id == id })
    }

    func deleteTask(_ id: UUID) {
        guard canDeleteTask(id) else { return }
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }

        tasks.remove(at: idx)

        if activeTaskID == id {
            activeTaskID = nil
            ensureActiveTask()
        }

        persistState()
    }

    func start() {
        guard !awaitingReview else { return }

        if phase == .idle {
            ensureActiveTask()
            guard activeTask != nil else { return }
            beginWork()
        } else if currentPhaseStartedAt == nil {
            currentPhaseStartedAt = Date()
        }

        isRunning = true
        startTicking()
    }

    func pause() {
        if phase == .work && isRunning {
            commitPartialFocusEntry()
            currentPhaseStartedAt = nil
        }
        isRunning = false
        timerCancellable?.cancel()
    }

    func reset() {
        if phase == .work && isRunning {
            commitPartialFocusEntry()
        }
        timerCancellable?.cancel()
        isRunning = false
        phase = .idle
        secondsRemaining = workMinutes * 60
        awaitingReview = false
        reviewAfterBreak = false
        pendingReview = nil
        reviewComment = ""
        reviewNextTaskTitle = ""
        currentPhaseStartedAt = nil
        hideBreakOverlay()
    }

    func completeTask(_ id: UUID) {
        let now = Date()

        if activeTaskID == id && phase == .work && isRunning {
            commitPartialFocusEntry(markCompleted: true, endedAt: now)
        }

        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].completedAt = tasks[idx].completedAt ?? now

        if activeTaskID == id {
            ensureActiveTask()

            if isRunning && phase == .work {
                if activeTask != nil {
                    beginWork()
                    isRunning = true
                    startTicking()
                } else {
                    reset()
                }
            }
        }

        persistState()
    }

    func skip() {
        if awaitingReview {
            return
        }
        finishCurrentPhase()
    }

    func stopAndReview() {
        guard !awaitingReview else { return }
        guard phase == .work, isRunning else { return }

        let end = Date()
        let duration = max(0, totalSeconds - secondsRemaining)
        let safeDuration = max(0, duration)
        let start = end.addingTimeInterval(TimeInterval(-safeDuration))
        let taskTitle = activeTask?.title ?? "Без задачи"

        timerCancellable?.cancel()
        isRunning = false
        currentPhaseStartedAt = nil

        pendingReview = PendingPomodoroReview(
            taskID: activeTaskID,
            taskTitle: taskTitle,
            startedAt: start,
            endedAt: end,
            durationSeconds: safeDuration,
            shouldTriggerLongBreak: false
        )
        awaitingReview = true
        reviewAfterBreak = false
        showStatistics = true
    }

    func handleScreenLockChange(isLocked: Bool) {
        if isLocked {
            hideBreakOverlay()
            return
        }

        if (phase == .shortBreak || phase == .longBreak), dimOnBreak, isRunning {
            showBreakOverlay()
        }
    }

    func submitReview(completedTask: Bool, continuation: PomodoroContinuation) {
        guard let pendingReview else { return }

        completedWorkSessions += 1
        storedCompletedWorkSessions = completedWorkSessions

        let comment = reviewComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTask = reviewNextTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        applyReview(
            pendingReview: pendingReview,
            completedTask: completedTask,
            comment: comment.isEmpty ? nil : comment
        )

        awaitingReview = false
        self.pendingReview = nil
        reviewAfterBreak = false
        reviewComment = ""
        reviewNextTaskTitle = ""

        if !nextTask.isEmpty {
            addTask(title: nextTask, selectAfterAdding: true)
        } else if continuation == .nextFocus {
            advanceToNextPendingTask()
        } else if completedTask {
            ensureActiveTask()
        }

        switch continuation {
        case .breakFirst:
            beginBreak(long: pendingReview.shouldTriggerLongBreak)
            isRunning = true
            startTicking()
            notify(
                title: pendingReview.shouldTriggerLongBreak ? String(localized: "Длинный перерыв") : String(localized: "Перерыв"),
                body: pendingReview.shouldTriggerLongBreak ? String(localized: "Сессия сохранена. Время отдохнуть.") : String(localized: "Сессия сохранена. Сделай короткий перерыв.")
            )
        case .nextFocus:
            beginWork()
            isRunning = true
            startTicking()
            notify(title: String(localized: "Следующий фокус"), body: String(localized: "Следующая задача запущена."))
        case .continueCurrentTask:
            beginWork()
            isRunning = true
            startTicking()
            notify(title: String(localized: "Фокус продолжен"), body: String(localized: "Таймер запущен для текущей задачи."))
        case .idle:
            phase = .idle
            secondsRemaining = workMinutes * 60
            currentPhaseStartedAt = nil
            hideBreakOverlay()
        }
    }

    private func beginWork() {
        ensureActiveTask()
        guard activeTask != nil else {
            phase = .idle
            secondsRemaining = workMinutes * 60
            isRunning = false
            hideBreakOverlay()
            return
        }

        phase = .work
        secondsRemaining = workMinutes * 60
        currentPhaseStartedAt = Date()
        hideBreakOverlay()
        playSound(.workStart)
    }

    private func beginBreak(long: Bool) {
        phase = long ? .longBreak : .shortBreak
        secondsRemaining = (long ? longBreakMinutes : shortBreakMinutes) * 60
        currentPhaseStartedAt = Date()

        if dimOnBreak { showBreakOverlay() }
        playSound(.breakStart)
    }

    private enum SoundMoment { case workStart, breakStart }

    private func playSound(_ moment: SoundMoment) {
        guard soundEnabled else { return }
        let name: NSSound.Name = moment == .breakStart ? "Glass" : "Pop"
        NSSound(named: name)?.play()
    }

    private func startTicking() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard isRunning else { return }
        if secondsRemaining > 0 {
            secondsRemaining -= 1
        } else {
            finishCurrentPhase()
        }
    }

    private func finishCurrentPhase() {
        switch phase {
        case .work:
            let end = Date()
            let start = currentPhaseStartedAt ?? end.addingTimeInterval(TimeInterval(-workMinutes * 60))
            timerCancellable?.cancel()
            isRunning = false
            currentPhaseStartedAt = nil
            let taskTitle = activeTask?.title ?? "Без задачи"
            let willBeLongBreak = (completedWorkSessions + 1) % max(1, sessionsBeforeLongBreak) == 0

            pendingReview = PendingPomodoroReview(
                taskID: activeTaskID,
                taskTitle: taskTitle,
                startedAt: start,
                endedAt: end,
                durationSeconds: max(0, Int(end.timeIntervalSince(start))),
                shouldTriggerLongBreak: willBeLongBreak
            )
            // A completed focus block begins the break immediately. The task
            // result is requested after the break, when it is actionable.
            awaitingReview = false
            reviewAfterBreak = true
            beginBreak(long: willBeLongBreak)
            isRunning = true
            startTicking()
            notify(
                title: willBeLongBreak ? String(localized: "Длинный перерыв") : String(localized: "Перерыв: 5 минут"),
                body: String(localized: "Фокус завершён. После перерыва зафиксируй результат задачи.")
            )

        case .shortBreak, .longBreak:
            finalizeBreakEntry()
            timerCancellable?.cancel()
            isRunning = false
            phase = .idle
            secondsRemaining = workMinutes * 60
            currentPhaseStartedAt = nil
            hideBreakOverlay()
            awaitingReview = pendingReview != nil
            reviewAfterBreak = awaitingReview
            showStatistics = true
            notify(title: String(localized: "Перерыв завершён"), body: String(localized: "Отметь результат и выбери следующее действие."))
            NotificationCenter.default.post(name: .pomodoroReviewReady, object: nil)

        case .idle:
            break
        }
    }

    private func applyReview(pendingReview: PendingPomodoroReview, completedTask: Bool, comment: String?) {
        if let taskID = pendingReview.taskID, let idx = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[idx].totalFocusSeconds += pendingReview.durationSeconds
            tasks[idx].focusSessions += 1
            if let comment, !comment.isEmpty {
                tasks[idx].lastComment = comment
            }
            if completedTask {
                tasks[idx].completedAt = pendingReview.endedAt
            }
        }

        history.insert(
            PomodoroEntry(
                id: UUID(),
                kind: .focus,
                taskID: pendingReview.taskID,
                taskTitle: pendingReview.taskTitle,
                startedAt: pendingReview.startedAt,
                endedAt: pendingReview.endedAt,
                durationSeconds: pendingReview.durationSeconds,
                taskCompleted: completedTask,
                comment: comment
            ),
            at: 0
        )

        persistState()
    }

    private func commitPartialFocusEntry(markCompleted: Bool = false, endedAt: Date = Date()) {
        guard phase == .work else { return }
        guard let startedAt = currentPhaseStartedAt else { return }

        let duration = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        guard duration > 0 else {
            currentPhaseStartedAt = Date()
            return
        }

        let taskTitle = activeTask?.title ?? "Без задачи"

        if let taskID = activeTaskID, let idx = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[idx].totalFocusSeconds += duration
            tasks[idx].focusSessions += 1
            if markCompleted {
                tasks[idx].completedAt = endedAt
            }
        }

        history.insert(
            PomodoroEntry(
                id: UUID(),
                kind: .focus,
                taskID: activeTaskID,
                taskTitle: taskTitle,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: duration,
                taskCompleted: markCompleted ? true : false,
                comment: nil
            ),
            at: 0
        )

        currentPhaseStartedAt = Date()
        persistState()
    }

    private func finalizeBreakEntry() {
        guard phase == .shortBreak || phase == .longBreak else { return }
        guard let startedAt = currentPhaseStartedAt else { return }

        let endedAt = Date()
        let duration = max(0, Int(endedAt.timeIntervalSince(startedAt)))

        history.insert(
            PomodoroEntry(
                id: UUID(),
                kind: phase == .longBreak ? .longBreak : .shortBreak,
                taskID: activeTaskID,
                taskTitle: activeTask?.title,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: duration,
                taskCompleted: nil,
                comment: nil
            ),
            at: 0
        )

        persistState()
    }

    private func advanceToNextPendingTask() {
        if let nextID = nextPendingTask?.id {
            activeTaskID = nextID
        } else {
            ensureActiveTask()
        }
        persistState()
    }

    private func ensureActiveTask() {
        if let activeTaskID, tasks.contains(where: { $0.id == activeTaskID && !$0.isCompleted }) {
            return
        }
        activeTaskID = tasks.first(where: { !$0.isCompleted })?.id
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func showBreakOverlay() {
        if overlayWindow == nil {
            overlayWindow = PomodoroBreakOverlayWindow()
        }
        // The break always blocks other input: the only way out is the
        // "Пропустить перерыв" button or Esc.
        overlayWindow?.showOverlay(blocksInput: true)
    }

    private func hideBreakOverlay() {
        overlayWindow?.hideOverlay()
    }

    private func loadPersistedState() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: tasksStorageKey),
           let decoded = try? JSONDecoder().decode([PomodoroTask].self, from: data) {
            tasks = decoded
        }

        if let data = defaults.data(forKey: historyStorageKey),
           let decoded = try? JSONDecoder().decode([PomodoroEntry].self, from: data) {
            history = decoded
        }

        if let uuid = UUID(uuidString: storedActiveTaskID) {
            activeTaskID = uuid
        }
    }

    private func persistState() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: tasksStorageKey)
        }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyStorageKey)
        }
        storedActiveTaskID = activeTaskID?.uuidString ?? ""
        storedCompletedWorkSessions = completedWorkSessions
    }
}

extension PomodoroManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banners even while the app is in the foreground, otherwise
        // macOS silently swallows the Pomodoro notifications.
        completionHandler([.banner, .sound])
    }
}
