import CryptoKit
import Foundation

/// One exact byte patch for one exact version of one file.
public struct PatchSpec: Sendable {
    public let fileName: String
    public let offset: Int
    public let originalBytes: [UInt8]
    public let replacementBytes: [UInt8]
    public let originalSHA256: String
    public let patchedSHA256: String

    public init(fileName: String, offset: Int, originalBytes: [UInt8], replacementBytes: [UInt8],
                originalSHA256: String, patchedSHA256: String) {
        self.fileName = fileName
        self.offset = offset
        self.originalBytes = originalBytes
        self.replacementBytes = replacementBytes
        self.originalSHA256 = originalSHA256.lowercased()
        self.patchedSHA256 = patchedSHA256.lowercased()
    }

    /// Turns off the optional graphics cache behind the startup black screen
    /// in Need for Speed Unbound, Steam build 16690907, under CrossOver with D3DMetal.
    public static let unboundBlackScreen = PatchSpec(
        fileName: "Engine.Render.Core2.PlatformPcDx12.dll",
        offset: 0x1AB423,
        originalBytes: [0x44, 0x38, 0xAB, 0xC0, 0x01, 0x00, 0x00],
        replacementBytes: [0x80, 0xA3, 0xC0, 0x01, 0x00, 0x00, 0x00],
        originalSHA256: "ee3a654be58be406eda32aeadad99ad60894403e374a2d3b847a20008cd30c62",
        patchedSHA256: "9dc33b2edebca402c48c53f32cce474aafd5d640e5754275484deaced66134aa"
    )
}

public enum FileState: Equatable, Sendable {
    /// The exact file the fix was made for. Safe to patch.
    case original
    /// The fix is already applied.
    case patched
    /// Some other version. Never touched.
    case unsupported(sha256: String)
}

/// What `apply` did, for showing the user.
public struct ApplyReport: Equatable, Sendable {
    public let backup: URL
    /// True when a verified backup from an earlier run was reused instead of making a new one.
    public let reusedBackup: Bool

    public init(backup: URL, reusedBackup: Bool) {
        self.backup = backup
        self.reusedBackup = reusedBackup
    }
}

public enum PatchError: LocalizedError, Equatable {
    case notFound(fileName: String)
    case multipleFound([URL])
    case unsupportedVersion(sha256: String)
    case alreadyPatched
    case notPatched
    case unexpectedBytes
    case patchHashMismatch
    case readFailed(URL)
    case notWritable(URL)
    case writeFailed(URL)
    case backupFailed
    case noBackup
    case verifyFailedRestored
    case verifyFailedNotRestored(backup: URL)

    public var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "Couldn't find \(name) there. Drop Unbound's game folder (named Excalibur), or your whole CrossOver bottle."
        case .multipleFound:
            return "Found more than one copy of the game file, so it's not clear which to fix. Drop just the game folder you play from."
        case .unsupportedVersion:
            return "This game file isn't Steam build 16690907, the version the fix was made for. Nothing was changed."
        case .alreadyPatched:
            return "The fix is already applied."
        case .notPatched:
            return "The fix isn't applied, so there's nothing to undo."
        case .unexpectedBytes:
            return "The bytes at the patch location aren't what was expected, so nothing was changed."
        case .patchHashMismatch:
            return "The patched file didn't come out as expected, so nothing was changed."
        case .readFailed(let url):
            return "Couldn't read \(url.lastPathComponent). Nothing was changed."
        case .notWritable(let url):
            return "macOS won't let this app change \(url.lastPathComponent). Nothing was changed."
        case .writeFailed(let url):
            return "Couldn't save \(url.lastPathComponent). Nothing was changed."
        case .backupFailed:
            return "Couldn't make a verified backup, so nothing was changed."
        case .noBackup:
            return "No verified backup of the original file was found. You can get the original back in Steam with \"Verify integrity of game files\"."
        case .verifyFailedRestored:
            return "The file didn't check out after saving, so the original was put back. Nothing has changed."
        case .verifyFailedNotRestored:
            return "The file didn't check out after saving and the original couldn't be put back automatically. Copy the backup back into the game folder, or use \"Verify integrity of game files\" in Steam."
        }
    }

    /// A short heading for the error, when there's a better one than the generic "it didn't work".
    public var title: String? {
        switch self {
        case .notFound: return "Game file not found"
        case .multipleFound: return "More than one copy found"
        case .unsupportedVersion: return "Unsupported game version"
        case .noBackup: return "No backup to restore"
        case .notWritable: return "No permission to change the file"
        default: return nil
        }
    }

    /// Extra technical detail worth showing or copying for support.
    public var detail: String? {
        switch self {
        case .multipleFound(let urls): return urls.map(\.path).joined(separator: "\n")
        case .unsupportedVersion(let hash): return "SHA-256: \(hash)"
        case .readFailed(let url), .notWritable(let url), .writeFailed(let url): return url.path
        case .verifyFailedNotRestored(let backup): return "Backup: \(backup.path)"
        default: return nil
        }
    }
}

