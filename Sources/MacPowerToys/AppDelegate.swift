import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeys()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        Permissions.preflight()
        hotKeys.register()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "wand.and.stars",
            accessibilityDescription: "Mac PowerToys"
        )
        item.button?.toolTip = "Mac PowerToys"

        let menu = NSMenu()
        menu.addItem(moduleItem("Color Picker", symbol: "eyedropper", action: #selector(runColorPicker), key: "c"))
        menu.addItem(moduleItem("Text Extractor", symbol: "text.viewfinder", action: #selector(runTextExtractor), key: "o"))
        menu.addItem(moduleItem("Advanced Paste", symbol: "doc.on.clipboard", action: #selector(runAdvancedPaste), key: "v"))
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
}
