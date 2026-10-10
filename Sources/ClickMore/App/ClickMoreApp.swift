import AppKit
import SwiftUI
import ClickMoreCore

@main
enum ClickMoreApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var testBoard: TestBoardController?
    let controller: AppController

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let testing = CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") || CommandLine.arguments.contains("--test-target")
        let url = testing
            ? FileManager.default.temporaryDirectory.appendingPathComponent("ClickMore-tests-\(UUID().uuidString)/layout.json")
            : support.appendingPathComponent("ClickMore/layout.json")
        controller = AppController(store: StateStore(url: url))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationMenu()
        if CommandLine.arguments.contains("--test-target") {
            openTestBoard()
            testBoard?.board.publishSnapshot()
            return
        }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "ClickMore")
        status.button?.image?.isTemplate = true
        status.button?.toolTip = "ClickMore"
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        status.menu = menu
        statusItem = status
        controller.showSettings = { [weak self] in self?.openSettings() }
        controller.showTestBoard = { [weak self] in self?.openTestBoard() }
        controller.start()
        if CommandLine.arguments.contains("--integration-test"),
           let receiptIndex = CommandLine.arguments.firstIndex(of: "--target-report"),
           CommandLine.arguments.indices.contains(receiptIndex + 1) {
            RuntimeVerification.startExternal(controller: controller,
                receiptURL: URL(fileURLWithPath: CommandLine.arguments[receiptIndex + 1]))
            return
        }
        if CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") {
            openTestBoard()
            if let testBoard {
                RuntimeVerification.start(controller: controller, board: testBoard.board,
                                          systemEvents: CommandLine.arguments.contains("--integration-test"))
            }
        } else if CommandLine.arguments.contains("--show-settings") {
            openSettings()
        }
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "ClickMore")
        appMenu.action("Settings…") { [weak self] in self?.openSettings() }.keyEquivalent = ","
        appMenu.action("Four-Button Test Board") { [weak self] in self?.openTestBoard() }
        appMenu.addItem(.separator())
        appMenu.action("Quit ClickMore") { NSApp.terminate(nil) }.keyEquivalent = "q"
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller.refreshPermission()
        menu.removeAllItems()
        menu.action("ClickMore · \(controller.layout.spots.count) spots", enabled: false) {}
        menu.action("Enabled", checked: controller.preferences.enabled) { [weak controller] in
            controller?.updatePreferences { $0.enabled.toggle() }
        }
        menu.action("Arrange Click Spots", checked: controller.editing) { [weak controller] in
            guard let controller else { return }; controller.setEditing(!controller.editing)
        }
        menu.action("Add Click Spot") { [weak controller] in controller?.addSpot() }
        menu.action("Remove All Click Spots", enabled: !controller.layout.spots.isEmpty) { [weak controller] in controller?.removeAllSpots() }
        menu.addItem(.separator())
        menu.action("Settings…") { [weak self] in self?.openSettings() }.keyEquivalent = ","
        menu.action("Four-Button Test Board") { [weak self] in self?.openTestBoard() }
        menu.action("Recenter Trigger") { [weak controller] in controller?.recenterTrigger() }
        if !controller.permissionGranted {
            menu.action("Allow Mouse Access…") { [weak controller] in controller?.requestPermission() }
        }
        menu.addItem(.separator())
        menu.action("Quit ClickMore") { NSApp.terminate(nil) }.keyEquivalent = "q"
    }

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "ClickMore Settings"
            window.contentView = NSHostingView(rootView: SettingsView(controller: controller))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        refreshSettingsFocus()
    }

    private func refreshSettingsFocus() {
        controller.setSettingsHasFocus(NSApp.isActive && settingsWindow?.isKeyWindow == true)
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshSettingsFocus() }
    func windowDidResignKey(_ notification: Notification) { refreshSettingsFocus() }
    func windowWillClose(_ notification: Notification) { controller.setSettingsHasFocus(false) }
    func applicationDidBecomeActive(_ notification: Notification) { refreshSettingsFocus() }
    func applicationDidResignActive(_ notification: Notification) { controller.setSettingsHasFocus(false) }

    func openTestBoard() {
        if testBoard == nil { testBoard = TestBoardController(controller: controller) }
        NSApp.activate(ignoringOtherApps: true)
        testBoard?.showWindow(nil)
        testBoard?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) { controller.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
