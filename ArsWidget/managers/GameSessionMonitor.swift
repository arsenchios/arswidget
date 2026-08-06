//
//  GameSessionMonitor.swift
//  ArsWidget
//
//  Watches an embedded game session: after one hour it reminds the user that
//  the game is still loaded (orange dot on the closed notch and on the Games
//  tab, an in-widget prompt, and a system notification). Also reports the
//  real memory used by the app and by the game's web process.
//

import Darwin
import Foundation
import UserNotifications

@MainActor
final class GameSessionMonitor: ObservableObject {
    static let shared = GameSessionMonitor()

    @Published private(set) var isGameClosedByUser = false
    @Published private(set) var showHourlyReminder = false
    @Published private(set) var showInGamePrompt = false
    @Published private(set) var gameMemoryMB = 0
    @Published private(set) var appMemoryMB = 0

    private let hour: TimeInterval = 3600
    private var loadedAt: Date?
    private var timer: Timer?

    private init() {}

    /// Called by the web view store when the game page is created.
    func noteGameLoaded() {
        guard !isGameClosedByUser else { return }
        loadedAt = loadedAt ?? Date()
        startTimerIfNeeded()
        refreshMemory()
    }

    /// "Продолжить" — another hour without reminders.
    func continueSession() {
        loadedAt = Date()
        showHourlyReminder = false
        showInGamePrompt = false
        refreshMemory()
    }

    /// "Закрыть" / the power button — unload the game and free memory.
    func closeGame() {
        GameWebViewStore.shared.releaseAll()
        isGameClosedByUser = true
        showHourlyReminder = false
        showInGamePrompt = false
        loadedAt = nil
        timer?.invalidate()
        timer = nil
        refreshMemory()
    }

    /// "Включить" from the closed placeholder — allows a fresh web view.
    func startGameAgain() {
        isGameClosedByUser = false
        loadedAt = nil
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard !isGameClosedByUser, let loadedAt else { return }
        refreshMemory()
        guard Date().timeIntervalSince(loadedAt) >= hour else { return }
        guard !showHourlyReminder else { return }

        showHourlyReminder = true
        showInGamePrompt = true

        let content = UNMutableNotificationContent()
        content.title = "Игра активна уже час"
        content.body = "Открой виджет, чтобы продолжить или закрыть игру. (Виджет занимает примерно \(max(appMemoryMB, 1)) МБ)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func refreshMemory() {
        appMemoryMB = Int(ProcessMemory.currentProcessRSSBytes() / 1_048_576)
        var web = ProcessMemory.webContentRSSBytes(parentPID: getpid()) / 1_048_576
        if web <= 0, !isGameClosedByUser {
            // Fallback estimate if the web process cannot be read.
            web = 120
        }
        gameMemoryMB = Int(web)
    }
}

/// Small helpers for reading real RSS values via the public libproc / mach APIs.
enum ProcessMemory {
    static func currentProcessRSSBytes() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }

    static func webContentRSSBytes(parentPID: pid_t) -> Int64 {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return 0 }

        var pids = [pid_t](repeating: 0, count: Int(count))
        let actual = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard actual > 0 else { return 0 }

        var total: Int64 = 0
        for index in 0..<Int(actual) {
            let pid = pids[index]
            guard pid != parentPID else { continue }
            guard processPath(pid).contains("WebKit.WebContent") else { continue }
            guard parentPid(of: pid) == parentPID else { continue }
            total += taskRSSBytes(pid)
        }
        return total
    }

    private static func processPath(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let size = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard size > 0 else { return "" }
        return String(cString: buffer)
    }

    private static func parentPid(of pid: pid_t) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    private static func taskRSSBytes(_ pid: pid_t) -> Int64 {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: Int8.self, capacity: size) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(size))
            }
        }
        guard result == size else { return 0 }
        return Int64(info.pti_resident_size)
    }
}