public func sha256Hex(of data: Data) -> String {
    hex(SHA256.hash(data: data))
}

public func sha256Hex(ofFileAt url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hex(hasher.finalize())
}

private func hex(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
}

public struct Patcher: Sendable {
    public let spec: PatchSpec
    /// Where verified copies of the original file are kept. Outside the game folder,
    /// so Steam updates and verification don't touch them.
    public let backupDirectory: URL
    /// Backup folders from earlier versions of the app. Searched for a backup, never written to.
    public let olderBackupDirectories: [URL]

    public init(spec: PatchSpec, backupDirectory: URL, olderBackupDirectories: [URL] = []) {
        self.spec = spec
        self.backupDirectory = backupDirectory
        self.olderBackupDirectories = olderBackupDirectories
    }

    public static var defaultBackupDirectory: URL {
        applicationSupport.appendingPathComponent("NFS Unbound Fix/Backups", isDirectory: true)
    }

    /// Where the app kept backups when it was called "Unbound Fix".
    public static var olderDefaultBackupDirectories: [URL] {
        [applicationSupport.appendingPathComponent("Unbound Fix/Backups", isDirectory: true)]
    }

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var allBackupDirectories: [URL] { [backupDirectory] + olderBackupDirectories }

    // MARK: Finding the file

    /// Every copy of the target file in `url`, which can be the file itself, the game
    /// folder, or anything above it such as a CrossOver bottle. Dropping some other file
    /// searches the folder it's in. Throws `CancellationError` if the task is cancelled.
    public func findTargets(in url: URL) throws -> [URL] {
        var root = url.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        if (try? root.resourceValues(forKeys: Set(keys)))?.isDirectory != true {
            if isTargetName(root) { return [root] }
            root.deleteLastPathComponent()
        }

        // Backup folders are recognised by their identity on disk rather than by path,
        // because macOS can spell the same folder more than one way (/var vs /private/var).
        let backupIDs = allBackupDirectories.compactMap { Self.identity(of: $0) }
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys + [.fileResourceIdentifierKey], options: [],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [URL] = []
        for case let item as URL in enumerator {
            try Task.checkCancellation()
            let values = try? item.resourceValues(forKeys: Set(keys))
            // Bottles link back to the whole Mac (dosdevices, Desktop, Documents…). Never follow links.
            if values?.isSymbolicLink == true || item.lastPathComponent == "dosdevices" {
                enumerator.skipDescendants()
                continue
            }
            if values?.isDirectory == true, let id = Self.identity(of: item), backupIDs.contains(id) {
                enumerator.skipDescendants()
                continue
            }
            if values?.isRegularFile == true, isTargetName(item) {
                found.append(item)
            }
        }
        return found
    }

    private static func identity(of url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject
    }

    /// The single copy of the target file in `url`. When there are several, the one
    /// in a Steam library wins if it's the only one there.
    public func findTarget(in url: URL) throws -> URL {
        let found = try findTargets(in: url)
        if found.count == 1 { return found[0] }
        if found.isEmpty { throw PatchError.notFound(fileName: spec.fileName) }
        let inSteam = found.filter { file in
            file.pathComponents.contains { $0.caseInsensitiveCompare("steamapps") == .orderedSame }
        }
        if inSteam.count == 1 { return inSteam[0] }
        throw PatchError.multipleFound(found)
    }

    private func isTargetName(_ url: URL) -> Bool {
        url.lastPathComponent.caseInsensitiveCompare(spec.fileName) == .orderedSame
    }

    // MARK: Checking

    public func state(of file: URL) throws -> FileState {
        do {
            return state(forHash: try sha256Hex(ofFileAt: file))
        } catch {
            throw PatchError.readFailed(file)
        }
    }

