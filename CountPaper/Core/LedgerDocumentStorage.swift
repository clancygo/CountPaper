import Foundation

struct LedgerFileSignature: Equatable {
    let modificationDate: Date
    let size: Int
}

enum ExternalChangeAction: Equatable { case none, reload, conflict }

func externalChangeAction(last: LedgerFileSignature?, current: LedgerFileSignature?, hasUnsavedChanges: Bool) -> ExternalChangeAction {
    guard let last, let current, last != current else { return .none }
    return hasUnsavedChanges ? .conflict : .reload
}

/// Foundation-only persistence for a CountPaper document.
///
/// The AppKit layer supplies presentation, parsing and conflict UI. This type
/// deliberately owns only the durable file operation so a future iOS target
/// can use exactly the same save and recovery behaviour.
enum LedgerDocumentStorage {
    struct SaveResult: Equatable {
        let backupURL: URL?
    }

    enum StorageError: LocalizedError {
        case invalidUTF8AfterWrite

        var errorDescription: String? {
            switch self {
            case .invalidUTF8AfterWrite:
                return "The temporary ledger file could not be read as UTF-8."
            }
        }
    }

    /// Writes through a sibling temporary file and replaces the destination
    /// only after the temporary content has been read back successfully. A
    /// copy of the previous document is kept before replacement, so neither a
    /// failed write nor an accidental edit can silently destroy the last
    /// recoverable version.
    @discardableResult
    static func save(_ text: String, to url: URL, backupLimit: Int = 20, recoveryDirectory: URL? = nil) throws -> SaveResult {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).countpaper-tmp-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporaryURL) }

        let data = Data(text.utf8)
        try data.write(to: temporaryURL, options: .withoutOverwriting)
        try FileHandle(forWritingTo: temporaryURL).synchronize()

        guard let verifiedText = try? String(contentsOf: temporaryURL, encoding: .utf8), verifiedText == text else {
            throw StorageError.invalidUTF8AfterWrite
        }

        let backupURL = try backupCurrentVersion(of: url, limit: backupLimit, recoveryDirectory: recoveryDirectory)
        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: temporaryURL, backupItemName: nil, options: .usingNewMetadataOnly)
        } else {
            try manager.moveItem(at: temporaryURL, to: url)
        }
        return SaveResult(backupURL: backupURL)
    }

    static func backupDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("CountPaper/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func fileSignature(for url: URL) -> LedgerFileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber else { return nil }
        return LedgerFileSignature(modificationDate: date, size: size.intValue)
    }

    /// Returns recoverable revisions for one ledger, newest first. New
    /// revisions live in a document-specific directory. Flat revisions made
    /// by older CountPaper versions are included for recovery compatibility,
    /// but never participate in pruning.
    static func backups(for documentURL: URL, recoveryDirectory: URL? = nil) throws -> [URL] {
        let root = try recoveryRoot(recoveryDirectory)
        let directory = try documentBackupDirectory(for: documentURL, root: root)
        let suffix = "-\(documentURL.lastPathComponent)"
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let manager = FileManager.default
        let documentBackups = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        // Before document directories were introduced, every ledger shared a
        // flat recovery folder. Keep those files visible so upgrading never
        // hides a user's existing recovery history.
        let legacyBackups = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            .filter { $0.lastPathComponent.hasSuffix(suffix) }
        return (documentBackups + legacyBackups)
            .sorted {
                let left = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                return left > right
            }
    }

    private static func backupCurrentVersion(of url: URL, limit: Int, recoveryDirectory: URL?) throws -> URL? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return nil }
        let root = try recoveryRoot(recoveryDirectory)
        let directory = try documentBackupDirectory(for: url, root: root)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = directory.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)")
        try manager.copyItem(at: url, to: backupURL)
        try pruneBackups(in: directory, keeping: max(1, limit))
        return backupURL
    }

    private static func recoveryRoot(_ recoveryDirectory: URL?) throws -> URL {
        if let recoveryDirectory {
            try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            return recoveryDirectory
        }
        return try backupDirectory()
    }

    /// A path-derived identifier prevents two documents with the same name
    /// from sharing a retention budget while avoiding raw absolute paths in
    /// Application Support. A move deliberately begins a new recovery series;
    /// the prior files remain untouched in their old directory.
    private static func documentBackupDirectory(for documentURL: URL, root: URL) throws -> URL {
        let path = documentURL.standardizedFileURL.path
        var hash: UInt64 = 14_695_981_039_346_656_037 // FNV-1a offset basis
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let hex = String(hash, radix: 16)
        let identifier = String(repeating: "0", count: max(0, 16 - hex.count)) + hex
        let directory = root.appendingPathComponent("ledger-\(identifier)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// `directory` is always the current document's recovery directory, never
    /// the shared Backups root. A busy ledger therefore cannot evict another
    /// ledger's revisions.
    private static func pruneBackups(in directory: URL, keeping limit: Int) throws {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let backups = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            .sorted {
                let left = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                return left > right
            }
        for backup in backups.dropFirst(limit) {
            try? manager.removeItem(at: backup)
        }
    }
}
