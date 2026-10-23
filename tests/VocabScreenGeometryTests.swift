// run-vocab-screen-geometry-tests.py inserts the actual production methods.
// The real card is hosted in a hidden AppKit panel; user settings stay untouched.
enum NotchState { case open, closed }
enum SettingKey { case showOnAllDisplays, automaticallySwitchDisplay }
enum Defaults {
    static var allDisplays = false
    static subscript(key: SettingKey) -> Bool {
        key == .showOnAllDisplays ? allDisplays : true
    }
}
extension NSScreen {
    var displayUUID: String? { "screen" }
    static func screen(withUUID: String) -> NSScreen? { .main }
}
func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    CGSize(width: 180, height: 32)
}
final class ArsWidgetViewModel: ObservableObject {
    @Published var screenUUID: String?
    @Published var notchState: NotchState = .open
    @Published var notchSize = CGSize(width: 400, height: 320)
    @Published var closedNotchSize = getClosedNotchSize()
    var vocabPromptHeight: CGFloat = 288
    init(screenUUID: String? = nil) { self.screenUUID = screenUUID }
    func updateOpenSizeIfNeeded() {
        guard notchState == .open else { return }
        notchSize = CGSize(width: 400, height: closedNotchSize.height + vocabPromptHeight)
    }
    func close() { notchState = .closed; notchSize = closedNotchSize }
    // __PRODUCTION_REFRESH__
}
final class TestCoordinator {
    var preferredScreenUUID: String? = "screen"
    var selectedScreenUUID = "screen"
}
final class NotchSpaceManager {
    static let shared = NotchSpaceManager()
    let notchSpace = Space()
    final class Space { var windows: Set<NSWindow> = [] }
}
final class AppDelegate: NSObject {
    let vm: ArsWidgetViewModel
    var window: NSWindow?
    var windows: [String: NSWindow] = [:]
    var viewModels: [String: ArsWidgetViewModel] = [:]
    let coordinator = TestCoordinator()
    init(vm: ArsWidgetViewModel, panel: NSWindow) {
        self.vm = vm; self.window = panel
        self.windows = ["screen": panel]; self.viewModels = ["screen": vm]
        super.init()
    }
    func createArsWidgetWindow(for screen: NSScreen, with viewModel: ArsWidgetViewModel) -> NSWindow { window! }
    func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool) {}
    // __PRODUCTION_ADJUST__
}
private struct ScreenGeometryHarness: View {
    @ObservedObject var vm: ArsWidgetViewModel
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: vm.closedNotchSize.height)
            VocabPromptCardView {
                vm.vocabPromptHeight = $0
                vm.updateOpenSizeIfNeeded()
            }
        }
        .frame(width: 400)
        .background(.black)
        .clipShape(NotchShape(topCornerRadius: 19, bottomCornerRadius: 24))
        .frame(height: vm.notchSize.height, alignment: .top)
        .contentShape(Rectangle())
        .frame(width: 680, height: 900, alignment: .top)
        .compositingGroup()
    }
}
@main struct VocabScreenGeometryTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        precondition(NSScreen.main != nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 900),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let vm = ArsWidgetViewModel(screenUUID: "screen")
        let host = NSHostingView(rootView: ScreenGeometryHarness(vm: vm))
        panel.contentView = host
        let delegate = AppDelegate(vm: vm, panel: panel)
        settle(host)
        assertClickable(host)
        // Unlock/wake and display selection use this actual AppDelegate path.
        for allDisplays in [false, true] {
            Defaults.allDisplays = allDisplays
            for _ in 0..<10 {
                delegate.adjustWindowPosition(changeAlpha: true)
                settle(host)
                assertClickable(host)
                precondition(vm.notchSize.height > vm.closedNotchSize.height)
            }
        }
        buttons(host).first { $0.bounds.width > 100 && $0.bounds.width < 200 }!.performClick(nil)
        settle(host)
        precondition(buttons(host).count == 3)
        Defaults.allDisplays = false
        delegate.adjustWindowPosition()
        settle(host)
        assertClickable(host)
        print("Screen refresh regression passed: actual positioning methods, 20 refreshes, reveal and hit testing")
    }
    @MainActor static func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
    }
    @MainActor static func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
    }
    @MainActor static func assertClickable(_ host: NSView) {
        for button in buttons(host) {
            let rect = button.convert(button.bounds, to: host.superview)
            precondition(host.hitTest(NSPoint(x: rect.midX, y: rect.midY)) === button,
                         "Screen refresh clipped a visible button: \(rect)")
        }
    }
}
