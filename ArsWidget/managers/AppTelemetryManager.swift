//
//  AppTelemetryManager.swift
//  ArsWidget
//
//  Anonymous usage counters, so the private dashboard at app.staroschuk.com
//  can answer "is anyone actually using this, and which tabs?".
//
//  What leaves the Mac, once a day at most:
//    • a random id this app generated on first launch (no account, no name,
//      no hardware serial — deleting the app's preferences resets it),
//    • the ArsWidget version, the macOS version and the language,
//    • how many times each tab was opened.
//
//  What never leaves: anything you typed or copied. Pomodoro tasks, notes,
//  vocabulary, clipboard history and AI limit values stay on the Mac.
//  The whole thing is one switch away from off, in Settings → Дополнительно.
//

import Foundation
import SwiftUI

@MainActor
final class AppTelemetryManager: ObservableObject {
    static let shared = AppTelemetryManager()

    /// Every ping is a full cumulative snapshot, so the server stores the
    /// latest total instead of adding deltas — a lost or retried request can
    /// neither lose counts nor double them.
    private static let pingInterval: TimeInterval = 24 * 60 * 60
    private static let appName = "arswidget"

    @AppStorage("arswidgetTelemetryEnabled") var isEnabled = true {
        willSet { objectWillChange.send() }
        didSet { if isEnabled { scheduleSoon() } }
    }
    @AppStorage("arswidgetStatsBaseURL") var baseURLString = "https://app.staroschuk.com"
    @AppStorage("arswidgetInstallID") private var installID = ""
    @AppStorage("arswidgetTabOpensJSON") private var tabOpensJSON = "{}"
    @AppStorage("arswidgetLastPingAt") private var lastPingAt: Double = 0

    private var timer: Timer?
    private var tabOpens: [String: Int] = [:]

    private init() {
        tabOpens = Self.decodeCounters(tabOpensJSON)
    }

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }
        // Checking a few times a day keeps a Mac that never quits the app
        // reporting, without a ping storm on every launch.
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendPingIfDue() }
        }
        scheduleSoon()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleSoon() {
        // A short delay keeps launch cheap and lets the network come up.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20 * NSEC_PER_SEC)
            sendPingIfDue()
        }
    }

    // MARK: Counting

    /// Called when a tab becomes visible. Counting happens even with reporting
    /// off, so switching it on later is not a blank slate — nothing is sent
    /// until it is on.
    func noteTabOpened(_ view: NotchViews) {
        let key = Self.featureKey(view)
        tabOpens[key, default: 0] += 1
        tabOpensJSON = Self.encodeCounters(tabOpens)
    }

    // MARK: Sending

    private var isDue: Bool {
        Date().timeIntervalSince1970 - lastPingAt >= Self.pingInterval
    }

    private func sendPingIfDue() {
        guard isEnabled, isDue, !tabOpens.isEmpty else { return }
        guard let url = endpoint("/api/apps/ping") else { return }

        let payload: [String: Any] = [
            "installId": currentInstallID(),
            "app": Self.appName,
            "appVersion": Self.appVersion,
            "osVersion": Self.osVersion,
            "locale": Locale.current.language.languageCode?.identifier ?? "",
            "usage": tabOpens,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { _, response, _ in
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            Task { @MainActor in
                AppTelemetryManager.shared.lastPingAt = Date().timeIntervalSince1970
            }
        }.resume()
    }

    /// Sends a suggestion written in the "Предложить улучшение" form.
    /// Returns false when the server could not be reached, so the caller can
    /// fall back to the clipboard rather than losing what was typed.
    func sendFeedback(kind: String, message: String, contact: String = "") async -> Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3, let url = endpoint("/api/apps/feedback") else { return false }

        let payload: [String: Any] = [
            "app": Self.appName,
            // Ties a suggestion to its follow-ups without identifying anyone.
            "installId": currentInstallID(),
            "kind": kind,
            "message": String(text.prefix(2000)),
            "appVersion": Self.appVersion,
            "contact": contact.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 20

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: Helpers

    private func endpoint(_ path: String) -> URL? {
        guard let base = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              base.scheme?.lowercased() == "https",
              base.host != nil
        else { return nil }
        return base.appendingPathComponent(path)
    }

    private func currentInstallID() -> String {
        if installID.isEmpty {
            installID = UUID().uuidString
        }
        return installID
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }

    /// Names match the server's allow-list; anything else it drops.
    static func featureKey(_ view: NotchViews) -> String {
        switch view {
        case .home: return "home"
        case .shelf: return "shelf"
        case .pomodoro: return "pomodoro"
        case .reminders: return "reminders"
        case .clipboard: return "clipboard"
        case .breathing: return "breathing"
        case .vocab: return "vocab"
        case .games: return "games"
        case .sessionTimer: return "sessionTimer"
        case .systemStats: return "systemStats"
        }
    }

    private static func decodeCounters(_ raw: String) -> [String: Int] {
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Int]
        else { return [:] }
        return parsed
    }

    private static func encodeCounters(_ counters: [String: Int]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: counters),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
