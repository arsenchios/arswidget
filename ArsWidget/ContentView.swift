//
//  ContentView.swift
//  ArsWidgetApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: ArsWidgetViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = ArsWidgetViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var vocabManager = VocabManager.shared
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    @ObservedObject var aiUsageManager = AIUsageManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject private var gameMonitor = GameSessionMonitor.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.showNotHumanFace) var showNotHumanFace

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var showsVocabLayout: Bool {
        vm.notchState == .open && vm.isVocabPromptPresented
    }

    private var closedMusicCenterWidth: CGFloat {
        coordinator.expandingView.show && coordinator.expandingView.type == .music
            && Defaults[.sneakPeekStyles] == .inline ? 380 : vm.closedNotchSize.width
    }

    private var closedMusicSideWidth: CGFloat {
        max(max(0, vm.effectiveClosedNotchHeight - 12) + 4 + 36 + Self.closedIndicatorsGap,
            closedTrailingIndicatorsWidth)
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            return closedMusicCenterWidth + 2 * closedMusicSideWidth
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        // Отступ зеркалится слева (см. ClosedActivityIndicators), поэтому в
        // ширину зоны наведения он входит дважды.
        chinWidth += 2 * closedTrailingIndicatorsWidth

        return chinWidth
    }

    private static let closedAIUsageCapsuleSpacing: CGFloat = 5
    /// Просвет между самим вырезом и первой капсулой.
    private static let closedIndicatorsGap: CGFloat = 8

    /// The user controls the compact row per provider in the System tab.
    private var closedAIUsageMetrics: [AIUsageMetric] {
        aiUsageManager.connectedMetrics
            .filter(aiUsageManager.isShownInClosedNotch)
            .sorted { $0.closedNotchOrder < $1.closedNotchOrder }
    }

    /// The closed row intentionally shows values only: the fixed service
    /// colours identify the provider without taking space from the percentage.
    private func closedAIUsageCapsuleWidth(for metric: AIUsageMetric) -> CGFloat {
        let value = aiUsageManager.value(for: metric)
        let number = value.map(metric.formattedValue) ?? "—"
        return ceil(CGFloat(number.count) * 7.2 + 18)
    }

    /// Matches the capsules actually drawn.
    private var closedAIUsageWidth: CGFloat {
        let metrics = closedAIUsageMetrics
        guard !metrics.isEmpty else { return 0 }
        return metrics.reduce(CGFloat(0)) { partial, metric in
            partial + closedAIUsageCapsuleWidth(for: metric)
        }
            + CGFloat(metrics.count - 1) * Self.closedAIUsageCapsuleSpacing
    }

    private var closedPomodoroWidth: CGFloat {
        shouldShowClosedPomodoroIndicator ? max(0, vm.effectiveClosedNotchHeight + 18) : 0
    }

    /// Всё, что дорисовано справа от выреза в свёрнутом виде.
    private var closedTrailingIndicatorsWidth: CGFloat {
        let pomodoro = closedPomodoroWidth
        let ai = shouldShowClosedAIUsageIndicators ? closedAIUsageWidth : 0
        guard pomodoro > 0 || ai > 0 else { return 0 }
        let between: CGFloat = (pomodoro > 0 && ai > 0) ? Self.closedAIUsageCapsuleSpacing : 0
        return Self.closedIndicatorsGap + pomodoro + between + ai
    }

    private var shouldShowClosedPomodoroIndicator: Bool {
        vm.notchState == .closed && pomodoroManager.isRunning
    }

    private var shouldShowClosedAIUsageIndicators: Bool {
        vm.notchState == .closed
            && !closedAIUsageMetrics.isEmpty
    }

    private var shouldKeepOpenOnMouseLeave: Bool {
        vm.notchState == .open && (
            vm.isVocabPromptPresented || coordinator.isFirstRunTourPresented
                || coordinator.currentView == .games
                || vm.isModalInteractionActive
        )
    }

    private var interactiveNotchHeight: CGFloat? {
        guard vm.notchState == .open else { return nil }
        // System actions sit at the very bottom; retain hover a little below the visual panel.
        return vm.notchSize.height + (coordinator.currentView == .systemStats ? extendedHoverPadding : 0)
    }

    private var closedPomodoroMinutesText: String {
        let minutes = Int(ceil(Double(max(pomodoroManager.secondsRemaining, 0)) / 60.0))
        return String(format: "%02d", max(minutes, 0))
    }

    private var pomodoroAccentColor: Color {
        switch pomodoroManager.phase {
        case .work, .idle:
            return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .shortBreak, .longBreak:
            return Color(red: 0.35, green: 0.85, blue: 0.55)
        }
    }

    private var openInnerWidth: CGFloat {
        if vm.isVocabPromptPresented { return VocabPromptCardView.width }
        let sideInset = (
            Defaults[.cornerRadiusScaling]
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.opened.bottom
        ) + 12
        return max(vm.isVocabPromptPresented ? 340 : 420, vm.notchSize.width - (sideInset * 2))
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()

        ZStack(alignment: .top) {
            if vm.notchState == .closed && gameMonitor.showHourlyReminder {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 9, height: 9)
                    .shadow(color: Color.orange.opacity(0.9), radius: 5)
                    .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                    .offset(x: vm.closedNotchSize.width / 2 + 18, y: 0)
            }

            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(width: showsVocabLayout ? VocabPromptCardView.width : nil, alignment: .top)
                    .padding(
                        .horizontal,
                        showsVocabLayout ? 0 : vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? (vm.isVocabPromptPresented ? 0 : 12) : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        // System values refresh independently of the view.
                        // A shadow on the open panel was redrawn with each
                        // refresh and flashed at the bottom edge; retain it
                        // only for the small closed hover state.
                        color: (vm.notchState == .closed && isHovering && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear,
                        radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )

                mainLayout
                    .frame(height: interactiveNotchHeight, alignment: .top)
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if vm.notchState == .closed { doOpen() }
                        },
                        including: vm.notchState == .closed ? .all : .none
                    )
                    .panGesture(
                        direction: .down,
                        enabled: Defaults[.enableGestures] && !vm.isVocabPromptPresented
                    ) { translation, phase in
                        handleDownGesture(translation: translation, phase: phase)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive && !shouldKeepOpenOnMouseLeave {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose && !self.shouldKeepOpenOnMouseLeave {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .pomodoroReviewReady)) { _ in
                        coordinator.currentView = .pomodoro
                        vm.open()
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose && !shouldKeepOpenOnMouseLeave {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose && !self.shouldKeepOpenOnMouseLeave {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose && !shouldKeepOpenOnMouseLeave {
                    vm.close()
                }
            }
        }
        .onChange(of: vm.isVocabPromptPresented) { _, visible in
            if visible {
                hoverTask?.cancel()
                gestureProgress = .zero
            }
        }
        .onChange(of: coordinator.currentView) { _, _ in
            vm.updateOpenSizeIfNeeded()
        }
        .onChange(of: coordinator.isFirstRunTourPresented) { _, shown in
            guard shown, vm.screenUUID == nil || vm.screenUUID == coordinator.selectedScreenUUID else { return }
            withAnimation(animationSpring) { vm.open() }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                ArsWidgetBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if vm.notchState == .closed && (shouldShowClosedPomodoroIndicator || shouldShowClosedAIUsageIndicators) && !vm.hideOnClosed {
                          ClosedActivityIndicators()
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          ArsWidgetFaceAnimation()
                       } else if vm.notchState == .open && vm.isVocabPromptPresented {
                           Color.clear
                               .frame(width: VocabPromptCardView.width, height: max(24, vm.effectiveClosedNotchHeight))
                       } else if vm.notchState == .open {
                           ArsWidgetHeader()
                               .frame(width: openInnerWidth, height: max(24, vm.effectiveClosedNotchHeight))
                               .frame(maxWidth: .infinity, alignment: .center)
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    openTabContent()
                }
                .frame(width: openInnerWidth, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    private func openTabContent() -> some View {
        if vm.isVocabPromptPresented {
            VocabPromptCardView { height in
                guard abs(vm.vocabPromptHeight - height) > 1 else { return }
                withAnimation(animationSpring) {
                    vm.vocabPromptHeight = height
                    vm.updateOpenSizeIfNeeded()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else if coordinator.isFirstRunTourPresented {
            FirstRunTourView()
                .frame(maxWidth: .infinity, alignment: .top)
        } else {
            switch coordinator.currentView {
            case .home:
                NotchHomeView(albumArtNamespace: albumArtNamespace)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .shelf:
                ShelfView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .pomodoro:
                centeredOpenTab { PomodoroView() }
            case .reminders:
                centeredOpenTab { RemindersView() }
            case .clipboard:
                centeredOpenTab { ClipboardHistoryView() }
            case .breathing:
                centeredOpenTab { BreathingView() }
            case .vocab:
                centeredOpenTab { VocabView() }
            case .games:
                centeredOpenTab { GamesView() }
            case .sessionTimer:
                centeredOpenTab { SessionTimerView() }
            case .systemStats:
                centeredOpenTab { SystemStatsView() }
            }
        }
    }

    private func centeredOpenTab<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    @ViewBuilder
    func ArsWidgetFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .clipped()
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                    )
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )

                musicVisualizerCapsule
            }
            .padding(.trailing, Self.closedIndicatorsGap)
            .frame(width: closedMusicSideWidth, alignment: .trailing)

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(width: closedMusicCenterWidth)

            HStack(spacing: Self.closedAIUsageCapsuleSpacing) {
                closedStatusIndicators
            }
            .padding(.leading, Self.closedIndicatorsGap)
            .frame(width: closedMusicSideWidth, alignment: .leading)
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func ClosedActivityIndicators() -> some View {
        // Окно виджета центрируется по экрану. Всё, что дорисовано справа,
        // уводит чёрный прямоугольник влево от настоящего выреза — и капсулы
        // уезжают под него, обрезая буквы и проценты. Зеркальный пустой
        // отступ слева держит вырез ровно на своём месте.
        HStack(spacing: 0) {
            Color.clear
                .frame(width: closedTrailingIndicatorsWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)

            HStack(spacing: Self.closedAIUsageCapsuleSpacing) {
                closedStatusIndicators
            }
            .padding(.leading, Self.closedIndicatorsGap)
            .frame(width: closedTrailingIndicatorsWidth, alignment: .leading)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var pomodoroCapsule: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .semibold))
            PomodoroMinuteFlipText(value: closedPomodoroMinutesText)
        }
        .foregroundStyle(pomodoroAccentColor)
        .padding(.horizontal, 8)
        .frame(
            width: max(0, vm.effectiveClosedNotchHeight + 18),
            height: max(0, vm.effectiveClosedNotchHeight - 12),
            alignment: .center
        )
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .layoutPriority(2)
    }

    @ViewBuilder
    private var closedStatusIndicators: some View {
        if shouldShowClosedPomodoroIndicator {
            pomodoroCapsule
        }

        if shouldShowClosedAIUsageIndicators {
            closedAIUsageIndicators
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var closedAIUsageIndicators: some View {
        HStack(spacing: Self.closedAIUsageCapsuleSpacing) {
            ForEach(closedAIUsageMetrics) { metric in
                if let value = aiUsageManager.value(for: metric) {
                    aiUsageCapsule(metric: metric, value: value)
                }
            }
        }
    }

    private func aiUsageCapsule(metric: AIUsageMetric, value: Double) -> some View {
        return HStack(spacing: 0) {
            Text(metric.formattedValue(value))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .fixedSize()
        // Stale numbers are dimmed instead of silently pretending to be live.
        .foregroundStyle(metric.tint.opacity(aiUsageManager.isStale ? 0.45 : 1))
        .frame(
            width: closedAIUsageCapsuleWidth(for: metric),
            height: max(0, vm.effectiveClosedNotchHeight - 12)
        )
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    // Keep numeric inference outside ViewBuilder: a clean Swift compiler can
    // otherwise exhaust its type-check budget on the combined expression.
    private func visualizerPulse(time: TimeInterval, index: Int) -> Double {
        let channel = Double(index)
        let frequency: Double = 3.0 + channel * 0.7
        let phase: Double = time * frequency + channel * 1.8
        return (sin(phase) + 1.0) / 2.0
    }

    private var musicVisualizerCapsule: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !musicManager.isPlaying)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    let pulse: Double = visualizerPulse(time: time, index: index)
                    Capsule()
                        .fill(Defaults[.coloredSpectrogram]
                              ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.65)
                              : Color.white.opacity(0.85))
                        .frame(width: 2, height: musicManager.isPlaying ? 4 + pulse * 10 : 4)
                        .animation(.linear(duration: 0.25), value: pulse)
                }
            }
            .frame(width: 20, height: 14)
        }
        .frame(width: 36, height: max(14, vm.effectiveClosedNotchHeight - 12))
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .accessibilityLabel(musicManager.isPlaying ? "Музыка воспроизводится" : "Музыка на паузе")
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.shelfEnabled] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()

        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }

            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }

                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }

                    if self.vm.notchState == .open
                        && !self.vm.isBatteryPopoverActive
                        && !SharingStateManager.shared.preventNotchClose
                        && !self.shouldKeepOpenOnMouseLeave
                    {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

private struct PomodoroMinuteFlipText: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .animation(.smooth(duration: 0.35), value: value)
            .accessibilityLabel("Осталось \(value) минут")
    }
}

#Preview {
    let vm = ArsWidgetViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
