import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeys()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        Permissions.preflight()
        hotKeys.register()
        ClipboardHistoryService.shared.start()
        OCRService.warmUp() // first OCR of a new build path costs ~26 s; pay it now
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "wand.and.stars",
            accessibilityDescription: "Mac PowerToys"
        )
        item.button?.toolTip = "Mac PowerToys"

        let menu = NSMenu()
        menu.addItem(headerItem())
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
        // Target is nil on purpose: quit goes through the responder chain to NSApp.
        let quit = NSMenuItem(
            title: "Quit Mac PowerToys",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    /// Disabled bold app name on top: the classic Mac menu-extra header.
    private func headerItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Mac PowerToys", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: "Mac PowerToys",
            attributes: [.font: NSFont.menuFont(ofSize: 0).withWeight(.bold)]
        )
        item.isEnabled = false
        return item
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
