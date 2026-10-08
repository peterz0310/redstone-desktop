import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var appState: AppState
    var body: some View {
        Form {
            Section("Output behavior") {
                Toggle("Run supported scripts; open other items", isOn: Binding(
                    get: { appState.scriptOutputSettings.runScriptsOpenOtherItems },
                    set: { appState.setRunScriptsOpenOtherItems($0) }))
                Text("Applies to Outputs set to Default. Supports .sh, .command and .zsh files. Each new or changed script still asks for approval; remembering that file is checked by default.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("An Output explicitly set to Execute script stays script-only. None disables its action. Changing this setting does not activate a circuit.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Forget Script Approvals") { appState.actionAuthorizations.revokeAll() }
            }
            Section("Desktop-folder access") {
                Text(appState.desktopScriptAccessStatus).font(.callout).textSelection(.enabled)
                Button("Check Desktop Access…") { appState.requestDesktopScriptAccess(retry: true) }
                    .disabled(appState.desktopScriptAccessTask != nil)
                Text("Access is checked when you choose Execute script or enable automatic script routing. macOS shows its permission prompt if needed. Finder Automation and permission to run a particular script are separate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 560, height: 400)
    }
}
