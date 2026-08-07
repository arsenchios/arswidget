//
//  SystemStatsManager.swift
//  ArsWidget
//
//  Added in personal fork: a small CPU + memory monitor, refreshed every
//  few seconds. Reading these numbers from the OS (host_processor_info /
//  host_statistics64) is very cheap — this is the same approach used by
//  well-known lightweight menu bar monitors like the open-source "Stats"
//  app — so polling every 2-3 seconds is not something you'll notice on
//  a non-Pro Mac. There's still an on/off toggle in the tab, same as the
//  other features, in case you ever want it off.
//

import Foundation
import Darwin
import SwiftUI
import Combine
import Network

struct SystemUsage {
    var cpuPercent: Double = 0
    var memoryUsedPercent: Double = 0
    var memoryUsedGB: Double = 0
    var memoryTotalGB: Double = 0
}

/// The Chrome bridge writes only these derived values. It never needs access to
/// account credentials, browser cookies, prompts, or chat content.
struct AIUsageSnapshot: Codable, Equatable {
    var codexWeeklyRemaining: Double?
    var claudeFiveHourRemaining: Double?
    var claudeWeeklyRemaining: Double?
    var deepseekRemaining: Double?
    var geminiRemaining: Double?
    var updatedAt: Date
}

/// One place that knows every limit we can show, so the tab, the closed notch
/// and the "you can still connect ..." hint can never drift apart again.
enum AIUsageMetric: String, CaseIterable, Identifiable {
    case codexWeekly
    case claudeFiveHour
    case claudeWeekly
    case deepseek
    case gemini

    var id: String { rawValue }

    /// Vendor name, used for the "not connected yet" hint (Claude has two rows).
    var provider: String {
        switch self {
        case .codexWeekly: return "Codex"
        case .claudeFiveHour, .claudeWeekly: return "Claude"
        case .deepseek: return "DeepSeek"
        case .gemini: return "Gemini"
        }
    }

    var title: String {
        switch self {
        case .codexWeekly: return String(localized: "Codex, неделя")
        case .claudeFiveHour: return String(localized: "Claude, 5 часов")
        case .claudeWeekly: return String(localized: "Claude, неделя")
        case .deepseek: return String(localized: "DeepSeek")
        case .gemini: return String(localized: "Gemini")
        }
    }

    /// Single character shown inside the closed-notch capsule.
    var shortLabel: String {
        switch self {
        case .codexWeekly: return "C"
        case .claudeFiveHour: return "5"
        case .claudeWeekly: return "W"
        case .deepseek: return "D"
        case .gemini: return "G"
        }
    }

    var tint: Color {
        switch self {
        case .codexWeekly: return .blue
        case .claudeFiveHour: return .orange
        case .claudeWeekly: return Color.orange.opacity(0.72)
        case .deepseek: return .teal
        case .gemini: return .purple
        }
    }

    func value(in snapshot: AIUsageSnapshot) -> Double? {
        switch self {
        case .codexWeekly: return snapshot.codexWeeklyRemaining
        case .claudeFiveHour: return snapshot.claudeFiveHourRemaining
        case .claudeWeekly: return snapshot.claudeWeeklyRemaining
        case .deepseek: return snapshot.deepseekRemaining
        case .gemini: return snapshot.geminiRemaining
        }
    }
}

@MainActor
final class AIUsageManager: ObservableObject {
    static let shared = AIUsageManager()

    /// Values older than this mean Chrome is closed, the tab is gone or the
    /// account is logged out — the numbers are still shown, but marked stale.
    static let staleAfter: TimeInterval = 15 * 60

    /// Below this share of the limit left, the number is shown as a warning.
    static let lowRemainingPercent: Double = 15

    static func isLow(_ remainingPercent: Double) -> Bool {
        remainingPercent < lowRemainingPercent
    }

