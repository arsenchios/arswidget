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
import WebKit

struct GamesView: View {
    @EnvironmentObject var vm: ArsWidgetViewModel
    @AppStorage("gamesBaseURL") private var baseURLString: String = "https://app.staroschuk.com"
    @State private var outsideClickMonitor: Any?
    @ObservedObject private var gameMonitor = GameSessionMonitor.shared

    private var gameURL: URL? {
        guard let base = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              base.scheme?.lowercased() == "https",
              base.host != nil
        else { return nil }
        // The game's own catalogue page: it already contains the choice of
        // games, so the widget does not need its own switcher.
        let url = base.appendingPathComponent("games")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "widget", value: "1"))
        components?.queryItems = queryItems
        return components?.url
    }

    var body: some View {
        Group {
            if let url = gameURL {
                ZStack(alignment: .top) {
                    if gameMonitor.isGameClosedByUser {
                        closedGamePlaceholder
                    } else {
                        GameWebView(url: url)
                            .frame(maxWidth: .infinity)
                            .frame(height: 840)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        if gameMonitor.showInGamePrompt {
                            hourPromptBanner
                                .padding(.top, 10)
                                .padding(.horizontal, 10)
                        }

                        Button {
                            gameMonitor.closeGame()
                        } label: {
                            Image(systemName: "power")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.65))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .help("Закрыть игру и освободить память")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(12)
                    }
                }
                .frame(height: 840)
            } else {
                Text("Некорректный адрес сервера")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 840)
            }
        }
        .onAppear {
            vm.updateOpenSizeIfNeeded()
            installOutsideClickMonitor()
        }
        .onDisappear {
            if let monitor = outsideClickMonitor {
                NSEvent.removeMonitor(monitor)
                outsideClickMonitor = nil
            }
        }
    }

    private var closedGamePlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.5))
            Text("Игра закрыта")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Память освобождена. Нажми «Включить», чтобы начать заново.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            Button {
                gameMonitor.startGameAgain()
            } label: {
                Text("Включить")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.orange.opacity(0.85)))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var hourPromptBanner: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Игра активна уже час. Продолжить или закрыть?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Игра занимает примерно \(gameMonitor.gameMemoryMB) МБ оперативной памяти")
                .font(.system(size: 11))
                .foregroundStyle(.orange.opacity(0.95))
            HStack(spacing: 10) {
                Button {
                    gameMonitor.continueSession()
                } label: {
                    Text("Продолжить")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)

                Button {
                    gameMonitor.closeGame()
                } label: {
                    Text("Закрыть")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.85)))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: .orange.opacity(0.25), radius: 10)
        )
    }

    /// In the games tab the notch stays open when the mouse leaves it, so the
    /// only way to dismiss it is a click outside the widget. A global monitor
    /// catches clicks in other apps and closes the games tab.
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor [weak vm] in
                guard let vm,
                      vm.notchState == .open,
                      ArsWidgetViewCoordinator.shared.currentView == .games
                else { return }
                vm.close()
            }
        }
    }
}

@MainActor
final class GameWebViewStore {
    static let shared = GameWebViewStore()

    private var webViews: [String: WKWebView] = [:]

    func webView(for url: URL) -> WKWebView {
        if let existing = webViews.values.first {
            if existing.url == nil {
                existing.load(URLRequest(url: url))
            }
            return existing
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.widgetModeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        webViews["games"] = webView
        GameSessionMonitor.shared.noteGameLoaded()
        return webView
    }

    /// Applied only inside the widget's web view ("widget" marker in the URL).
    /// The games themselves are never changed: the page simply renders with a
    /// black backdrop and without theme controls while embedded here.
    private static let widgetModeScript = """
    (function () {
      const css = `
        html, body { background: #000 !important; }
        [data-st4="root"] { background: #000 !important; }
        iframe, #kizuna-ui { background: #000 !important; }
        [title="Светлый или ночной фон"], [title="Светлая или ночная тема"] { display: none !important; }
        [onclick*="toggleTheme"], [onclick*="toggleBackdrop"], [onclick*="useAutoTheme"] { display: none !important; }
        [sc-camel-on-click*="toggleTheme"], [sc-camel-on-click*="toggleBackdrop"], [sc-camel-on-click*="useAutoTheme"] { display: none !important; }
      `;
      const style = document.createElement('style');
      style.textContent = css;
      document.documentElement.appendChild(style);

      const apply = () => {
        try {
          document.documentElement.style.setProperty('background', '#000', 'important');
          if (document.body) document.body.style.setProperty('background', '#000', 'important');
          document.querySelectorAll('[data-st4="root"]').forEach((el) => {
            el.style.setProperty('background', '#000', 'important');
          });
          document.querySelectorAll('[data-st4="root"] > div').forEach((el) => {
            if (el.style.position === 'relative') {
              el.style.setProperty('padding-top', '4px', 'important');
            }
          });
          document.querySelectorAll('[data-screen-label]').forEach((el) => {
            el.style.setProperty('padding-top', '8px', 'important');
          });
          document.querySelectorAll('iframe').forEach((f) => {
            f.style.setProperty('background', '#000', 'important');
          });
        } catch (_) {}
      };

      apply();
      try {
        const observer = new MutationObserver(apply);
        observer.observe(document.documentElement, {
          subtree: true,
          childList: true,
          attributes: true,
          attributeFilter: ['style', 'class', 'onclick'],
        });
      } catch (_) {}
      window.addEventListener('load', apply);
      document.addEventListener('DOMContentLoaded', apply);
    })();
    """

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
    let url: URL

    func makeNSView(context: Context) -> TrackingContainerView {
        let webView = GameWebViewStore.shared.webView(for: url)
        return TrackingContainerView(webView: webView)
    }

    func updateNSView(_ container: TrackingContainerView, context: Context) {
        let webView = GameWebViewStore.shared.webView(for: url)
        container.updateWebView(webView)

        if webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }
}

final class TrackingContainerView: NSView {
    private(set) var webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 24
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

    func updateWebView(_ newWebView: WKWebView) {
        guard webView !== newWebView else { return }
        webView.removeFromSuperview()
        webView = newWebView
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 24
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
