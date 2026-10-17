import AppKit

/// Polls `NSPasteboard.changeCount` (macOS has no change notification) and
/// keeps the persisted history current.
@MainActor
final class ClipboardHistoryService {
    static let shared = ClipboardHistoryService()

    private(set) var history: ClipboardHistory
    private let store: ClipboardHistoryStore
    private var timer: Timer?
    private var lastChangeCount: Int

    private init(store: ClipboardHistoryStore = .standard) {
        self.store = store
        self.history = store.load()
        // Whatever is on the pasteboard at launch is recorded on the first poll.
        self.lastChangeCount = -1
    }

    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { ClipboardHistoryService.shared.poll() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Reads the pasteboard now; the panel calls this so a copy made a
    /// moment ago is already listed.
    func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        let snapshot = Self.snapshot(of: pasteboard)
        // Swapped mid-read (types and contents may belong to different copies,
        // one of them a marked secret): drop it, the next poll reads it whole.
        guard pasteboard.changeCount == changeCount else { return }
        guard let entry = ClipboardEntry.capture(snapshot, date: Date()) else { return }
        let outcome = history.record(entry)
        if outcome.inserted, entry.kind == .image, let png = snapshot.pngData {
            try? store.writeImage(png, for: entry)
        }
        store.deleteImages(of: outcome.evicted)
        persist()
    }

    /// Our own pasteboard writes (pasting an entry or a transform result) are
    /// not new copies.
    func ignoreOwnWrite() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func promote(_ entry: ClipboardEntry) {
        history.promote(entry.id, date: Date())
        persist()
    }

    func clear() {
        store.deleteImages(of: history.removeAll())
        persist()
    }

    func imageData(for entry: ClipboardEntry) -> Data? {
        store.imageData(for: entry)
    }

    private func persist() {
        do {
            try store.save(history)
        } catch {
            // ponytail: history keeps working in memory; next change retries the write
            print("ClipboardHistory: could not save (\(error.localizedDescription))")
        }
    }

    // MARK: - Pasteboard reading

    private static func snapshot(of pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let types = pasteboard.types?.map(\.rawValue) ?? []
        // Skip the expensive reads for marked secrets.
        guard !types.contains(where: PasteboardSnapshot.ignoredMarkers.contains) else {
            return PasteboardSnapshot(types: types)
        }
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        let frontmost = NSWorkspace.shared.frontmostApplication
        var snapshot = PasteboardSnapshot(
            types: types,
            text: pasteboard.string(forType: .string),
            html: pasteboard.string(forType: .html),
            fileURLs: urls.filter(\.isFileURL),
            sourceApp: frontmost?.localizedName,
            sourceBundleID: frontmost?.bundleIdentifier
        )
        let hasText = !(snapshot.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if snapshot.fileURLs.isEmpty, !hasText, let png = pngData(from: pasteboard) {
            snapshot.pngData = png
            if let rep = NSBitmapImageRep(data: png) {
                snapshot.imageSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            }
        }
        return snapshot
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
