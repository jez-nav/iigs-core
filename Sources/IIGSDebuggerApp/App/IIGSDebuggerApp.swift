import AppKit
import SwiftUI

@main
@MainActor
final class IIGSDebuggerApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenus()
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    private func showMainWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = ContentView()
            .frame(minWidth: 1120, minHeight: 760)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "IIGSDebugger"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func installMenus() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(
                title: "Quit IIGSDebugger",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let debuggerMenuItem = NSMenuItem()
        let debuggerMenu = NSMenu(title: "Debugger")
        addDebuggerItem("Boot Local ROM1", key: "b", action: #selector(bootLocalROM1), to: debuggerMenu)
        addDebuggerItem("Load Local ROM1", key: "1", action: #selector(loadLocalROM1), to: debuggerMenu)
        debuggerMenu.addItem(.separator())
        addDebuggerItem("Step", key: "s", action: #selector(step), to: debuggerMenu)
        addDebuggerItem("Run", key: "r", action: #selector(run), to: debuggerMenu)
        addDebuggerItem("Pause", key: ".", action: #selector(pause), to: debuggerMenu)

        let resetItem = NSMenuItem(title: "Reset", action: #selector(reset), keyEquivalent: "r")
        resetItem.keyEquivalentModifierMask = [.command, .shift]
        resetItem.target = self
        debuggerMenu.addItem(resetItem)

        debuggerMenuItem.submenu = debuggerMenu
        mainMenu.addItem(debuggerMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func addDebuggerItem(_ title: String, key: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command]
        item.target = self
        menu.addItem(item)
    }

    @objc private func bootLocalROM1() {
        NotificationCenter.default.post(name: .debuggerBootLocalROMRequested, object: nil)
    }

    @objc private func loadLocalROM1() {
        NotificationCenter.default.post(name: .debuggerLoadLocalROMRequested, object: nil)
    }

    @objc private func step() {
        NotificationCenter.default.post(name: .debuggerStepRequested, object: nil)
    }

    @objc private func run() {
        NotificationCenter.default.post(name: .debuggerRunRequested, object: nil)
    }

    @objc private func pause() {
        NotificationCenter.default.post(name: .debuggerPauseRequested, object: nil)
    }

    @objc private func reset() {
        NotificationCenter.default.post(name: .debuggerResetRequested, object: nil)
    }
}

extension Notification.Name {
    static let debuggerLoadLocalROMRequested = Notification.Name("IIGSDebugger.loadLocalROMRequested")
    static let debuggerBootLocalROMRequested = Notification.Name("IIGSDebugger.bootLocalROMRequested")
    static let debuggerStepRequested = Notification.Name("IIGSDebugger.stepRequested")
    static let debuggerRunRequested = Notification.Name("IIGSDebugger.runRequested")
    static let debuggerPauseRequested = Notification.Name("IIGSDebugger.pauseRequested")
    static let debuggerResetRequested = Notification.Name("IIGSDebugger.resetRequested")
}
