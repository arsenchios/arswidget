import AppKit
import Combine
import IOKit.pwr_mgt

enum KeepAwakeMode: String, CaseIterable, Identifiable {
    case system, display
    var id: String { rawValue }
    var title: String { self == .system ? "Не усыплять Mac" : "Не гасить экран" }
    var icon: String { self == .system ? "laptopcomputer" : "display" }
    var assertionType: CFString {
        (self == .system ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep) as CFString
    }
    var explanation: String {
        self == .system
            ? "Mac продолжит работу без автоматического сна. Экран при этом может погаснуть. Закрытие крышки, ручной сон и выключение не блокируются."
            : "Экран не погаснет от бездействия; Mac также не уснёт автоматически. Это может увеличить расход батареи. Закрытие крышки и ручной сон не блокируются."
    }
}

struct KeepAwakeSession: Equatable {
    let assertionID: IOPMAssertionID
    let minutes: Int
    let endsAt: Date
}

protocol KeepAwakeAssertionProviding {
    func create(mode: KeepAwakeMode, seconds: TimeInterval) -> IOPMAssertionID?
    func release(_ id: IOPMAssertionID)
}

struct SystemKeepAwakeAssertions: KeepAwakeAssertionProviding {
    func create(mode: KeepAwakeMode, seconds: TimeInterval) -> IOPMAssertionID? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithDescription(
            mode.assertionType,
            "ArsWidget: \(mode.title)" as CFString,
            "Temporary user-selected timer" as CFString,
            "Временный режим бодрствования ArsWidget" as CFString,
            nil, seconds, kIOPMAssertionTimeoutActionTurnOff as CFString, &id
        )
        return result == kIOReturnSuccess ? id : nil
    }
    func release(_ id: IOPMAssertionID) { IOPMAssertionRelease(id) }
}

@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()
    @Published private(set) var sessions: [KeepAwakeMode: KeepAwakeSession] = [:]
    @Published private(set) var now: Date
    @Published private(set) var errorMessage: String?
    private let assertions: KeepAwakeAssertionProviding
    private let clock: () -> Date
    private let schedulesTimer: Bool
    private var timer: Timer?
    private var wakeObserver: AnyCancellable?

    init(assertions: KeepAwakeAssertionProviding = SystemKeepAwakeAssertions(),
         now: @escaping () -> Date = Date.init, schedulesTimer: Bool = true) {
        self.assertions = assertions
        clock = now
        self.now = now()
        self.schedulesTimer = schedulesTimer
        if schedulesTimer {
            wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
        }
    }

    func start(_ mode: KeepAwakeMode, minutes: Int) {
        guard [30, 60, 120].contains(minutes) else { return }
        stop(mode)
        now = clock()
        guard let id = assertions.create(mode: mode, seconds: TimeInterval(minutes * 60)) else {
            errorMessage = "Не удалось включить режим. Попробуйте ещё раз."
            return
        }
        errorMessage = nil
        sessions[mode] = KeepAwakeSession(assertionID: id, minutes: minutes, endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)))
        if schedulesTimer && timer == nil {
            let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer = newTimer
            RunLoop.main.add(newTimer, forMode: .common)
        }
    }

    func stop(_ mode: KeepAwakeMode) {
        if let session = sessions.removeValue(forKey: mode) { assertions.release(session.assertionID) }
        if sessions.isEmpty { timer?.invalidate(); timer = nil }
        errorMessage = nil
    }

    func stopAll() {
        for mode in KeepAwakeMode.allCases { stop(mode) }
    }

    func refresh() {
        now = clock()
        let expired = sessions.filter { $0.value.endsAt <= now }.map(\.key)
        for mode in expired { stop(mode) }
    }

    func remainingLabel(for mode: KeepAwakeMode) -> String {
        guard let session = sessions[mode] else { return "Выключено" }
        let minutes = max(1, Int(ceil(session.endsAt.timeIntervalSince(now) / 60)))
        return "Ещё \(minutes) мин"
    }
}
