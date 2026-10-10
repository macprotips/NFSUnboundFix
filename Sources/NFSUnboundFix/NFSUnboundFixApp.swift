import AppKit
import SwiftUI

@main
struct NFSUnboundFixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = FixModel()

    var body: some Scene {
        Window("NFS Unbound Fix", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o")
                    .disabled(model.isBusy)
                Divider()
                Button("Show Backups Folder") { model.showBackupsFolder() }
            }
            CommandGroup(replacing: .help) {
                Button("NFS Unbound Fix Help") { model.showingHelp = true }
                    .keyboardShortcut("?")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wait a turn so the main window exists, then show the warning attached to it.
        DispatchQueue.main.async { Self.showRiskWarning() }
    }

    /// Shown on every launch. The window can't be used until the warning is accepted.
    static func showRiskWarning() {
        let alert = makeRiskAlert()
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
            alert.beginSheetModal(for: window) { response in
                if response != .alertFirstButtonReturn { NSApp.terminate(nil) }
            }
        } else if alert.runModal() != .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    static func makeRiskAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Use at your own risk"
        alert.informativeText = """
            NFS Unbound Fix changes a file in your copy of Need for Speed Unbound. It isn't made or \
            approved by Electronic Arts, and it's unclear whether EA allows fixes like this.

            Changing game files may go against EA's user agreement, and playing online with a changed \
            game could put your EA account at risk.

            Your original file is always backed up first, and you can undo the fix at any time.
            """
        alert.addButton(withTitle: "I Understand")
        alert.addButton(withTitle: "Quit")
        return alert
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
