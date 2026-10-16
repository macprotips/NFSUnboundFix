import AppKit
import Foundation
import NFSUnboundFixKit

@MainActor
final class FixModel: ObservableObject {
    enum Phase: Equatable {
        case waiting
        case searching
        case working(String)
        case ready(file: URL)
        case alreadyFixed(file: URL)
        case olderFixFound(file: URL)
        case fixed(file: URL, report: ApplyReport)
        case undone(file: URL)
        case problem(title: String, message: String, detail: String?)
    }

    @Published var phase: Phase = .waiting
    @Published var showingHelp = false
    /// The game file found last time, so it can be checked again after a Steam update.
    @Published var recentFile: URL?

    let patcher: Patcher
    private var task: Task<Void, Never>?
    private var generation = 0
    private static let recentFileKey = "RecentGameFile"

    init(patcher: Patcher = Patcher(spec: .unboundBlackScreen, backupDirectory: Patcher.defaultBackupDirectory,
                                    olderBackupDirectories: Patcher.olderDefaultBackupDirectories)) {
        self.patcher = patcher
        if let path = UserDefaults.standard.string(forKey: Self.recentFileKey),
           FileManager.default.fileExists(atPath: path) {
            recentFile = URL(fileURLWithPath: path)
        }
    }

    var isBusy: Bool {
        switch phase {
        case .searching, .working: return true
        default: return false
        }
    }

    // MARK: Actions

    func load(_ url: URL) {
        guard url.isFileURL, !isBusy else { return }
        phase = .searching
        let patcher = patcher
        run(failureTitle: "Couldn't check the game") {
            let file = try patcher.findTarget(in: url)
            switch try patcher.state(of: file) {
            case .original:
                return .ready(file: file)
            case .patched:
                return .alreadyFixed(file: file)
            case .olderFix:
                return .olderFixFound(file: file)
            case .unsupported(let hash):
                throw PatchError.unsupportedVersion(sha256: hash)
            }
        }
    }

    func applyFix(to file: URL) {
        guard !isBusy else { return }
        phase = .working("Backing up and applying the fix…")
        let patcher = patcher
        run(failureTitle: "The fix wasn't applied") {
            guard !isUnboundRunning() else { throw GameRunningError() }
            return .fixed(file: file, report: try patcher.apply(to: file))
        }
    }

    func undoFix(on file: URL) {
        guard !isBusy else { return }
        phase = .working("Putting the original file back…")
        let patcher = patcher
        run(failureTitle: "Couldn't undo the fix") {
            guard !isUnboundRunning() else { throw GameRunningError() }
            try patcher.restore(file)
            return .undone(file: file)
        }
    }

    /// Stops a search. Applying and undoing are quick and all-or-nothing, so they aren't cancellable.
    func cancelSearch() {
        guard phase == .searching else { return }
        task?.cancel()
        task = nil
        generation += 1
        phase = .waiting
    }

    func startOver() {
        guard !isBusy else { return }
        phase = .waiting
    }

    func chooseFolder() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose Unbound's game folder, named Excalibur, or your whole CrossOver bottle."
        panel.prompt = "Choose"
        let bottles = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CrossOver/Bottles")
        if FileManager.default.fileExists(atPath: bottles.path) {
            panel.directoryURL = bottles
        }
        if panel.runModal() == .OK, let url = panel.url {
            load(url)
        }
    }

    func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showBackupsFolder() {
        let folder = patcher.backupDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Running work

    /// Runs file work off the main thread, then shows the outcome. Only the latest
    /// piece of work may update the window.
    private func run(failureTitle: String, _ work: @escaping @Sendable () throws -> Phase) {
        task?.cancel()
        generation += 1
        let generation = generation
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = Result { try work() }
            await self?.finish(outcome, generation: generation, failureTitle: failureTitle)
        }
    }

    private func finish(_ outcome: Result<Phase, Error>, generation: Int, failureTitle: String) {
        guard generation == self.generation else { return }
        task = nil
        switch outcome {
        case .success(let phase):
            self.phase = phase
            remember(phase)
        case .failure(is CancellationError):
            phase = .waiting
        case .failure(let error):
            let patchError = error as? PatchError
            phase = .problem(title: patchError?.title ?? failureTitle, message: error.localizedDescription,
                             detail: patchError?.detail)
        }
    }

    private func remember(_ phase: Phase) {
        let file: URL
        switch phase {
        case .ready(let f), .alreadyFixed(let f), .olderFixFound(let f), .fixed(let f, _), .undone(let f): file = f
        default: return
        }
        recentFile = file
        UserDefaults.standard.set(file.path, forKey: Self.recentFileKey)
    }
}

private struct GameRunningError: LocalizedError {
    var errorDescription: String? {
        "Need for Speed Unbound is still running. Quit the game, then try again. Nothing was changed."
    }
}

/// `~/Library/…` instead of `/Users/name/Library/…`.
func abbreviatedPath(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
}
