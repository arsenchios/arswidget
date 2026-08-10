//
//  ArsWidgetViewModel.swift
//  ArsWidget
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class ArsWidgetViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = ArsWidgetViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: ArsWidgetAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []

    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false
    // Sheets are displayed outside the notch's hover region, so keep it open while one is active.
    @Published var isModalInteractionActive: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    let webcamManager = WebcamManager.shared
    @Published var isCameraExpanded: Bool = false
    @Published var isRequestingAuthorization: Bool = false

    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()

        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)

        setupDetectorObserver()
    }

    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
                isCameraExpanded = false
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
                isCameraExpanded = true
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isRequestingAuthorization = false
            }

        default:
            break
        }
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {

            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2

            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }

        return false
    }

    func open() {
        self.notchSize = openNotchSizeForCurrentView()
        self.notchState = .open

        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    func updateOpenSizeIfNeeded() {
        guard notchState == .open else { return }
        notchSize = openNotchSizeForCurrentView()
    }

    private func openNotchSizeForCurrentView() -> CGSize {
        openNotchSizeForView(
            coordinator.currentView,
            pomodoroExpanded: PomodoroManager.shared.showStatistics
        )
    }

    private func openNotchSizeForView(_ view: NotchViews, pomodoroExpanded: Bool) -> CGSize {
        if coordinator.isFirstRunTourPresented {
            // Карточка тура: заголовок, текст, полоска прогресса и кнопки.
            return .init(width: 640, height: 330)
        }

        switch view {
        case .home, .shelf, .clipboard, .sessionTimer:
            return openNotchSize
        case .systemStats:
            // Built from what is actually on screen: the old fixed height was
            // sized for three AI limits and clipped the tab once more appeared.
            let systemStats = SystemStatsManager.shared
            let aiUsage = AIUsageManager.shared
            var height: CGFloat = 262

            let connectedLimits = aiUsage.connectedMetrics.count
            if connectedLimits > 0 {
                height += CGFloat(connectedLimits) * 21
                if !aiUsage.missingProviders.isEmpty { height += 18 }
            } else {
                height += 46 // "connect AI limits" call to action
            }

            if systemStats.isAILimitsSetupVisible { height += 190 }
            if systemStats.isProcessDetailsVisible { height += 96 }
            if systemStats.showSupport { height += 160 }

            return .init(width: openNotchSize.width, height: height)
        case .reminders:
            // Список напоминаний стал короче, а снизу добавился трекер
            // привычек — вкладка целиком стала выше.
            let habits = HabitsManager.shared
            return .init(width: 640, height: habits.expandedMonthHabitID == nil ? 540 : 720)
        case .vocab:
            return .init(width: 640, height: 560)
        case .games:
            return .init(width: 640, height: 880)
        case .pomodoro:
            return .init(width: 640, height: pomodoroExpanded ? 560 : 240)
        case .breathing:
            return .init(width: openNotchSize.width, height: 240)
        }
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false

        // Preserve the user's last active tab unless the shelf should take over because
        // there are pending shared files and the shelf-open preference is enabled.
        if !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] {
            coordinator.currentView = .shelf
        }
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
