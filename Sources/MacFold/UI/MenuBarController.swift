import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let angleItem = NSMenuItem(title: "Connecting…", action: nil, keyEquivalent: "")
    private let statusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enable effect", action: #selector(toggle), keyEquivalent: "")
    private let controller: FoldController
    private let showSettings: () -> Void

    init(controller: FoldController, showSettings: @escaping () -> Void) {
        self.controller = controller
        self.showSettings = showSettings
        super.init()
        item.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "MacFold")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "MacFold — lid-controlled blur"
        menu.autoenablesItems = false
        angleItem.isEnabled = false
        statusItem.isEnabled = false
        menu.addItem(angleItem)
        menu.addItem(statusItem)
        menu.addItem(.separator())
        enabledItem.target = self
        menu.addItem(enabledItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let retry = NSMenuItem(title: "Reconnect sensor", action: #selector(reconnect), keyEquivalent: "")
        retry.target = self
        menu.addItem(retry)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MacFold", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.delegate = self
        item.menu = menu
    }

    func refresh() {
        angleItem.title = controller.angle.map { String(format: "Lid angle · %.0f°", $0) } ?? "Lid angle · unavailable"
        statusItem.title = controller.status
        enabledItem.state = controller.settings.configuration.enabled ? .on : .off
        item.button?.appearsDisabled = !controller.settings.configuration.enabled
    }
    func menuWillOpen(_ menu: NSMenu) { refresh() }
    @objc private func toggle() { controller.settings.update { $0.enabled.toggle() }; refresh() }
    @objc private func openSettings() { showSettings() }
    @objc private func reconnect() { controller.retry() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
