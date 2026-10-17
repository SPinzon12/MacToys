import Foundation

/// Disk layout: `history.json` (the index) plus `images/<uuid>.png`, all
/// owner-only — clipboard history routinely holds things nobody else should read.
struct ClipboardHistoryStore {
    let directory: URL

    var indexURL: URL { directory.appendingPathComponent("history.json") }
    private var imagesURL: URL { directory.appendingPathComponent("images", isDirectory: true) }

    static var standard: ClipboardHistoryStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ClipboardHistoryStore(directory: support.appendingPathComponent("MacPowerToys", isDirectory: true))
    }

    /// A missing or unreadable index starts an empty history instead of failing launch.
    func load() -> ClipboardHistory {
        guard let data = try? Data(contentsOf: indexURL),
              let history = try? JSONDecoder().decode(ClipboardHistory.self, from: data) else {
            return ClipboardHistory()
        }
        return history
    }

    func save(_ history: ClipboardHistory) throws {
        try prepare(directory)
        let data = try JSONEncoder().encode(history)
        try data.write(to: indexURL, options: [.atomic])
        try ownerOnly(indexURL)
    }

    func writeImage(_ png: Data, for entry: ClipboardEntry) throws {
        guard let name = entry.imageFile else { return }
        try prepare(imagesURL)
        let url = imagesURL.appendingPathComponent(name)
        try png.write(to: url, options: [.atomic])
        try ownerOnly(url)
    }

    func imageData(for entry: ClipboardEntry) -> Data? {
        guard let name = entry.imageFile else { return nil }
        return try? Data(contentsOf: imagesURL.appendingPathComponent(name))
    }

    func deleteImages(of entries: [ClipboardEntry]) {
        for name in entries.compactMap(\.imageFile) {
            try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(name))
        }
    }

    private func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // createDirectory leaves an existing folder's permissions alone.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func ownerOnly(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
