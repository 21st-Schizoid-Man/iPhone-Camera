import Photos
import SwiftUI

@MainActor
final class CaptureLibrary: ObservableObject {
    @Published private(set) var records: [CaptureRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isExporting = false
    @Published var errorMessage: String?
    @Published var exportNotice: String?
    @Published private(set) var needsPhotoSettings = false
    let repository: CaptureRepository
    private var decorationWrites: [UUID: Task<Void, Never>] = [:]

    init(repository: CaptureRepository = CaptureRepository()) { self.repository = repository }

    var undeveloped: [CaptureRecord] { records.filter { $0.kind == .photo && !$0.isDeveloped } }

    func fileURL(_ record: CaptureRecord, original: Bool = false) -> URL {
        repository.url(for: record, filename: original ? record.originalFilename : record.displayFilename)
    }

    func thumbnailURL(_ record: CaptureRecord) -> URL? {
        record.thumbnailFilename.map { repository.url(for: record, filename: $0) }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await repository.load()
            records = result.records
            if result.unreadable > 0 { errorMessage = "有 \(result.unreadable) 个作品暂时无法读取，原文件仍然保留。" }
        } catch { errorMessage = "无法打开 App 相册：\(error.localizedDescription)" }
    }

    func migrateLegacy() async {
        do { try await repository.migrateLegacyFiles(RecoveryStore()) }
        catch { errorMessage = "旧版待保存作品导入未完成，旧文件仍然保留：\(error.localizedDescription)" }
        await reload()
    }

    func addPhoto(original: Data, displayed: Data, metadata: CaptureMetadata) async throws {
        let record = try await repository.importPhoto(original: original, displayed: displayed, metadata: metadata)
        records.insert(record, at: 0)
    }

    func addVideo(_ url: URL, metadata: CaptureMetadata) async throws {
        let record = try await repository.importVideo(from: url, metadata: metadata)
        records.insert(record, at: 0)
        // Source removal happens only after the durable library commit succeeds.
        try? FileManager.default.removeItem(at: url)
    }

    func develop(_ ids: [UUID]) async throws {
        do {
            try await repository.markDeveloped(ids)
            let selected = Set(ids)
            for index in records.indices where selected.contains(records[index].id) { records[index].isDeveloped = true }
        } catch {
            await reload()
            throw error
        }
    }

    func editDecoration(_ decoration: PhotoDecoration, id: UUID) {
        if let index = records.firstIndex(where: { $0.id == id }) { records[index].decoration = decoration }
        let previous = decorationWrites[id]
        let repository = repository
        decorationWrites[id] = Task { [weak self] in
            // Finish earlier edits first, including when the editor has already closed.
            await previous?.value
            do { try await repository.setDecoration(decoration, id: id) }
            catch { self?.errorMessage = "装饰设置暂未保存，照片原片仍然保留。请重新选择后重试。" }
        }
    }

    func export(_ record: CaptureRecord, decoration: PhotoDecoration, original: Bool = false) async {
        guard !isExporting else { return }
        isExporting = true
        needsPhotoSettings = false
        exportNotice = nil
        defer { isExporting = false }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            needsPhotoSettings = true
            errorMessage = "没有添加照片权限。作品仍在 App 相册，你可以在系统设置中授权后重试。"
            return
        }
        do {
            if record.kind == .photo {
                let url = fileURL(record, original: original)
                let metadata = record.metadata
                let output = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: url)
                    return original ? data : try PhotoDecorationRenderer.render(data, metadata: metadata, decoration: decoration)
                }.value
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = record.metadata.capturedAt
                    request.addResource(with: .photo, data: output, options: nil)
                }
            } else {
                let url = fileURL(record)
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = record.metadata.capturedAt
                    request.addResource(with: .video, fileURL: url, options: nil)
                }
            }
            // A bookkeeping failure cannot undo a successful system Photos export.
            exportNotice = "已保存到系统相册，App 内原片仍保留。"
            do {
                try await repository.markExported(record.id)
                if let index = records.firstIndex(where: { $0.id == record.id }) { records[index].lastExportedAt = Date() }
            } catch { exportNotice = "已保存到系统相册；App 内导出记录暂未更新。" }
        } catch {
            errorMessage = "导出失败，App 内原片未改变：\(error.localizedDescription)"
        }
    }
}
