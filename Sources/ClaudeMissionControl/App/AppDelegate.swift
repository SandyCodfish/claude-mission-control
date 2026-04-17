// Sources/ClaudeMissionControl/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock by default (menu bar-only app)
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController()
        menuBarController.setup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep running in menu bar when window is closed
    }
}
