import XCTest
@testable import CountPaperCore

final class StorageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CountPaperStorage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testSaveCreatesRecoverableVersion() throws {
        let ledger = directory.appendingPathComponent("Ledger.countpaper")
        let backups = directory.appendingPathComponent("Backups")
        XCTAssertNil(try LedgerDocumentStorage.save("first", to: ledger, recoveryDirectory: backups).backupURL)
        let result = try LedgerDocumentStorage.save("second", to: ledger, recoveryDirectory: backups)
        XCTAssertEqual(try String(contentsOf: ledger, encoding: .utf8), "second")
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(result.backupURL), encoding: .utf8), "first")
        XCTAssertEqual(try LedgerDocumentStorage.backups(for: ledger, recoveryDirectory: backups).count, 1)
    }

    func testSignatureTreatsEqualHashMetadataChangeAsNoChange() {
        let first = LedgerFileSignature(modificationDate: Date(timeIntervalSince1970: 1), size: 10, contentHash: "same")
        let metadataChanged = LedgerFileSignature(modificationDate: Date(timeIntervalSince1970: 2), size: 10, contentHash: "same")
        let contentChanged = LedgerFileSignature(modificationDate: Date(timeIntervalSince1970: 2), size: 10, contentHash: "different")
        XCTAssertEqual(externalChangeAction(last: first, current: metadataChanged, hasUnsavedChanges: false), .none)
        XCTAssertEqual(externalChangeAction(last: first, current: contentChanged, hasUnsavedChanges: true), .conflict)
        XCTAssertEqual(externalChangeAction(last: first, current: nil, hasUnsavedChanges: false), .deleted)
    }
}
