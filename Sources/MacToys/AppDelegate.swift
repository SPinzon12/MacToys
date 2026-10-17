import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeys()
    private lazy var panel = MenuPanelController(model: makePanelModel())

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        if !Permissions.current.allGranted {
            PermissionsWindowController.shared.show()
        }
        hotKeys.register()
        ClipboardHistoryService.shared.start()
        OCRService.warmUp() // first OCR of a new build path costs ~26 s; pay it now
        KeepAwakeController.shared.onChange = { [weak self] in
            self?.updateStatusIcon()
            self?.refreshPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeepAwakeController.shared.stopForTermination() // macOS would release them anyway; be explicit
    }

    // MARK: - Status item

    /// The status item opens the glass panel (UI/MenuPanel.swift) instead of a menu.
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = BrandGlyph.menuBar()
        item.button?.toolTip = "MacToys"
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button else { return }
        refreshPanel()
        panel.toggle(below: button)
    }

    /// A filled cup while Keep Awake is on, so the state is visible at a glance.
    private func updateStatusIcon() {
        let active = KeepAwakeController.shared.isActive
        statusItem?.button?.image = active
            ? NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "MacToys — Keep Awake on")
            : BrandGlyph.menuBar()
        statusItem?.button?.toolTip = active ? "MacToys — Keep Awake on" : "MacToys"
    }

    // MARK: - Panel

    private func makePanelModel() -> MenuPanelModel {
        let model = MenuPanelModel(version: AppVersion.label())
        model.onModule = { [weak self] module in
            self?.panel.close()
            switch module {
            case .colorPicker: ColorPickerModule.trigger()
            case .textExtractor: TextExtractorModule.trigger()
            case .clipboard: AdvancedPasteModule.trigger()
            }
        }
        model.onKeepAwake = { duration in
            if let duration {
                KeepAwakeController.shared.start(duration)
            } else {
                KeepAwakeController.shared.stop()
            }
        }
        model.onExtendKeepAwake = { KeepAwakeController.shared.extend(by: 15 * 60) }
        model.onAllowDisplaySleep = { [weak self] allow in
            KeepAwakeController.shared.allowDisplaySleep = allow
            self?.refreshPanel()
        }
        model.onLaunchAtLogin = { [weak self] in
            LaunchAtLogin.toggle()
            self?.refreshPanel()
        }
        model.onPermissions = { [weak self] in
            self?.panel.close()
            PermissionsWindowController.shared.show()
        }
        model.onClearHistory = { [weak self] in
            self?.panel.close()
            self?.clearHistory()
        }
        model.onQuit = { NSApp.terminate(nil) }
        return model
    }

    /// Pulls live state into the panel: permissions and the login item can
    /// change in System Settings while MacToys runs.
    private func refreshPanel() {
        let model = panel.model
        let keepAwake = KeepAwakeController.shared
        model.keepAwake = keepAwake.session
        model.allowDisplaySleep = keepAwake.allowDisplaySleep
        model.permissions = Permissions.current
        model.launchAtLoginAvailable = LaunchAtLogin.isAvailable
        model.launchAtLogin = LaunchAtLogin.isAvailable && LaunchAtLogin.isEnabled
        model.now = Date()
    }

    private func clearHistory() {
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
