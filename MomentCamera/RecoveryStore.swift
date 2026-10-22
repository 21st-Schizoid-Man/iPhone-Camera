import Foundation

/// Fallback files survive failed library imports; older versions used this for Photos failures.
struct RecoveryStore: Sendable {
    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PendingCaptures", isDirectory: true)) {
        self.directory = directory
    }

    func photo(_ data: Data) throws -> URL {
        try prepare()
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    func video(_ temporaryURL: URL) throws -> URL {
        try prepare()
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        try FileManager.default.moveItem(at: temporaryURL, to: url)
        return url
    }

    func items() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { ["jpg", "mov"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
