import AppKit

/// ⌃⇧V flow: snapshot the clipboard → pop a menu of valid transforms at the
/// cursor → run the chosen transform → write the payload to the pasteboard →
/// synthesize ⌘V into whichever app had focus before the menu opened.
@MainActor
final class PasteCoordinator: NSObject {
    static let shared = PasteCoordinator()

    private override init() {
        super.init()
    }

    func showMenu() async {
        let content = readClipboard()
        let transforms = PasteTransform.available(for: content)
        guard !transforms.isEmpty else {
            presentAlert(
                "Nothing to transform",
                "The clipboard has no content Advanced Paste can transform."
            )
            return
        }
        // The panel activates us; ⌘V must land back in the app that had focus.
        let previousApp = NSWorkspace.shared.frontmostApplication

        let picked = await PastePanelController.shared.present(
            rows: transforms.map { PasteRowModel($0) },
            preview: preview(for: content)
        )
        previousApp?.activate() // give focus back, picked or dismissed

        guard let transform = picked else { return } // dismissed without a pick
        await execute(transform, content: content)
    }

    /// One-line clipboard summary for the panel's header chip.
    private func preview(for content: ClipboardContent) -> String {
        if let text = content.text, !text.isEmpty {
            let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return collapsed.count > 60 ? String(collapsed.prefix(60)) + "…" : collapsed
        }
        if let image = content.image { return "Image \(image.width)×\(image.height)" }
        if let file = content.fileURLs.first {
            let extra = content.fileURLs.count > 1 ? " +\(content.fileURLs.count - 1)" : ""
            return file.lastPathComponent + extra
        }
        if content.hasHTML { return "HTML" }
        return "Empty"
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