    private func state(forHash hash: String) -> FileState {
        switch hash {
        case spec.originalSHA256: return .original
        case spec.patchedSHA256: return .patched
        default: return .unsupported(sha256: hash)
        }
    }

    /// A backup whose contents match the original file exactly.
    public func existingBackup() -> URL? {
        for directory in allBackupDirectories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey]
            ) else { continue }
            for case let item as URL in enumerator where isTargetName(item) {
                if (try? sha256Hex(ofFileAt: item)) == spec.originalSHA256 {
                    return item
                }
            }
        }
        return nil
    }

    // MARK: Applying and undoing

    /// Backs up the original, applies the patch and checks the result.
    /// On any failure the game file is left as it was.
    @discardableResult
    public func apply(to file: URL) throws -> ApplyReport {
        let original: Data
        do {
            original = try Data(contentsOf: file)
        } catch {
            throw PatchError.readFailed(file)
        }
        switch state(forHash: sha256Hex(of: original)) {
        case .original: break
        case .patched: throw PatchError.alreadyPatched
        case .unsupported(let hash): throw PatchError.unsupportedVersion(sha256: hash)
        }

        let range = spec.offset ..< spec.offset + spec.originalBytes.count
        guard spec.originalBytes.count == spec.replacementBytes.count,
              original.count >= range.upperBound,
              Array(original[range]) == spec.originalBytes
        else { throw PatchError.unexpectedBytes }

        var patched = original
        patched.replaceSubrange(range, with: spec.replacementBytes)
        guard sha256Hex(of: patched) == spec.patchedSHA256 else { throw PatchError.patchHashMismatch }

        try checkWritable(file)
        let report: ApplyReport
        if let existing = existingBackup() {
            report = ApplyReport(backup: existing, reusedBackup: true)
        } else {
            report = ApplyReport(backup: try makeBackup(of: original), reusedBackup: false)
        }

        try replaceContents(of: file, with: patched)
        if (try? sha256Hex(ofFileAt: file)) != spec.patchedSHA256 {
            do {
                try replaceContents(of: file, with: original)
            } catch {
                throw PatchError.verifyFailedNotRestored(backup: report.backup)
            }
            throw PatchError.verifyFailedRestored
        }
        return report
    }

    /// Puts the verified backup of the original back. Only works on a patched file,
    /// so it never overwrites a newer version from a game update.
    public func restore(_ file: URL) throws {
        switch try state(of: file) {
        case .patched: break
        case .original: throw PatchError.notPatched
        case .unsupported(let hash): throw PatchError.unsupportedVersion(sha256: hash)
        }
        guard let backup = existingBackup(),
              let original = try? Data(contentsOf: backup),
              sha256Hex(of: original) == spec.originalSHA256
        else { throw PatchError.noBackup }

        try checkWritable(file)
        try replaceContents(of: file, with: original)
        guard try state(of: file) == .original else {
            throw PatchError.verifyFailedNotRestored(backup: backup)
        }
    }

    private func makeBackup(of original: Data) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())
        let fm = FileManager.default

        var folder = backupDirectory.appendingPathComponent(stamp, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: folder.path) {
            folder = backupDirectory.appendingPathComponent("\(stamp) \(suffix)", isDirectory: true)
            suffix += 1
        }
        let backup = folder.appendingPathComponent(spec.fileName)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try original.write(to: backup, options: .withoutOverwriting)
        } catch {
            throw PatchError.backupFailed
        }
        guard (try? sha256Hex(ofFileAt: backup)) == spec.originalSHA256 else { throw PatchError.backupFailed }
        return backup
    }

    private func checkWritable(_ file: URL) throws {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: file.path),
              fm.isWritableFile(atPath: file.deletingLastPathComponent().path)
        else { throw PatchError.notWritable(file) }
    }

    /// Writes to a temporary file next to `file`, then swaps it in, so the game file
    /// is never left half written.
    private func replaceContents(of file: URL, with data: Data) throws {
        let temp = file.deletingLastPathComponent()
            .appendingPathComponent(".\(file.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp, options: .withoutOverwriting)
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw PatchError.writeFailed(file)
        }
    }
}

/// Best-effort check for the game's process, which runs under CrossOver/Wine.
public func isUnboundRunning() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "command="]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return false
    }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: output, as: UTF8.self).lowercased().contains("needforspeedunbound")
}
