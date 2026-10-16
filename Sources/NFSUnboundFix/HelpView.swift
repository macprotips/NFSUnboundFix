import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NFS Unbound Fix Help")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("What does it do?",
                            "It fixes the black screen at startup in Need for Speed Unbound when you play it in CrossOver with D3DMetal. At startup the game pre-builds the shaders it saved last time, and a few of them can't be created on a Mac, which crashed the game. The fix makes the game skip just those and carry on, so it starts and keeps pre-building everything else, for less stutter. It changes a few bytes in one game file, Engine.Render.Core2.PlatformPcDx12.dll.")
                    section("I used the original fix. Should I update?",
                            "Yes. The original fix stopped the crash by turning shader pre-building off completely, which causes more stutter while you play. Drop your game folder in and click Update Fix. The first launch afterwards can take a little longer while shaders are built.")
                    section("Where's my game folder?",
                            "The game's folder is named Excalibur, not Need for Speed Unbound. It's inside your CrossOver bottle, usually ~/Library/Application Support/CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam/steamapps/common/Excalibur. You don't have to find it exactly: drop the whole bottle and the app finds the file.")
                    section("Is it safe?",
                            "It only changes the exact file version the fix was made for (Steam build 16690907) and stops if anything else is different. It backs up the original first, checks the result before and after saving, and puts the original back if anything doesn't match.")
                    section("How do I undo it?",
                            "Drop the game folder in again and click Undo Fix. Steam's \"Verify integrity of game files\" also brings back the original.")
                    section("The fix stopped working after an update",
                            "Steam updates and file verification can replace the file. Run the app again. If it says the version isn't supported, the game file has changed and this fix doesn't apply to it.")
                    section("Who made this?",
                            "NFS Unbound Fix is an independent tool. It isn't made, endorsed or supported by Electronic Arts or Criterion Games. Need for Speed and Need for Speed Unbound are trademarks of Electronic Arts Inc.")
                    section("Where are the backups?",
                            "In ~/Library/Application Support/NFS Unbound Fix/Backups. Click Backups at the bottom of the window to open the folder.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 500, height: 480)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