    @Published private(set) var snapshot: AIUsageSnapshot?
    /// Recomputed on a timer, but only republished when the visible text
    /// actually changes, so the notch is not redrawn every 15 seconds.
    @Published private(set) var freshnessText: String?
    @Published private(set) var isStale = false

    // @AppStorage does not drive objectWillChange on its own inside a class,
    // so views observing this manager would repaint late (or not at all).
    @AppStorage("aiUsageShowInClosedNotch") var showInClosedNotch = false {
        willSet { objectWillChange.send() }
    }

    private var refreshTimer: AnyCancellable?
    private let fileName = "ai-usage.json"

    private init() {
        reload()
        refreshTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.reload() }
    }

    var hasData: Bool { !connectedMetrics.isEmpty }

    /// Metrics we actually received a value for, in display order.
    var connectedMetrics: [AIUsageMetric] {
        guard let snapshot else { return [] }
        return AIUsageMetric.allCases.filter { $0.value(in: snapshot) != nil }
    }

    /// Vendors with nothing connected yet, deduplicated (Claude counts once).
    var missingProviders: [String] {
        let connected = Set(connectedMetrics.map(\.provider))
        var seen = Set<String>()
        return AIUsageMetric.allCases
            .map(\.provider)
            .filter { seen.insert($0).inserted && !connected.contains($0) }
    }

    func value(for metric: AIUsageMetric) -> Double? {
        snapshot.flatMap { metric.value(in: $0) }
    }

    var dataFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ArsWidget", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    func reload() {
        if let dataFileURL,
           let data = try? Data(contentsOf: dataFileURL),
           let decoded = try? JSONDecoder().decode(AIUsageSnapshot.self, from: data),
           decoded != snapshot {
            snapshot = decoded
        }
        // A missing or unreadable file must not wipe values we already show:
        // the bridge keeps the live snapshot in memory even if the disk write
        // failed, and dropping it would blank the tab for no reason.
        refreshFreshness()
    }

    func accept(_ snapshot: AIUsageSnapshot) {
        if snapshot != self.snapshot {
            self.snapshot = snapshot
        }
        refreshFreshness()

        guard let dataFileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: dataFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: dataFileURL, options: .atomic)
        } catch {
            // The live value is still shown for this launch if persistence fails.
        }
    }

    private func refreshFreshness() {
        guard let updatedAt = snapshot?.updatedAt else {
            if freshnessText != nil { freshnessText = nil }
            if isStale { isStale = false }
            return
        }

        let age = max(0, Date().timeIntervalSince(updatedAt))
        let text: String
        switch age {
        case ..<90:
            text = String(localized: "только что")
        case ..<3600:
            text = String(localized: "\(Int(age / 60)) мин назад")
        case ..<86_400:
            text = String(localized: "\(Int(age / 3600)) ч назад")
        default:
            text = String(localized: "давно")
        }

        if text != freshnessText { freshnessText = text }
        let stale = age > Self.staleAfter
        if stale != isStale { isStale = stale }
    }
}

/// Receives only percentage values from the optional Chrome extension.
/// The listener accepts local connections only; it never exposes a network API.
final class AIUsageBridge {
    static let shared = AIUsageBridge()

    private let queue = DispatchQueue(label: "com.staroschuk.arswidget.ai-usage-bridge")
    private let port = NWEndpoint.Port(rawValue: 63554)!
    private let maximumRequestSize = 4 * 1024
    private let maximumPayloadSize = 1024
    private var listener: NWListener?

    private init() {}

    func start() {
        // `listener` is touched from the app lifecycle and from Network's own
        // callback queue, so every access is funnelled through `queue`.
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }

            let parameters = NWParameters.tcp
            parameters.acceptLocalOnly = true
            parameters.allowLocalEndpointReuse = true

