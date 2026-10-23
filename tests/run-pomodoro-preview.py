"""Render the production Pomodoro UI with isolated settings and OS effects disabled."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
output = root.parents[1] / 'outputs' / 'pomodoro-redesign'
output.mkdir(parents=True, exist_ok=True)
manager = (root / 'ArsWidget/managers/PomodoroManager.swift').read_text()
# Keep actual timer/task/review code. Redirect every setting to a disposable suite;
# notifications, sound and the full-screen break overlay are not part of this QA.
manager = manager.replace('UserDefaults.standard', 'previewDefaults')
manager = re.sub(r'@AppStorage\("([^"]+)"\)', r'@AppStorage("\1", store: previewDefaults)', manager)
manager = manager.replace('        let center = UNUserNotificationCenter.current()\n        center.delegate = self\n        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }', '')

def no_effect(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[:opening + 1] + '\n    }' + source[end:]

manager = no_effect(manager, 'private func notify(')
manager = no_effect(manager, 'private func playSound(')
fixture = r'''
import AppKit
import SwiftUI
let previewSuite = "ArsWidget.PomodoroPreview." + UUID().uuidString
let previewDefaults = UserDefaults(suiteName: previewSuite)!
final class PomodoroBreakOverlayWindow {
    func showOverlay(blocksInput: Bool) {}
    func hideOverlay() {}
}
extension Notification.Name { static let pomodoroReviewReady = Notification.Name("preview.review") }
@MainActor final class ArsWidgetViewModel: ObservableObject {
    func updateOpenSizeIfNeeded() {}
}
@main struct Preview {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        defer { previewDefaults.removePersistentDomain(forName: previewSuite) }
        let manager = PomodoroManager.shared
        let vm = ArsWidgetViewModel()
        let directory = CommandLine.arguments[1]
        func render(_ name: String) {
            let content = PomodoroView().environmentObject(vm)
                .padding(.top, 8).frame(width: 562).background(.black)
            let host = NSHostingView(rootView: content)
            let size = host.fittingSize
            precondition(size.width <= 563)
            precondition(size.height <= (manager.showStatistics || manager.awaitingReview ? 594 : 300), "Content exceeds notch height budget: \(size)")
            let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            window.orderBack(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = bitmap.representation(using: .png, properties: [:])!
            try! data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            print(name, Int(size.width), Int(size.height))
            window.orderOut(nil)
        }
        precondition(!manager.showStatistics && manager.tasks.isEmpty)
        render("idle")
        manager.start()
        precondition(manager.isRunning && manager.phase == .work && manager.tasks.count == 1, "One-click empty start must create a valid focus task")
        manager.renameTask(manager.activeTaskID!, to: "Подготовить следующую большую идею")
        render("running")
        manager.pause()
        precondition(!manager.isRunning)
        manager.start()
        precondition(manager.isRunning && manager.tasks.count == 1, "Resume must not create duplicate tasks")
        manager.pause()
        render("paused")
        manager.start()
        manager.stopAndReview()
        precondition(manager.awaitingReview && !manager.isRunning)
        render("review")
        manager.submitReview(completedTask: false, continuation: .breakFirst)
        precondition(manager.phase == .shortBreak && manager.isRunning)
        manager.showStatistics = false
        render("break")
        manager.reset()
        manager.showStatistics = true
        render("workspace")
        manager.reset()
        print("Pomodoro QA passed: production views fit, quick start, pause/resume, review and break transitions")
        manager.start()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        manager.pause()
        let savedBeforeResume = manager.activeTask!.totalFocusSeconds
        precondition(savedBeforeResume >= 1)
        manager.start()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        manager.stopAndReview()
        manager.submitReview(completedTask: false, continuation: .idle)
        let newlySaved = manager.activeTask!.totalFocusSeconds - savedBeforeResume
        precondition(newlySaved == 1, "Stop/review must not count the previously saved paused segment again")
        print("Pause/resume focus accounting regression: PASS")
    }
}
'''.replace('\\\\', '\\')
with tempfile.TemporaryDirectory(prefix='arswidget-pomodoro-') as tmp:
    path = Path(tmp)
    (path / 'Manager.swift').write_text(manager)
    (path / 'Preview.swift').write_text(fixture)
    (path / 'View.swift').write_text((root / 'ArsWidget/components/Pomodoro/PomodoroView.swift').read_text())
    subprocess.run(['swiftc', '-module-cache-path', '/private/tmp/arswidget-tests-module-cache', str(path / 'Manager.swift'), str(path / 'Preview.swift'), str(path / 'View.swift'), '-o', str(path / 'preview')], check=True)
    subprocess.run([str(path / 'preview'), str(output)], check=True)
