import XCTest
import UIKit
@testable import MomentCamera

final class CaptureRepositoryTests: XCTestCase {
    private let metadata = CaptureMetadata(capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                           timeZoneIdentifier: "Asia/Shanghai", deviceModel: "iPhone 15 Pro", city: "杭州")

    func testPhotoKeepsOriginalAndStyledImageAcrossRestart() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CaptureRepository(root: root)
        let original = try photo(.red)
        let styled = try photo(.blue)
        let saved = try await repository.importPhoto(original: original, displayed: styled, metadata: metadata)
        let reloaded = try await CaptureRepository(root: root).load()
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.unreadable, 0)
        let record = try XCTUnwrap(reloaded.records.first)
        XCTAssertEqual(record.id, saved.id)
        XCTAssertEqual(record.metadata, metadata)
        XCTAssertFalse(record.isDeveloped)
        XCTAssertNotEqual(record.originalFilename, record.displayFilename)
        XCTAssertEqual(try Data(contentsOf: repository.url(for: record, filename: record.originalFilename)), original)
        XCTAssertEqual(try Data(contentsOf: repository.url(for: record, filename: record.displayFilename)), styled)
    }

    func testDevelopmentAndDecorationEditsPreserveEachOther() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CaptureRepository(root: root)
        let data = try photo(.red)
        let record = try await repository.importPhoto(original: data, displayed: data, metadata: metadata)
        var decoration = PhotoDecoration()
        decoration.frame = .instant
        decoration.watermarkEnabled = true
        decoration.position = .left
        decoration.showCity = true
        try await repository.setDecoration(decoration, id: record.id)
        try await repository.markDeveloped([record.id])
        try await repository.markExported(record.id)
        let result = try await CaptureRepository(root: root).load()
        let reloaded = try XCTUnwrap(result.records.first)
        XCTAssertTrue(reloaded.isDeveloped)
        XCTAssertEqual(reloaded.decoration, decoration)
        XCTAssertNotNil(reloaded.lastExportedAt)
        XCTAssertEqual(try Data(contentsOf: repository.url(for: reloaded, filename: reloaded.originalFilename)), data)
    }

    func testCorruptRecordDoesNotEraseItsPhotoOrHideOtherCaptures() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CaptureRepository(root: root)
        let data = try photo(.green)
        let first = try await repository.importPhoto(original: data, displayed: data, metadata: metadata)
        _ = try await repository.importPhoto(original: data, displayed: data, metadata: metadata)
        let index = root.appendingPathComponent(first.id.uuidString).appendingPathComponent("record.json")
        try Data("broken json".utf8).write(to: index)
        let reloaded = try await repository.load()
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.unreadable, 1)
        XCTAssertEqual(try Data(contentsOf: repository.url(for: first, filename: first.originalFilename)), data)
    }

    func testFailedVideoImportPreservesTheSource() async throws {
        let root = temporaryRoot()
        let source = temporaryRoot().appendingPathExtension("mov")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: source)
        // A file at the library path makes creation fail before any source can be removed.
        try Data([0]).write(to: root)
        do {
            _ = try await CaptureRepository(root: root).importVideo(from: source, metadata: metadata)
            XCTFail("Import should fail when the destination is not a directory")
        } catch {
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
    }

    func testLegacyRecoveryImportIsRepeatableAndKeepsTheLegacyOriginal() async throws {
        let root = temporaryRoot()
        let legacyRoot = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: legacyRoot)
        }
        let store = RecoveryStore(directory: legacyRoot)
        let data = try photo(.yellow)
        let source = try store.photo(data)
        let repository = CaptureRepository(root: root)
        try await repository.migrateLegacyFiles(store)
        try await repository.migrateLegacyFiles(store)
        let result = try await repository.load()
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(try Data(contentsOf: source), data)
        XCTAssertNil(result.records.first?.metadata.capturedAt, "Migration must not invent a capture date")
    }

    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    private func photo(_ color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 1))
    }
}