            do {
                let listener = try NWListener(using: parameters, on: self.port)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    if case .failed = state {
                        self.queue.async {
                            self.listener?.cancel()
                            self.listener = nil
                        }
                    }
                }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                self.listener = nil
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        // A local client cannot keep the listener occupied with a partial request.
        queue.asyncAfter(deadline: .now() + 5) {
            connection.cancel()
        }
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: maximumRequestSize) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            guard error == nil else {
                connection.cancel()
                return
            }

            var updatedBuffer = buffer
            if let data {
                updatedBuffer.append(data)
            }

            if let payload = self.payload(from: updatedBuffer), self.accept(payload) {
                self.respond(on: connection, status: "204 No Content")
            } else if isComplete || updatedBuffer.count >= self.maximumRequestSize {
                self.respond(on: connection, status: "400 Bad Request")
            } else {
                self.receiveRequest(on: connection, buffer: updatedBuffer)
            }
        }
    }

    private func payload(from request: Data) -> AIUsageBridgePayload? {
        guard let separator = request.range(of: Data("\r\n\r\n".utf8)) else { return nil }

        let headerData = request.subdata(in: request.startIndex..<separator.lowerBound)
        guard let header = String(data: headerData, encoding: .utf8),
              header.hasPrefix("POST /v1/ai-usage "),
              header.lowercased().contains("\r\ncontent-type: application/json"),
              let contentLength = contentLength(from: header),
              contentLength > 0,
              contentLength <= maximumPayloadSize
        else { return nil }

        let bodyStart = separator.upperBound
        let body = request.subdata(in: bodyStart..<request.endIndex)
        guard body.count == contentLength else { return nil }
        return try? JSONDecoder().decode(AIUsageBridgePayload.self, from: body)
    }

    private func contentLength(from header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
            else { continue }
            return Int(String(parts[1]).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private func accept(_ payload: AIUsageBridgePayload) -> Bool {
        let values = [
            payload.codexWeeklyRemaining,
            payload.claudeFiveHourRemaining,
            payload.claudeWeeklyRemaining,
            payload.deepseekRemaining,
            payload.geminiRemaining,
        ].compactMap { $0 }

        guard !values.isEmpty, values.allSatisfy({ (0...100).contains($0) }) else { return false }

        let snapshot = AIUsageSnapshot(
            codexWeeklyRemaining: payload.codexWeeklyRemaining,
            claudeFiveHourRemaining: payload.claudeFiveHourRemaining,
            claudeWeeklyRemaining: payload.claudeWeeklyRemaining,
            deepseekRemaining: payload.deepseekRemaining,
            geminiRemaining: payload.geminiRemaining,
            updatedAt: Self.captureDate(from: payload.capturedAt)
        )
        Task { @MainActor in
            AIUsageManager.shared.accept(snapshot)
        }
        return true
    }

    /// When the extension last actually read the numbers off a page, in epoch
    /// milliseconds. The extension re-sends its cache every minute even when no
    /// tab is open, so trusting the arrival time would make dead values look
    /// fresh forever. Obviously broken timestamps fall back to "now".
    private static func captureDate(from milliseconds: Double?) -> Date {
        let now = Date()
        guard let milliseconds, milliseconds > 0 else { return now }
        let captured = Date(timeIntervalSince1970: milliseconds / 1000)
        guard captured <= now.addingTimeInterval(60),
              captured > now.addingTimeInterval(-7 * 24 * 60 * 60)
        else { return now }
        return captured
    }

    private func respond(on connection: NWConnection, status: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Length: 0\r
        Connection: close\r
        \r
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct AIUsageBridgePayload: Decodable, Sendable {
    let codexWeeklyRemaining: Double?
    let claudeFiveHourRemaining: Double?
    let claudeWeeklyRemaining: Double?
    let deepseekRemaining: Double?
    let geminiRemaining: Double?
    /// Epoch milliseconds of the last real read from a page. Optional so older
    /// builds of the extension keep working.
    let capturedAt: Double?
}

@MainActor
final class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    @Published private(set) var usage = SystemUsage()
    @Published var showSupport = false
    @Published var isAILimitsSetupVisible = false

    // @AppStorage inside a class does not fire objectWillChange, so without
    // these the switch and stepper only redrew on the next stats tick.
    @AppStorage("systemStatsEnabled") var isEnabled: Bool = true {
        willSet { objectWillChange.send() }
        didSet { restart() }
    }
    @AppStorage("systemStatsIntervalSeconds") var intervalSeconds: Int = 3 {
        willSet { objectWillChange.send() }
        didSet { restart() }
    }

    private var timerCancellable: AnyCancellable?
    private var previousCPUTicks: [Int32]?
    private let totalMemoryBytes = Double(ProcessInfo.processInfo.physicalMemory)

    private init() {
        restart()
    }

    private func restart() {
        timerCancellable?.cancel()
        guard isEnabled else { return }
        let interval = max(1, intervalSeconds)
        timerCancellable = Timer.publish(every: TimeInterval(interval), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
        refresh()
    }

    private func refresh() {
        let memory = currentMemoryUsage()
        var updated = usage
        updated.memoryUsedGB = memory.usedGB
        updated.memoryUsedPercent = memory.usedPercent
        updated.memoryTotalGB = totalMemoryBytes / 1_073_741_824
        if let cpu = currentCPUUsage() {
            updated.cpuPercent = cpu
        }
        usage = updated
    }

    // MARK: CPU

    /// Returns nil on the very first call (needs two samples to compute a
    /// delta), then a 0...100 percentage on every call after that.
    private func currentCPUUsage() -> Double? {
        var numCPUsU: natural_t = 0
        var cpuInfoPtr: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfoPtr, &numCpuInfo)
        guard result == KERN_SUCCESS, let cpuInfoPtr else { return nil }

        let currentTicks = Array(UnsafeBufferPointer(start: cpuInfoPtr, count: Int(numCpuInfo)))
        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: cpuInfoPtr),
            vm_size_t(Int(numCpuInfo) * MemoryLayout<integer_t>.stride)
        )

        defer { previousCPUTicks = currentTicks }

        guard let previous = previousCPUTicks, previous.count == currentTicks.count else {
            return nil // first sample — no previous data to compare against yet
        }

        let numCPUs = Int(numCPUsU)
        var totalUsage: Double = 0
        var countedCPUs = 0

        for i in 0..<numCPUs {
            let base = Int(CPU_STATE_MAX) * i
            guard base + Int(CPU_STATE_IDLE) < currentTicks.count else { continue }

            let user = Double(currentTicks[base + Int(CPU_STATE_USER)])
            let sys = Double(currentTicks[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(currentTicks[base + Int(CPU_STATE_NICE)])
            let idle = Double(currentTicks[base + Int(CPU_STATE_IDLE)])

            let prevUser = Double(previous[base + Int(CPU_STATE_USER)])
            let prevSys = Double(previous[base + Int(CPU_STATE_SYSTEM)])
            let prevNice = Double(previous[base + Int(CPU_STATE_NICE)])
            let prevIdle = Double(previous[base + Int(CPU_STATE_IDLE)])

            let diffUse = (user - prevUser) + (sys - prevSys) + (nice - prevNice)
            let diffIdle = idle - prevIdle
            let diffTotal = diffUse + diffIdle

            if diffTotal > 0 {
                totalUsage += diffUse / diffTotal
                countedCPUs += 1
            }
        }

        guard countedCPUs > 0 else { return nil }
        return (totalUsage / Double(countedCPUs)) * 100
    }

    // MARK: Memory

    private func currentMemoryUsage() -> (usedGB: Double, usedPercent: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }

        let pageSize = Double(vm_kernel_page_size)
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        let usedGB = used / 1_073_741_824
        let percent = totalMemoryBytes > 0 ? (used / totalMemoryBytes) * 100 : 0
        return (usedGB, percent)
    }
}
