"""Render production controls and every tour step without changing user settings."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
output = root.parents[1] / 'outputs' / 'system-and-tour'
output.mkdir(parents=True, exist_ok=True)
fixture = r'''
import AppKit
import SwiftUI
import IOKit.pwr_mgt
enum NotchViews { case home, pomodoro, reminders, vocab, clipboard, shelf, systemStats, games }
@MainActor final class ArsWidgetViewCoordinator: ObservableObject {
    static let shared = ArsWidgetViewCoordinator()
    @Published var currentView: NotchViews = .home
    func finishFirstRunTour() {}
}
@MainActor final class ArsWidgetViewModel: ObservableObject {
    func updateOpenSizeIfNeeded() {}
    func close() {}
}
final class Assertions: KeepAwakeAssertionProviding {
    func create(mode: KeepAwakeMode, seconds: TimeInterval) -> IOPMAssertionID? { mode == .system ? 1 : 2 }
    func release(_ id: IOPMAssertionID) {}
}
@main struct Preview {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let vm = ArsWidgetViewModel()
        func render<V: View>(_ name: String, _ view: V, heightBudget: CGFloat) {
            let host = NSHostingView(rootView: view.environmentObject(vm).frame(width: 562).padding(12).background(.black))
            let size = host.fittingSize
            precondition(size.height <= heightBudget, "Content exceeds height budget: \(name) \(size)")
            let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            window.orderBack(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = bitmap.representation(using: .png, properties: [:])!
            try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
            print(name, Int(size.width), Int(size.height))
            window.orderOut(nil)
        }
        let manager = KeepAwakeManager(assertions: Assertions(), schedulesTimer: false)
        render("awake-off", KeepAwakeControlsView(manager: manager), heightBudget: 260)
        manager.start(.system, minutes: 30)
        manager.start(.display, minutes: 120)
        render("awake-on", KeepAwakeControlsView(manager: manager), heightBudget: 260)
        for i in FirstRunTourStep.all.indices {
            render("tour-\(i + 1)", FirstRunTourView(initialStep: i), heightBudget: 388)
        }
        print("System/tour QA passed: controls and all 10 tour steps fit the notch")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='arswidget-tour-') as tmp:
    path = Path(tmp)
    (path / 'Preview.swift').write_text(fixture)
    subprocess.run(['swiftc', '-module-cache-path', '/private/tmp/arswidget-tests-module-cache',
        str(root / 'ArsWidget/managers/KeepAwakeManager.swift'),
        str(root / 'ArsWidget/components/SystemStats/KeepAwakeControlsView.swift'),
        str(root / 'ArsWidget/components/Onboarding/FirstRunTourView.swift'),
        str(path / 'Preview.swift'), '-o', str(path / 'preview')], check=True)
    subprocess.run([str(path / 'preview'), str(output)], check=True)
