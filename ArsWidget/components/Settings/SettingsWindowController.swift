//
//  SettingsWindowController.swift
//  ArsWidget
//
//  Created by Alexander on 2025-06-14.
//

import AppKit
import SwiftUI
import Defaults
import Sparkle

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var updaterController: SPUStandardUpdaterController?
    private var selectedTab = "General"

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        setupWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUpdaterController(_ controller: SPUStandardUpdaterController) {
        self.updaterController = controller
        // Recreate the content view with the proper updater controller
        setupWindow()
    }

    private func setupWindow() {
        guard let window = window else { return }

        window.title = String(localized: "Настройки arsansara ☯")
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true

        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary, .moveToActiveSpace]

        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false

        // Configure window to be a standard document-style window
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("arswidgetSettingsWindow")

        // Create the SwiftUI content
        let settingsView = SettingsView(updaterController: updaterController, initialTab: selectedTab)
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView

        // Handle window closing
        window.delegate = self
    }

    func showWindow(selecting tab: String? = nil) {
        guard let window else { return }

        if let tab, selectedTab != tab {
            selectedTab = tab
            setupWindow()
        }

        // Activation must happen before ordering the window. Doing this in the
        // opposite order can leave the settings window behind the front app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if !window.isVisible {
            window.center()
        }

        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            window.makeMain()
        }
    }

    override func close() {
        super.close()
        relinquishFocus()
    }

    private func relinquishFocus() {
        window?.orderOut(nil)

        // Set app back to accessory mode immediately
        NSApp.setActivationPolicy(.accessory)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure app is in regular mode when window becomes key
        NSApp.setActivationPolicy(.regular)
    }

    func windowDidResignKey(_ notification: Notification) {
    }

}
