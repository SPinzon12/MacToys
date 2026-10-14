import AppKit

/// ⌃⇧V flow: snapshot the clipboard → pop a menu of valid transforms at the
/// cursor → run the chosen transform → write the payload to the pasteboard →
/// synthesize ⌘V into whichever app had focus before the menu opened.
@MainActor
final class PasteCoordinator: NSObject {
    static let shared = PasteCoordinator()

    /// The 1×1 panel that anchors the menu under the cursor.
    private var panel: NSWindow?
    /// Set by the menu action while the menu is tracking.
    private var chosen: PasteTransform?

    private override init() {
        super.init()
    }

    func showMenu() {
        let content = readClipboard()
        let transforms = PasteTransform.available(for: content)
        guard !transforms.isEmpty else {
            presentAlert(
                "Nothing to transform",
                "The clipboard has no content Advanced Paste can transform."
            )
            return
        }
        // The menu activates us; ⌘V must land back in the app that had focus.
        let previousApp = NSWorkspace.shared.frontmostApplication

        chosen = nil
        let menu = buildMenu(transforms)
        popup(menu: menu)

        guard let transform = chosen else {
            previousApp?.activate() // dismissed without a pick: give focus back
            return
        }
        previousApp?.activate()
        Task { await execute(transform, content: content) }
    }

    // MARK: - Menu

    private func buildMenu(_ transforms: [PasteTransform]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false // items carry target/action already
        for transform in transforms {
            let item = NSMenuItem(
                title: transform.title,
                action: #selector(transformChosen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = transform.rawValue
            menu.addItem(item)
        }
        return menu
    }

    /// Accessory apps have no window to anchor a menu in, so a 1×1 borderless
    /// panel at the cursor becomes that anchor. `popUp` runs a tracking loop
    /// and returns once the menu is dismissed (item chosen or not).
    private func popup(menu: NSMenu) {
        let mouse = NSEvent.mouseLocation // AppKit global, y-up
        let panel = NSWindow(
            contentRect: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar // above normal windows so the menu shows
        self.panel = panel

        NSApp.activate() // brief activation so the menu can take keys
        panel.makeKeyAndOrderFront(nil)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 1), in: panel.contentView!)

        panel.orderOut(nil)
        self.panel = nil
    }

    @objc private func transformChosen(_ sender: NSMenuItem) {
        chosen = (sender.representedObject as? String).flatMap(PasteTransform.init(rawValue:))
    }

    // MARK: - Execution

    private func execute(_ transform: PasteTransform, content: ClipboardContent) async {
        guard let payload = await transform.run(content) else {
            presentAlert(
                "Transform failed",
                "\(transform.title) could not transform the clipboard content."
            )
            return
        }
        write(payload)
        // A beat for focus to settle in the previous app before ⌘V lands.
        try? await Task.sleep(nanoseconds: 150_000_000)
        SyntheticPaste.send()
    }

    private func write(_ payload: PastePayload) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch payload {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let image):
            let rep = NSBitmapImageRep(cgImage: image)
            if let png = rep.representation(using: .png, properties: [:]) {
                pasteboard.setData(png, forType: .png)
            }
            if let tiff = rep.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff) // apps that read TIFF only
            }
        case .file(let url):
            pasteboard.writeObjects([url as NSURL])
        }
    }

    private func readClipboard() -> ClipboardContent {
        let pasteboard = NSPasteboard.general
        var content = ClipboardContent()
        content.text = pasteboard.string(forType: .string)
        content.html = pasteboard.string(forType: .html)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            content.fileURLs = urls.filter(\.isFileURL)
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: data) {
            content.image = rep.cgImage
        }
        return content
    }

    private func presentAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
