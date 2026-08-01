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
    var updatedAt: Date
}

@MainActor
final class AIUsageManager: ObservableObject {
    static let shared = AIUsageManager()

    @Published private(set) var snapshot: AIUsageSnapshot?
    @AppStorage("aiUsageShowInClosedNotch") var showInClosedNotch = false

    private var refreshTimer: AnyCancellable?
    private let fileName = "ai-usage.json"

    private init() {
        reload()
        refreshTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.reload() }
    }

    var hasData: Bool {
        snapshot?.codexWeeklyRemaining != nil
            || snapshot?.claudeFiveHourRemaining != nil
            || snapshot?.claudeWeeklyRemaining != nil
    }

    var dataFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ArsWidget", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    func reload() {
        guard let dataFileURL,
              let data = try? Data(contentsOf: dataFileURL),
              let decoded = try? JSONDecoder().decode(AIUsageSnapshot.self, from: data)
        else {
            snapshot = nil
            return
        }
        snapshot = decoded
    }

    func accept(_ snapshot: AIUsageSnapshot) {
        self.snapshot = snapshot

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
}

/// Receives only percentage values from the optional Chrome extension.
/// The listener accepts local connections only; it never exposes a network API.
final class AIUsageBridge {
    static let shared = AIUsageBridge()

    private let queue = DispatchQueue(label: "com.staroschuk.arswidget.ai-usage-bridge")
    private let port = NWEndpoint.Port(rawValue: 63554)!
    private var listener: NWListener?

    private init() {}

    func start() {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.listener?.cancel()
                    self?.listener = nil
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            listener = nil
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
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
            } else if isComplete || updatedBuffer.count >= 16 * 1024 {
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
              header.hasPrefix("POST /v1/ai-usage ")
        else { return nil }

        let bodyStart = separator.upperBound
        let body = request.subdata(in: bodyStart..<request.endIndex)
        guard !body.isEmpty else { return nil }
        return try? JSONDecoder().decode(AIUsageBridgePayload.self, from: body)
    }

    private func accept(_ payload: AIUsageBridgePayload) -> Bool {
        let values = [
            payload.codexWeeklyRemaining,
            payload.claudeFiveHourRemaining,
            payload.claudeWeeklyRemaining,
        ].compactMap { $0 }

        guard !values.isEmpty, values.allSatisfy({ (0...100).contains($0) }) else { return false }

        let snapshot = AIUsageSnapshot(
            codexWeeklyRemaining: payload.codexWeeklyRemaining,
            claudeFiveHourRemaining: payload.claudeFiveHourRemaining,
            claudeWeeklyRemaining: payload.claudeWeeklyRemaining,
            updatedAt: Date()
        )
        Task { @MainActor in
            AIUsageManager.shared.accept(snapshot)
        }
        return true
    }

    private func respond(on connection: NWConnection, status: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
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
}

@MainActor
final class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    @Published private(set) var usage = SystemUsage()
    @Published var showSupport = false

    @AppStorage("systemStatsEnabled") var isEnabled: Bool = true {
        didSet { restart() }
    }
    @AppStorage("systemStatsIntervalSeconds") var intervalSeconds: Int = 3 {
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
