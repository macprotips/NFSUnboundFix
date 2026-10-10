import Foundation
import NFSUnboundFixKit
import XCTest

final class PatcherTests: XCTestCase {
    private var root: URL!
    private var gameFolder: URL!
    private var backups: URL!

    private let offset = 1000
    private let originalBytes: [UInt8] = [0x44, 0x38, 0xAB, 0xC0, 0x01, 0x00, 0x00]
    private let replacementBytes: [UInt8] = [0x80, 0xA3, 0xC0, 0x01, 0x00, 0x00, 0x00]
    private var originalData: Data!
    private var patchedData: Data!
    private var spec: PatchSpec!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        gameFolder = root.appendingPathComponent("Bottle/drive_c/Steam/steamapps/common/Excalibur")
        backups = root.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)

        var bytes = (0 ..< 4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        bytes.replaceSubrange(offset ..< offset + 7, with: originalBytes)
        originalData = Data(bytes)
        patchedData = originalData
        patchedData.replaceSubrange(offset ..< offset + 7, with: replacementBytes)
        spec = makeSpec(originalBytes: originalBytes)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSpec(originalBytes: [UInt8]) -> PatchSpec {
        PatchSpec(fileName: PatchSpec.unboundBlackScreen.fileName, offset: offset,
                  originalBytes: originalBytes, replacementBytes: replacementBytes,
                  originalSHA256: sha256Hex(of: originalData), patchedSHA256: sha256Hex(of: patchedData))
    }

    private var patcher: Patcher { Patcher(spec: spec, backupDirectory: backups) }

    @discardableResult
    private func writeDLL(_ data: Data, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? gameFolder).appendingPathComponent(spec.fileName)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func testRealSpecIsConsistent() {
        let real = PatchSpec.unboundBlackScreen
        XCTAssertEqual(real.offset, 0x1AB423)
        XCTAssertEqual(real.originalBytes.count, 7)
        XCTAssertEqual(real.replacementBytes.count, 7)
        XCTAssertEqual(real.originalSHA256.count, 64)
        XCTAssertEqual(real.patchedSHA256.count, 64)
        XCTAssertNotEqual(real.originalSHA256, real.patchedSHA256)
    }

    func testFindsFileFromBottleOrGameFolderOrFileItself() throws {
        let dll = try writeDLL(originalData)
        let bottle = root.appendingPathComponent("Bottle")
        XCTAssertEqual(try patcher.findTarget(in: bottle).resolvingSymlinksInPath(), dll.resolvingSymlinksInPath())
        XCTAssertEqual(try patcher.findTarget(in: gameFolder).resolvingSymlinksInPath(), dll.resolvingSymlinksInPath())
        XCTAssertEqual(try patcher.findTarget(in: dll).resolvingSymlinksInPath(), dll.resolvingSymlinksInPath())
    }

    func testNotFound() {
        XCTAssertThrowsError(try patcher.findTarget(in: gameFolder)) {
            XCTAssertEqual($0 as? PatchError, .notFound(fileName: spec.fileName))
        }
    }

    func testMultipleCopiesIsAnError() throws {
        try writeDLL(originalData, in: root.appendingPathComponent("Bottle/Copy A"))
        try writeDLL(originalData, in: root.appendingPathComponent("Bottle/Copy B"))
        XCTAssertThrowsError(try patcher.findTarget(in: root.appendingPathComponent("Bottle"))) {
            guard case .multipleFound(let urls) = $0 as? PatchError else { return XCTFail("\($0)") }
            XCTAssertEqual(urls.count, 2)
        }
    }

    func testSteamCopyWinsOverLooseCopy() throws {
        let dll = try writeDLL(originalData)
        try writeDLL(originalData, in: root.appendingPathComponent("Bottle/My manual backup"))
        let found = try patcher.findTarget(in: root.appendingPathComponent("Bottle"))
        XCTAssertEqual(found.resolvingSymlinksInPath(), dll.resolvingSymlinksInPath())
    }

    func testDroppingAnotherFileSearchesItsFolder() throws {
        let dll = try writeDLL(originalData)
        let exe = gameFolder.appendingPathComponent("NeedForSpeedUnbound.exe")
        try Data([0]).write(to: exe)
        XCTAssertEqual(try patcher.findTarget(in: exe).resolvingSymlinksInPath(), dll.resolvingSymlinksInPath())
    }

    func testSearchStopsWhenCancelled() async throws {
        try writeDLL(originalData)
        let patcher = self.patcher
        let root = self.root!
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try patcher.findTargets(in: root)
        }
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
    }

    func testFolderNamedLikeBackupsIsStillSearched() throws {
        try writeDLL(originalData, in: root.appendingPathComponent("Backups2/Need for Speed Unbound"))
        XCTAssertEqual(try patcher.findTargets(in: root).count, 1)
    }

    func testBackupsMadeInTheSameSecondDontCollide() throws {
        let dll = try writeDLL(originalData)
        try patcher.apply(to: dll)
        // Corrupt the backup so the next run has to make a new one straight away.
        let first = try XCTUnwrap(patcher.existingBackup())
        try Data([1, 2, 3]).write(to: first)
        try writeDLL(originalData)
        let report = try patcher.apply(to: dll)
        XCTAssertFalse(report.reusedBackup)
        XCTAssertEqual(try Data(contentsOf: report.backup), originalData)
    }

    func testUnreadableFileGivesFriendlyError() throws {
        let missing = gameFolder.appendingPathComponent(spec.fileName)
        XCTAssertThrowsError(try patcher.state(of: missing)) {
            XCTAssertEqual($0 as? PatchError, .readFailed(missing))
        }
    }

    func testSearchIgnoresBackupsAndSymlinks() throws {
        try writeDLL(originalData)
        try writeDLL(originalData, in: backups.appendingPathComponent("old"))
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try writeDLL(originalData, in: elsewhere)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: elsewhere)
        XCTAssertEqual(try patcher.findTargets(in: root).count, 1)
    }

    func testApplyThenUndo() throws {
        let dll = try writeDLL(originalData)
        XCTAssertEqual(try patcher.state(of: dll), .original)

        let report = try patcher.apply(to: dll)
        XCTAssertFalse(report.reusedBackup)
        let backup = report.backup
        XCTAssertEqual(try Data(contentsOf: dll), patchedData)
        XCTAssertEqual(try patcher.state(of: dll), .patched)
        XCTAssertEqual(try Data(contentsOf: backup), originalData)
        XCTAssertNotNil(patcher.existingBackup())
        XCTAssertEqual(try patcher.findTargets(in: gameFolder).count, 1, "no temp files left behind")

        try patcher.restore(dll)
        XCTAssertEqual(try Data(contentsOf: dll), originalData)
        XCTAssertEqual(try patcher.state(of: dll), .original)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: gameFolder.path)
        XCTAssertEqual(leftovers, [spec.fileName])
    }

    func testApplyingTwiceIsRefused() throws {
        let dll = try writeDLL(originalData)
        try patcher.apply(to: dll)
        XCTAssertThrowsError(try patcher.apply(to: dll)) { XCTAssertEqual($0 as? PatchError, .alreadyPatched) }
        XCTAssertEqual(try Data(contentsOf: dll), patchedData)
    }

    func testReapplyAfterSteamRestoresOriginalReusesBackup() throws {
        let dll = try writeDLL(originalData)
        let first = try patcher.apply(to: dll)
        try writeDLL(originalData)
        let second = try patcher.apply(to: dll)
        XCTAssertTrue(second.reusedBackup)
        XCTAssertEqual(first.backup.resolvingSymlinksInPath().path, second.backup.resolvingSymlinksInPath().path)
    }

    func testUnsupportedVersionIsNeverTouched() throws {
        var other = originalData!
        other[0] ^= 0xFF
        let dll = try writeDLL(other)
        guard case .unsupported = try patcher.state(of: dll) else { return XCTFail() }
        XCTAssertThrowsError(try patcher.apply(to: dll)) {
            guard case .unsupportedVersion = $0 as? PatchError else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try patcher.restore(dll))
        XCTAssertEqual(try Data(contentsOf: dll), other)
        XCTAssertNil(patcher.existingBackup())
    }

    func testUnexpectedBytesAreRefused() throws {
        spec = makeSpec(originalBytes: [1, 2, 3, 4, 5, 6, 7])
        let dll = try writeDLL(originalData)
        XCTAssertThrowsError(try patcher.apply(to: dll)) { XCTAssertEqual($0 as? PatchError, .unexpectedBytes) }
        XCTAssertEqual(try Data(contentsOf: dll), originalData)
    }

    func testEveryErrorHasAMessage() {
        let url = URL(fileURLWithPath: "/tmp/x.dll")
        let errors: [PatchError] = [
            .notFound(fileName: "x"), .multipleFound([url]), .unsupportedVersion(sha256: "abc"), .alreadyPatched,
            .notPatched, .unexpectedBytes, .patchHashMismatch, .readFailed(url), .notWritable(url),
            .writeFailed(url), .backupFailed, .noBackup, .verifyFailedRestored, .verifyFailedNotRestored(backup: url),
        ]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error)")
        }
        XCTAssertEqual(PatchError.unsupportedVersion(sha256: "abc").title, "Unsupported game version")
    }

    func testUndoFindsBackupFromOlderVersionOfTheApp() throws {
        let older = root.appendingPathComponent("Older Backups")
        try writeDLL(originalData, in: older.appendingPathComponent("2026-10-10 at 12.00.00"))
        let dll = try writeDLL(patchedData)
        let patcher = Patcher(spec: spec, backupDirectory: backups, olderBackupDirectories: [older])
        try patcher.restore(dll)
        XCTAssertEqual(try Data(contentsOf: dll), originalData)
        let found = try patcher.findTargets(in: root)
        XCTAssertEqual(found.count, 1, "older backups aren't treated as game files: \(found.map(\.path))")
    }

    func testUndoOnUnpatchedFileIsRefused() throws {
        let dll = try writeDLL(originalData)
        XCTAssertThrowsError(try patcher.restore(dll)) { XCTAssertEqual($0 as? PatchError, .notPatched) }
    }

    func testUndoWithoutBackupIsRefused() throws {
        let dll = try writeDLL(patchedData)
        XCTAssertThrowsError(try patcher.restore(dll)) { XCTAssertEqual($0 as? PatchError, .noBackup) }
        XCTAssertEqual(try Data(contentsOf: dll), patchedData)
    }
}
