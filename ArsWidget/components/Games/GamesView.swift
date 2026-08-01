//
//  GamesView.swift
//  ArsWidget
//
//  Added in personal fork: a "Games" tab that embeds the user's own
//  Kizuna / Tsunagu web games (hosted separately at app.staroschuk.com,
//  Flask + Socket.IO + Postgres backend — see games-staroschuk repo).
//
//  Reuses 100% of the existing game code — no porting. The web view is
//  only created while this tab is on screen: SwiftUI tears it down the
//  moment you switch to another tab, so it costs nothing the rest of the
//  time. Needs an internet connection and the game server to be running.
//

import SwiftUI
import UserNotifications
import WebKit

private enum GameChoice: String, CaseIterable, Identifiable {
    case kizuna = "Kizuna"
    case tsunagu = "Цунаги"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .kizuna: return "Kizuna"
        case .tsunagu: return String(localized: "Цунаги")
        }
    }

    var path: String {
        switch self {
        case .kizuna: return "/kizuna"
        case .tsunagu: return "/tsunagu"
        }
    }
}

struct GamesView: View {
    @EnvironmentObject var vm: ArsWidgetViewModel
    @AppStorage("gamesBaseURL") private var baseURLString: String = "https://app.staroschuk.com"
    @State private var selectedGame: GameChoice = .kizuna
    @State private var isEditingURL = false
    @StateObject private var session = GameSessionController.shared

    private var gameURL: URL? {
        guard let base = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              base.scheme?.lowercased() == "https",
              base.host != nil
        else { return nil }
        return base.appendingPathComponent(String(selectedGame.path.dropFirst()))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Picker("", selection: $selectedGame) {
                    ForEach(GameChoice.allCases) { game in
                        Text(game.title).tag(game)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                Button {
                    if let url = gameURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .help("Открыть в браузере на весь экран")

                Button {
                    isEditingURL.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
            }

            if isEditingURL {
                TextField("Адрес сервера игр", text: $baseURLString)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            if let url = gameURL {
                GameWebView(
                    cacheKey: selectedGame.rawValue,
                    url: url,
                    onInteraction: {
                        session.registerInteraction()
                    }
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: 720)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            } else {
                Text("Некорректный адрес сервера")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 720)
            }
        }
        .padding(.horizontal, 8)
        .onAppear {
            vm.updateOpenSizeIfNeeded()
            session.attach(viewModel: vm)
            session.start()
            session.registerInteraction()
        }
        .onDisappear {
            session.detachIfNeeded(for: vm)
        }
        .onChange(of: selectedGame) { _, _ in
            session.registerInteraction()
        }
    }
}

@MainActor
final class GameSessionController: ObservableObject {
    static let shared = GameSessionController()

    private weak var viewModel: ArsWidgetViewModel?
    private var timer: Timer?
    private var lastInteraction = Date()
    private let inactivityInterval: TimeInterval = 600

    func attach(viewModel: ArsWidgetViewModel) {
        self.viewModel = viewModel
    }

    func detachIfNeeded(for viewModel: ArsWidgetViewModel) {
        if self.viewModel === viewModel {
            self.viewModel = nil
            stop()
        }
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleTimeout()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func registerInteraction() {
        lastInteraction = Date()
    }

    private func checkIdleTimeout() {
        guard let viewModel else { return }
        guard viewModel.notchState == .open else { return }
        guard ArsWidgetViewCoordinator.shared.currentView == .games else { return }
        guard Date().timeIntervalSince(lastInteraction) >= inactivityInterval else { return }

        GameWebViewStore.shared.releaseAll()
        viewModel.close()

        let content = UNMutableNotificationContent()
        content.title = "Игра скрыта"
        content.body = "Игра выгружена после долгого простоя, чтобы не расходовать память. Открой вкладку снова, чтобы продолжить."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
final class GameWebViewStore {
    static let shared = GameWebViewStore()

    private var webViews: [String: WKWebView] = [:]

    func webView(for key: String, url: URL) -> WKWebView {
        if let existing = webViews[key] {
            if existing.url == nil {
                existing.load(URLRequest(url: url))
            }
            return existing
        }

        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        webViews[key] = webView
        return webView
    }

    func releaseAll() {
        for webView in webViews.values {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.removeFromSuperview()
        }
        webViews.removeAll()
    }
}

private struct GameWebView: NSViewRepresentable {
    let cacheKey: String
    let url: URL
    let onInteraction: () -> Void

    func makeNSView(context: Context) -> TrackingContainerView {
        let webView = GameWebViewStore.shared.webView(for: cacheKey, url: url)
        return TrackingContainerView(webView: webView, onInteraction: onInteraction)
    }

    func updateNSView(_ container: TrackingContainerView, context: Context) {
        let webView = GameWebViewStore.shared.webView(for: cacheKey, url: url)
        container.updateWebView(webView)
        container.onInteraction = onInteraction

        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

final class TrackingContainerView: NSView {
    var onInteraction: () -> Void
    private(set) var webView: WKWebView
    private var trackingAreaRef: NSTrackingArea?

    init(webView: WKWebView, onInteraction: @escaping () -> Void) {
        self.webView = webView
        self.onInteraction = onInteraction
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 22
        webView.layer?.cornerCurve = .continuous
        webView.layer?.masksToBounds = true
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onInteraction()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onInteraction()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onInteraction()
    }

    func updateWebView(_ newWebView: WKWebView) {
        guard webView !== newWebView else { return }
        webView.removeFromSuperview()
        webView = newWebView
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 22
        webView.layer?.cornerCurve = .continuous
        webView.layer?.masksToBounds = true
        addSubview(webView)
        needsLayout = true
    }
}

#Preview {
    GamesView()
        .frame(width: 340, height: 220)
        .background(.black)
}
