import Foundation

/// A complete capture is committed by renaming its directory only after all files are written.
/// One actor serializes capture imports, development state and decoration edits.
actor CaptureRepository {
    nonisolated let root: URL

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CaptureLibrary", isDirectory: true)) {
        self.root = root
    }

    nonisolated func url(for record: CaptureRecord, filename: String) -> URL {
        root.appendingPathComponent(record.id.uuidString, isDirectory: true).appendingPathComponent(filename)
    }

    func load() throws -> (records: [CaptureRecord], unreadable: Int) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        var records: [CaptureRecord] = []
        var unreadable = 0
        for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil {
            do {
                let record = try read(directory.appendingPathComponent("record.json"))
                guard record.id.uuidString == directory.lastPathComponent,
                      validFilename(record.originalFilename), validFilename(record.displayFilename),
                      record.thumbnailFilename.map(validFilename) ?? true,
                      FileManager.default.fileExists(atPath: url(for: record, filename: record.originalFilename).path),
                      FileManager.default.fileExists(atPath: url(for: record, filename: record.displayFilename).path)
                else { throw CocoaError(.fileReadCorruptFile) }
                records.append(record)
            } catch { unreadable += 1 }
        }
        return (records.sorted { $0.sortDate > $1.sortDate }, unreadable)
    }

    func importPhoto(original: Data, displayed: Data, metadata: CaptureMetadata, legacyFilename: String? = nil) throws -> CaptureRecord {
        let id = UUID()
        let staging = try prepare(id)
        defer { try? FileManager.default.removeItem(at: staging) }
        let originalName = "original.\(LibraryImages.fileExtension(original))"
        try original.write(to: staging.appendingPathComponent(originalName), options: .atomic)
        let displayName = original == displayed ? originalName : "developed.jpg"
        if displayName != originalName { try displayed.write(to: staging.appendingPathComponent(displayName), options: .atomic) }
        // A thumbnail failure must not discard a successfully captured original.
        let thumbnail = try? LibraryImages.thumbnail(displayed)
        if let thumbnail { try thumbnail.write(to: staging.appendingPathComponent("thumbnail.jpg"), options: .atomic) }
        let record = CaptureRecord(id: id, kind: .photo, importedAt: Date(), metadata: metadata,
                                   originalFilename: originalName, displayFilename: displayName,
                                   thumbnailFilename: thumbnail == nil ? nil : "thumbnail.jpg",
                                   isDeveloped: false, decoration: PhotoDecoration(), legacyFilename: legacyFilename)
        try commit(record, staging: staging)
        return record
    }

    func importVideo(from source: URL, metadata: CaptureMetadata, legacyFilename: String? = nil) throws -> CaptureRecord {
        let id = UUID()
        let staging = try prepare(id)
        defer { try? FileManager.default.removeItem(at: staging) }
        let destination = staging.appendingPathComponent("original.mov")
        // Copy first: failed metadata writes cannot destroy the only video file.
        try FileManager.default.copyItem(at: source, to: destination)
        let thumbnail = LibraryImages.videoThumbnail(destination)
        if let thumbnail { try thumbnail.write(to: staging.appendingPathComponent("thumbnail.jpg"), options: .atomic) }
        let record = CaptureRecord(id: id, kind: .video, importedAt: Date(), metadata: metadata,
                                   originalFilename: "original.mov", displayFilename: "original.mov",
                                   thumbnailFilename: thumbnail == nil ? nil : "thumbnail.jpg",
                                   isDeveloped: true, decoration: PhotoDecoration(), legacyFilename: legacyFilename)
        try commit(record, staging: staging)
        return record
    }

    func markDeveloped(_ ids: [UUID]) throws {
        for id in ids {
            try update(id) { $0.isDeveloped = true }
        }
    }

    func setDecoration(_ decoration: PhotoDecoration, id: UUID) throws {
        try update(id) { $0.decoration = decoration }
    }

    func markExported(_ id: UUID) throws { try update(id) { $0.lastExportedAt = Date() } }

    func migrateLegacyFiles(_ store: RecoveryStore) throws {
        let importedNames = Set(try load().records.compactMap(\.legacyFilename))
        for file in store.items() where !importedNames.contains(file.lastPathComponent) {
            let metadata = CaptureMetadata(capturedAt: nil, timeZoneIdentifier: TimeZone.current.identifier,
                                           deviceModel: "设备型号未记录", city: nil)
            if file.pathExtension == "mov" {
                _ = try importVideo(from: file, metadata: metadata, legacyFilename: file.lastPathComponent)
            } else {
                let data = try Data(contentsOf: file)
                _ = try importPhoto(original: data, displayed: data, metadata: metadata, legacyFilename: file.lastPathComponent)
            }
            // Preserve legacy files. The committed legacy filename prevents duplicate imports.
        }
    }

    private func validFilename(_ filename: String) -> Bool {
        !filename.isEmpty && filename != "." && filename != ".." && !filename.contains("/")
    }

    private func prepare(_ id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".import-\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    private func commit(_ record: CaptureRecord, staging: URL) throws {
        try JSONEncoder().encode(record).write(to: staging.appendingPathComponent("record.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: root.appendingPathComponent(record.id.uuidString))
    }

    private func read(_ url: URL) throws -> CaptureRecord { try JSONDecoder().decode(CaptureRecord.self, from: Data(contentsOf: url)) }

    private func update(_ id: UUID, change: (inout CaptureRecord) -> Void) throws {
        let path = root.appendingPathComponent(id.uuidString).appendingPathComponent("record.json")
        var record = try read(path)
        change(&record)
        try JSONEncoder().encode(record).write(to: path, options: .atomic)
    }
}
