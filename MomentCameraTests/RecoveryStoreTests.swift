import XCTest
@testable import MomentCamera

final class RecoveryStoreTests: XCTestCase {
    func testPhotoSurvivesStoreRecreationAndCanBeRemovedAfterSaving() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecoveryStore(directory: directory)
        let original = Data([1, 2, 3, 4])
        let url = try store.photo(original)
        let reopened = RecoveryStore(directory: directory)
        XCTAssertEqual(reopened.items(), [url])
        XCTAssertEqual(try Data(contentsOf: url), original)
        reopened.remove(url)
        XCTAssertTrue(reopened.items().isEmpty)
    }

    func testVideoMovesOutOfTemporaryStorageWithoutChangingItsBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: source)
        }
        let original = Data([5, 6, 7, 8])
        try original.write(to: source)
        let store = RecoveryStore(directory: directory)
        let destination = try store.video(source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(store.items(), [destination])
    }
}
