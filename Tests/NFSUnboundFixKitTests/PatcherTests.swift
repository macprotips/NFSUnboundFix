import Foundation
import NFSUnboundFixKit
import XCTest

final class PatcherTests: XCTestCase {
    private var root: URL!
    private var gameFolder: URL!
    private var backups: URL!

    // The stand-in fix makes two edits; the stand-in older fix makes one edit somewhere else.
    private let edits = [
        ByteEdit(offset: 1000, original: [0x44, 0x38, 0xAB, 0xC0, 0x01, 0x00, 0x00],
                 replacement: [0x80, 0xA3, 0xC0, 0x01, 0x00, 0x00, 0x00]),
        ByteEdit(offset: 3000, original: [0x00, 0x00, 0x00, 0x00], replacement: [0x48, 0x83, 0xBD, 0x04]),
    ]
    private let olderEdit = ByteEdit(offset: 2000, original: [0x10, 0x20, 0x30, 0x40, 0x50],
                                     replacement: [0x90, 0x90, 0x90, 0x90, 0x90])
    private var originalData: Data!
    private var patchedData: Data!
    private var olderFixData: Data!
    private var spec: PatchSpec!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        gameFolder = root.appendingPathComponent("Bottle/drive_c/Steam/steamapps/common/Excalibur")
        backups = root.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)

        var bytes = (0 ..< 4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        for edit in edits + [olderEdit] {
            bytes.replaceSubrange(edit.offset ..< edit.offset + edit.original.count, with: edit.original)
        }
        originalData = Data(bytes)
        patchedData = Self.applying(edits, to: originalData)
        olderFixData = Self.applying([olderEdit], to: originalData)
        spec = makeSpec(edits: edits)
    }

    private static func applying(_ edits: [ByteEdit], to data: Data) -> Data {
        var result = data
        for edit in edits {
            result.replaceSubrange(edit.offset ..< edit.offset + edit.replacement.count, with: edit.replacement)
        }
        return result
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSpec(edits: [ByteEdit]) -> PatchSpec {
        PatchSpec(fileName: PatchSpec.unboundBlackScreen.fileName,
                  originalSHA256: sha256Hex(of: originalData), patchedSHA256: sha256Hex(of: patchedData),
                  edits: edits,
                  olderFixes: [OlderFix(name: "the original fix", sha256: sha256Hex(of: olderFixData),
                                        edits: [olderEdit])])
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
        XCTAssertEqual(real.edits.count, 6)
        XCTAssertEqual(real.originalSHA256.count, 64)
        XCTAssertEqual(real.patchedSHA256.count, 64)
        XCTAssertNotEqual(real.originalSHA256, real.patchedSHA256)
        // Edits are in order, don't overlap, and each actually changes something.
        for (a, b) in zip(real.edits, real.edits.dropFirst()) {
            XCTAssertLessThanOrEqual(a.offset + a.original.count, b.offset)
        }
        for edit in real.edits { XCTAssertNotEqual(edit.original, edit.replacement) }
        // The original fix is recognised, and touches bytes the new fix doesn't.
        XCTAssertEqual(real.olderFixes.count, 1)
        let older = real.olderFixes[0]
        XCTAssertEqual(older.sha256, "9dc33b2edebca402c48c53f32cce474aafd5d640e5754275484deaced66134aa")
        XCTAssertEqual(older.edits.map(\.offset), [0x1AB423])
        for edit in real.edits {
            XCTAssertFalse((edit.offset ..< edit.offset + edit.original.count).overlaps(0x1AB423 ..< 0x1AB42A))
        }
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
        spec = makeSpec(edits: [ByteEdit(offset: 1000, original: [1, 2, 3, 4, 5, 6, 7],
                                         replacement: edits[0].replacement), edits[1]])
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

    func testBackupsFromOlderVersionsOfTheAppAreFoundButNotSearched() throws {
        let older = root.appendingPathComponent("Older Backups")
        try writeDLL(originalData, in: older.appendingPathComponent("2026-10-10 at 12.00.00"))
        try writeDLL(patchedData)
        let patcher = Patcher(spec: spec, backupDirectory: backups, olderBackupDirectories: [older])
        XCTAssertNotNil(patcher.existingBackup())
        let found = try patcher.findTargets(in: root)
        XCTAssertEqual(found.count, 1, "older backups aren't treated as game files: \(found.map(\.path))")
    }

    func testOlderFixIsRecognised() throws {
        let dll = try writeDLL(olderFixData)
        XCTAssertEqual(try patcher.state(of: dll), .olderFix(name: "the original fix"))
    }

    func testUpdatingFromOlderFix() throws {
        let dll = try writeDLL(olderFixData)
        let report = try patcher.apply(to: dll)
        XCTAssertTrue(report.replacedOlderFix)
        XCTAssertEqual(try Data(contentsOf: dll), patchedData)
        XCTAssertEqual(try patcher.state(of: dll), .patched)
        // The backup is the untouched original, not the older fix.
        XCTAssertEqual(try Data(contentsOf: report.backup), originalData)
    }

    func testUndoingOlderFix() throws {
        let dll = try writeDLL(olderFixData)
        try patcher.restore(dll)
        XCTAssertEqual(try Data(contentsOf: dll), originalData)
    }

    func testOlderFixWithUnexpectedBytesIsRefused() throws {
        // Right fingerprint can't have the wrong bytes, so simulate a spec whose older-fix description is wrong.
        spec = PatchSpec(fileName: spec.fileName, originalSHA256: spec.originalSHA256, patchedSHA256: spec.patchedSHA256,
                         edits: edits,
                         olderFixes: [OlderFix(name: "x", sha256: sha256Hex(of: olderFixData),
                                               edits: [ByteEdit(offset: 2000, original: olderEdit.original,
                                                                replacement: [1, 1, 1, 1, 1])])])
        let dll = try writeDLL(olderFixData)
        XCTAssertThrowsError(try patcher.apply(to: dll)) { XCTAssertEqual($0 as? PatchError, .unexpectedBytes) }
        XCTAssertThrowsError(try patcher.restore(dll)) { XCTAssertEqual($0 as? PatchError, .noBackup) }
        XCTAssertEqual(try Data(contentsOf: dll), olderFixData)
    }

    func testUndoOnUnpatchedFileIsRefused() throws {
        let dll = try writeDLL(originalData)
        XCTAssertThrowsError(try patcher.restore(dll)) { XCTAssertEqual($0 as? PatchError, .notPatched) }
    }

    func testUndoWorksWithoutBackup() throws {
        let dll = try writeDLL(patchedData)
        XCTAssertNil(patcher.existingBackup())
        try patcher.restore(dll)
        XCTAssertEqual(try Data(contentsOf: dll), originalData)
    }
}
