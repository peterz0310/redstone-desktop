import SwiftUI

struct SetupWizardView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var finder: FinderDiagnosticsModel
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    init(appState: AppState) { self.appState = appState; finder = appState.finderDiagnostics }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(["Welcome to Redstone Desktop", "Finder stays your desktop", "Scripts are optional", "Ready to build"][page]).font(.largeTitle)
            Text("Step \(page + 1) of 4").font(.caption).foregroundStyle(.secondary)
            switch page {
            case 0:
                Text("Worlds are saved maps with their own seeds and circuits. Areas are named views into a world; they share its components.")
                Text("Browse and build in the editor, save an area, then explicitly assign it to Desktop. Start Desktop runs the chosen circuit; browsing never starts it.")
            case 1:
                Text("The world draws beneath real Finder icons. Finder keeps selecting, dragging and opening your files. Automation permission lets Redstone Desktop read icon positions to find the item at an Output.")
                Button("Connect to Finder…") { Task { await finder.readItems() } }.disabled(finder.isReading)
                Text("Finder: \(finder.permission.rawValue)\(finder.error.map { " · " + $0 } ?? "")").font(.callout)
                Text("You can skip this and connect later by starting Desktop or opening Finder Diagnostics. Denied access leaves the editor usable.").font(.caption).foregroundStyle(.secondary)
            case 2:
                Text("Outputs normally open files and folders. Executing .sh, .command or .zsh scripts is an explicit optional feature.")
                Text("macOS Desktop-folder access is separate from Finder Automation. Each new or changed script also asks for approval before running with your account's access. Always Allow starts checked; uncheck it to approve each run.")
                Button("Check Desktop Access for Scripts…") { appState.requestDesktopScriptAccess(retry: true) }
                    .disabled(appState.desktopScriptAccessTask != nil)
                Text(appState.desktopScriptAccessStatus).font(.caption)
                Text("Automatic script-versus-open routing remains off unless you enable it in Settings. Setup never runs a script.").font(.caption).foregroundStyle(.secondary)
            default:
                Text("Start with a button, dust and an Output on clear ground. Use harmless folders first. Stop Desktop before editing its active world; other worlds remain editable.")
                Text("Settings includes sound, appearance, optional Finder scale, export and Start Over. Start Over saves a recovery backup, then restarts into this setup with Desktop stopped.")
            }
            Spacer()
            Text("macOS privacy choices remain in System Settings. Skipping setup or starting over does not reset those choices or force new system prompts.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Skip Setup") { finish() }
                Spacer()
                if page > 0 { Button("Back") { page -= 1 } }
                Button(page == 3 ? "Finish Setup" : "Next") { if page == 3 { finish() } else { page += 1 } }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 600, height: 430)
        .disabled(appState.isMaintenanceLocked)
        .onAppear { MaintenanceSmokeConfiguration.report("wizard", state: appState) }
    }
    private func finish() { appState.finishSetup(); dismiss() }
}
