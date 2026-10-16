import SwiftUI
import NFSUnboundFixKit

struct ContentView: View {
    @ObservedObject var model: FixModel
    @State private var isTargeted = false

    static let size = CGSize(width: 560, height: 480)
    /// One margin for every edge, so the icon, drop zone and footer all line up.
    private static let margin: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 38) // clears the window buttons in the hidden title bar
                .padding(.bottom, 18)

            // The header and footer never move; only this middle area changes between screens.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(-1)

            footer
                .padding(.vertical, 14)
        }
        .padding(.horizontal, Self.margin)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.background)
        .ignoresSafeArea()
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL), !model.isBusy else { return false }
            model.load(url)
            return true
        } isTargeted: { isTargeted = $0 && !model.isBusy }
        .sheet(isPresented: $model.showingHelp) { HelpView() }
        .animation(.easeOut(duration: 0.18), value: model.phase)
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                // App icons have about 10% clear space around the artwork; pull it back so
                // the artwork itself lines up with the drop zone's edge.
                .padding(.leading, -5.5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("NFS Unbound Fix")
                    .font(.title2.weight(.semibold))
                Text("Fixes the startup black screen in Need for Speed Unbound.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .accessibilityHidden(true)
            Text("The original file is backed up before any change.")
            Spacer(minLength: 8)
            Button("Backups") { model.showBackupsFolder() }
                .buttonStyle(.link)
                .help("Show the backups folder in Finder")
            HelpLink { model.showingHelp = true }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .controlSize(.small)
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .waiting:
            dropZone

        case .searching:
            StatusLayout {
                ProgressView().controlSize(.large)
            } title: {
                "Looking for the game file…"
            } message: {
                "This can take a moment for a whole CrossOver bottle."
            } buttons: {
                Button("Cancel") { model.cancelSearch() }
                    .keyboardShortcut(.cancelAction)
            }

        case .working(let message):
            StatusLayout {
                ProgressView().controlSize(.large)
            } title: {
                message
            } message: {
                "Don't open the game until this finishes."
            } buttons: {
                EmptyView()
            }

        case .ready(let file):
            StatusLayout {
                StatusIcon(name: "checkmark.seal.fill", color: .accentColor)
            } title: {
                "Ready to fix"
            } message: {
                "Quit the game if it's open, then click Apply Fix."
            } details: {
                Checklist(items: [
                    .init("Found the game file", detail: abbreviatedPath(file)),
                    .init("Matches Steam build 16690907, the version this fix is for"),
                ])
            } buttons: {
                Button("Cancel") { model.startOver() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply Fix") { model.applyFix(to: file) }
                    .keyboardShortcut(.defaultAction)
            }

        case .fixed(let file, let report):
            StatusLayout {
                StatusIcon(name: "checkmark.circle.fill", color: .green)
            } title: {
                "Fix applied"
            } message: {
                "Launch Unbound through Steam in CrossOver. The first launch can take a little longer while it pre-builds shaders."
            } details: {
                Checklist(items: [
                    .init("Checked the game version"),
                    .init(report.reusedBackup ? "Original already backed up" : "Backed up the original",
                          detail: abbreviatedPath(report.backup)),
                    .init(report.replacedOlderFix ? "Replaced the old fix with the new one"
                                                  : "Applied the fix to \(file.lastPathComponent)"),
                    .init("Checked the saved file"),
                ])
            } buttons: {
                Button("Show Backup") { model.showInFinder(report.backup) }
                Button("Done") { model.startOver() }
                    .keyboardShortcut(.defaultAction)
            }

        case .alreadyFixed(let file):
            StatusLayout {
                StatusIcon(name: "checkmark.circle.fill", color: .green)
            } title: {
                "Already fixed"
            } message: {
                "This game already has the fix. Launch Unbound through Steam in CrossOver."
            } details: {
                Checklist(items: [.init("Fix is applied", detail: abbreviatedPath(file))])
            } buttons: {
                Button("Undo Fix") { model.undoFix(on: file) }
                Button("Done") { model.startOver() }
                    .keyboardShortcut(.defaultAction)
            }

        case .olderFixFound(let file):
            StatusLayout {
                StatusIcon(name: "arrow.up.circle.fill", color: .accentColor)
            } title: {
                "Update available"
            } message: {
                "This game has the original fix, which turns shader pre-building off. The new fix keeps it on, for less stutter."
            } details: {
                Checklist(items: [
                    .init("Found the game file", detail: abbreviatedPath(file)),
                    .init("Has the original fix for Steam build 16690907"),
                ])
            } buttons: {
                Button("Undo Fix") { model.undoFix(on: file) }
                Button("Update Fix") { model.applyFix(to: file) }
                    .keyboardShortcut(.defaultAction)
            }

        case .undone(let file):
            StatusLayout {
                StatusIcon(name: "arrow.uturn.backward.circle.fill", color: .accentColor)
            } title: {
                "Fix removed"
            } message: {
                "The original game file is back, exactly as it was."
            } details: {
                Checklist(items: [.init("Original restored and checked", detail: abbreviatedPath(file))])
            } buttons: {
                Button("Done") { model.startOver() }
                    .keyboardShortcut(.defaultAction)
            }

        case .problem(let title, let message, let detail):
            StatusLayout {
                StatusIcon(name: "exclamationmark.triangle.fill", color: .orange)
            } title: {
                title
            } message: {
                message
            } details: {
                if let detail {
                    DetailBox(text: detail)
                }
            } buttons: {
                if detail != nil {
                    Button("Copy Details") { model.copyToClipboard("\(title)\n\(message)\n\n\(detail ?? "")") }
                }
                Button("Start Over") { model.startOver() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: isTargeted ? "folder.fill.badge.plus" : "folder.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .frame(height: 50)
                .accessibilityHidden(true)
            Text("Drop your game folder here")
                .font(.title3.weight(.semibold))
            Text("Unbound's game folder is named **Excalibur**.\nYou can also drop your whole CrossOver bottle.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose Folder…") { model.chooseFolder() }
                .controlSize(.large)
                .padding(.top, 6)
            if let recent = model.recentFile {
                Button {
                    model.load(recent)
                } label: {
                    Text("Check again: \(recent.deletingLastPathComponent().lastPathComponent) folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.link)
                .font(.callout)
                .help(abbreviatedPath(recent))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [7, 5]))
        }
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop Unbound's game folder, named Excalibur, here")
    }
}

// MARK: - Building blocks

/// Icon, title, message, optional details and a row of buttons, laid out the same way in every state.
private struct StatusLayout<Icon: View, Details: View, Buttons: View>: View {
    let icon: Icon
    let title: String
    let message: String
    let details: Details
    let buttons: Buttons

    init(@ViewBuilder icon: () -> Icon, title: () -> String, message: () -> String,
         @ViewBuilder details: () -> Details, @ViewBuilder buttons: () -> Buttons) {
        self.icon = icon()
        self.title = title()
        self.message = message()
        self.details = details()
        self.buttons = buttons()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            icon
                .frame(height: 48)
                .padding(.bottom, 12)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
                .padding(.top, 6)
            details
                .padding(.top, 16)
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                buttons
            }
            .controlSize(.large)
            .padding(.bottom, 16)
        }
    }
}

extension StatusLayout where Details == EmptyView {
    init(@ViewBuilder icon: () -> Icon, title: () -> String, message: () -> String,
         @ViewBuilder buttons: () -> Buttons) {
        self.init(icon: icon, title: title, message: message, details: { EmptyView() }, buttons: buttons)
    }
}

private struct StatusIcon: View {
    let name: String
    let color: Color

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 42))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

private struct Checklist: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let detail: String?

        init(_ title: String, detail: String? = nil) {
            self.title = title
            self.detail = detail
        }
    }

    let items: [Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        if let detail = item.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .help(detail)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 460)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DetailBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(4)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .frame(maxWidth: 460)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The standard round macOS help button.
private struct HelpLink: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.click))
        button.bezelStyle = .helpButton
        button.controlSize = .small
        button.toolTip = "NFS Unbound Fix Help"
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func click() { action() }
    }
}
