import AppKit
import CoreServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: FoldController?
    private var menu: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var lastMenuRefresh: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        if CommandLine.arguments.contains("--duo-look") {
            settings.update { $0.applyDuoLook() }
        }
        let controller = FoldController(settings: settings)
        self.controller = controller
        menu = MenuBarController(controller: controller) { [weak self] in self?.showSettings() }
        controller.onStatus = { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.lastMenuRefresh > 0.25 {
                self.menu?.refresh()
                self.lastMenuRefresh = now
            }
        }
        controller.start()
        menu?.refresh()
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        // Finder/Spotlight launches should open a visible window every time.
        // Login launches keep running quietly in the menu bar.
        if !launchedAtLogin || CommandLine.arguments.contains("--settings") {
            showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { controller?.stop() }

    private func showSettings() {
        guard let controller else { return }
        if settingsWindow == nil { settingsWindow = SettingsWindowController(controller: controller) }
        controller.refreshPermission()
        settingsWindow?.present()
    }
}
