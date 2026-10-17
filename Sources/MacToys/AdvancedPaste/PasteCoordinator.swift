import AppKit

/// ⌃⇧V flow: open the Spotlight-style clipboard history → the user picks an
/// entry (paste as-is) or one of its transforms → write the payload to the
/// pasteboard → synthesize ⌘V into whichever app had focus before the panel.
@MainActor
final class PasteCoordinator: NSObject {
    static let shared = PasteCoordinator()

    private let history = ClipboardHistoryService.shared

    private override init() {
        super.init()
    }

    func showMenu() async {
        history.poll() // a copy made a moment ago is already listed
        // The panel activates us; ⌘V must land back in the app that had focus.
        let previousApp = NSWorkspace.shared.frontmostApplication

        let picked = await PastePanelController.shared.present(
            history: history.history,
            contentFor: { [history] in Self.content(for: $0, imageData: history.imageData(for: $0)) },
            imageData: { [history] in history.imageData(for: $0) }
        )
        previousApp?.activate() // give focus back, picked or dismissed

        switch picked {
        case nil:
            return // dismissed without a pick
        case .entry(let entry):
            guard writeOriginal(entry) else {
                presentAlert("Paste failed", "This clipboard item is no longer available.")
                return
            }
            history.promote(entry)
            await paste()
        case .transform(let entry, let transform):
            let content = Self.content(for: entry, imageData: history.imageData(for: entry))
            await execute(transform, content: content)
        }
    }

    /// Rebuilds the transform input from a history entry.
    private static func content(for entry: ClipboardEntry, imageData: Data?) -> ClipboardContent {
        var content = ClipboardContent(text: entry.text, html: entry.html, fileURLs: entry.fileURLs)
        if entry.kind == .image, let imageData, let rep = NSBitmapImageRep(data: imageData) {
            content.image = rep.cgImage
        }
        return content
    }

    /// Puts the entry back on the pasteboard exactly as it was recorded.
    private func writeOriginal(_ entry: ClipboardEntry) -> Bool {
        let pasteboard = NSPasteboard.general
        switch entry.kind {
        case .text:
            guard let text = entry.text else { return false }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            if let html = entry.html { pasteboard.setString(html, forType: .html) }
        case .image:
            guard let png = history.imageData(for: entry) else { return false }
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff) // apps that read TIFF only
            }
        case .files:
            let existing = entry.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(existing.map { $0 as NSURL })
        }
        history.ignoreOwnWrite()
        return true
    }

    private func paste() async {
        // A beat for focus to settle in the previous app before ⌘V lands.
        try? await Task.sleep(nanoseconds: 150_000_000)
        SyntheticPaste.send()
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
        history.ignoreOwnWrite() // derived output, not a new copy
        await paste()
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

    private func presentAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
