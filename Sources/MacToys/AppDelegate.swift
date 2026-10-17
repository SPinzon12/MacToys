import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private let keepAwakeMenu = NSMenu(title: "Keep Awake")
    private let hotKeys = HotKeys()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        Permissions.preflight()
        hotKeys.register()
        ClipboardHistoryService.shared.start()
        OCRService.warmUp() // first OCR of a new build path costs ~26 s; pay it now
        KeepAwakeController.shared.onChange = { [weak self] in self?.updateStatusIcon() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeepAwakeController.shared.stop() // macOS would release them anyway; be explicit
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "wand.and.stars",
            accessibilityDescription: "MacToys"
        )
        item.button?.toolTip = "MacToys"

        let menu = NSMenu()
        menu.addItem(headerItem())
        menu.addItem(versionItem())
        menu.addItem(.separator())
        menu.addItem(moduleItem("Color Picker", symbol: "eyedropper", action: #selector(runColorPicker), key: "c"))
        menu.addItem(moduleItem("Text Extractor", symbol: "text.viewfinder", action: #selector(runTextExtractor), key: "o"))
        menu.addItem(moduleItem("Clipboard History", symbol: "doc.on.clipboard", action: #selector(runAdvancedPaste), key: "v"))
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Clipboard History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear Clipboard History")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())
        let keepAwake = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
        keepAwake.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "Keep Awake")
        keepAwakeMenu.delegate = self
        keepAwake.submenu = keepAwakeMenu
        menu.addItem(keepAwake)
        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        if !LaunchAtLogin.isAvailable {
            launch.toolTip = "Available when running the MacToys app, not `swift run`."
        }
        menu.addItem(launch)
        launchAtLoginItem = launch
        menu.addItem(.separator())
        // Target is nil on purpose: quit goes through the responder chain to NSApp.
        let quit = NSMenuItem(
            title: "Quit MacToys",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Disabled bold app name on top: the classic Mac menu-extra header.
    private func headerItem() -> NSMenuItem {
        let item = NSMenuItem(title: "MacToys", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: "MacToys",
            attributes: [.font: NSFont.menuFont(ofSize: 0).withWeight(.bold)]
        )
        item.isEnabled = false
        return item
    }

    private func versionItem() -> NSMenuItem {
        let item = NSMenuItem(title: AppVersion.label(), action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: AppVersion.label(),
            attributes: [.font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]
        )
        item.isEnabled = false
        return item
    }

    /// The login-item state can change in System Settings; read it on every open.
    func menuWillOpen(_ menu: NSMenu) {
        if menu === keepAwakeMenu {
            rebuildKeepAwakeMenu()
            return
        }
        guard let item = launchAtLoginItem else { return }
        item.state = !LaunchAtLogin.isAvailable ? .off
            : LaunchAtLogin.isEnabled ? .on
            : LaunchAtLogin.needsApproval ? .mixed : .off
        item.title = LaunchAtLogin.isAvailable && LaunchAtLogin.needsApproval
            ? "Launch at Login (approve in System Settings)"
            : "Launch at Login"
    }

    /// Disabled (greyed) outside a bundle: `validateMenuItem` runs before display.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleLaunchAtLogin) { return LaunchAtLogin.isAvailable }
        return true
    }

    // MARK: - Keep Awake

    /// Rebuilt on every open so the remaining time is current.
    private func rebuildKeepAwakeMenu() {
        let controller = KeepAwakeController.shared
        keepAwakeMenu.removeAllItems()
        if let session = controller.session {
            let status = NSMenuItem(
                title: KeepAwakeSession.statusLabel(remaining: session.remaining(at: Date())),
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            keepAwakeMenu.addItem(status)
            keepAwakeMenu.addItem(.separator())
        }
        for (index, duration) in KeepAwakeDuration.allCases.enumerated() {
            let item = NSMenuItem(title: duration.title, action: #selector(startKeepAwake(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.state = controller.session?.duration == duration ? .on : .off
            keepAwakeMenu.addItem(item)
        }
        if controller.isActive {
            let off = NSMenuItem(title: "Turn Off", action: #selector(stopKeepAwake), keyEquivalent: "")
            off.target = self
            keepAwakeMenu.addItem(off)
        }
        keepAwakeMenu.addItem(.separator())
        let display = NSMenuItem(title: "Allow Display to Sleep", action: #selector(toggleAllowDisplaySleep), keyEquivalent: "")
        display.target = self
        display.state = controller.allowDisplaySleep ? .on : .off
        display.toolTip = "Keep the Mac working (downloads, builds) while the screen turns off."
        keepAwakeMenu.addItem(display)
    }

    /// A filled cup while Keep Awake is on, so the state is visible at a glance.
    private func updateStatusIcon() {
        let active = KeepAwakeController.shared.isActive
        statusItem?.button?.image = NSImage(
            systemSymbolName: active ? "cup.and.saucer.fill" : "wand.and.stars",
            accessibilityDescription: active ? "MacToys — Keep Awake on" : "MacToys"
        )
        statusItem?.button?.toolTip = active ? "MacToys — Keep Awake on" : "MacToys"
    }

    @objc private func startKeepAwake(_ sender: NSMenuItem) {
        let durations = KeepAwakeDuration.allCases
        guard durations.indices.contains(sender.tag) else { return }
        KeepAwakeController.shared.start(durations[sender.tag])
    }

    @objc private func stopKeepAwake() { KeepAwakeController.shared.stop() }

    @objc private func toggleAllowDisplaySleep() {
        KeepAwakeController.shared.allowDisplaySleep.toggle()
    }

    private func moduleItem(_ title: String, symbol: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.keyEquivalentModifierMask = [.control, .shift]
        item.target = self
        return item
    }

    @objc private func runColorPicker() { ColorPickerModule.trigger() }
    @objc private func runTextExtractor() { TextExtractorModule.trigger() }
    @objc private func runAdvancedPaste() { AdvancedPasteModule.trigger() }

    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.toggle() }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Every saved item and image is deleted. The current clipboard stays as it is."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            ClipboardHistoryService.shared.clear()
        }
    }
}

private extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
