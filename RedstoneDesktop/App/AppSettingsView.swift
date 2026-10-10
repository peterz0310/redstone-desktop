import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var confirmingReset = false
    @State private var exporting = false
    @State private var exportDocument: LibraryExportDocument?
    @State private var exportStatus = ""
    @State private var importing = false
    @State private var incoming: WorldLibraryDocument?
    @State private var confirmingImport = false

    var body: some View {
        TabView {
            Form {
                Section("Setup and permissions") {
                    Button("Open Setup…") { openWindow(id: "setup") }
                    Text("Connect to Finder so Outputs can find your desktop files. Your Mac may ask for permission.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Finder Diagnostics…") { openWindow(id: "finder-diagnostics") }
                }
                Section("Optional Finder scale") {
                    Toggle("Synchronize desktop scale to Finder icon size", isOn: Binding(
                        get: { appState.finderScale.enabled }, set: { appState.setFinderScaleEnabled($0) }))
                    Text(appState.finderScaleStatus).font(.caption)
                    Text("Match block size to your Finder icons. Try this if files don’t fit comfortably on Output blocks; turn it off to return to your saved size.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Section("Sound effects") {
                    Toggle("Enable sound effects", isOn: audioBinding(\.effectsEnabled))
                    Toggle("Mute", isOn: audioBinding(\.muted))
                    Slider(value: audioBinding(\.volume), in: 0...1) { Text("Volume") }
                    Text("Volume: \(Int(appState.audioSettings.volume * 100))%")
                    HStack {
                        Button("Preview Left") { appState.previewSound(.buttonPress, pan: -1) }
                        Button("Center") { appState.previewSound(.buttonPress) }
                        Button("Right") { appState.previewSound(.buttonPress, pan: 1) }
                    }
                    Menu("Preview Effects") { ForEach(SoundID.allCases, id: \.self) { id in Button(id.rawValue) { appState.previewSound(id) } } }
                    Text(appState.audioStatus).font(.caption)
                    Text("Sounds follow your circuit across the screen. Components outside the visible desktop stay quiet.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            AssetSettingsView(assets: appState.assets).tabItem { Label("Appearance", systemImage: "paintpalette") }
            scriptSettings.tabItem { Label("Outputs", systemImage: "terminal") }
            Form {
                Section("Your worlds") {
                    Button("Export Library…") {
                        exportDocument = LibraryExportDocument(library: appState.library); exporting = true
                    }
                    Button("Import Library…") { importing = true }
                    HStack {
                        Text("Save a copy of all your worlds, areas and circuits, or add worlds from a previous export.").font(.caption).foregroundStyle(.secondary)
                        HelpButton(title: "Library files", text: "Exports include every world, saved area and circuit. They don’t include your saved blueprint shelf, desktop files, script permissions or texture packs. Circuit copies already placed in worlds are included. Import adds independent copies to your library and keeps your current desktop assignment.")
                    }
                    if !exportStatus.isEmpty { Text(exportStatus).font(.caption).textSelection(.enabled) }
                    if let backup = appState.lastBackup {
                        Button("Reveal Reset Backup") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
                    } else {
                        Button("Reveal Backups Folder") { appState.revealBackupsFolder() }
                    }
                    if !appState.backupRevealStatus.isEmpty { Text(appState.backupRevealStatus).font(.caption).textSelection(.enabled) }
                }
                Section("Start over") {
                    Button("Start Over…", role: .destructive) { confirmingReset = true }
                    Text("Backs up your app data, then starts fresh with an empty world and default settings. Your desktop files stay safe.").font(.caption).foregroundStyle(.secondary)
                    if !appState.maintenanceStatus.isEmpty { Text(appState.maintenanceStatus).font(.caption).textSelection(.enabled) }
                }
            }.formStyle(.grouped).tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .padding(12).frame(width: 700, height: 600)
        .disabled(appState.isMaintenanceLocked)
        .overlay(alignment: .bottom) {
            if appState.isMaintenanceLocked {
                VStack { Text(appState.maintenanceStatus).textSelection(.enabled); Button("Quit") { appState.shutdown(); NSApplication.shared.terminate(nil) } }
                    .padding().background(.regularMaterial)
            }
        }
        .alert("Start Over and Restart?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Back Up, Reset and Restart", role: .destructive) {
                Task { if await appState.startOver() { NSApplication.shared.terminate(nil) } }
            }
        } message: {
            Text("Your worlds, settings and imported textures will be backed up before the app restarts with a fresh setup. Your desktop files and Mac permissions won’t change. You can restore the backup using the recovery guide.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    incoming = try LibraryImport.read(from: url)
                    confirmingImport = true
                } catch { exportStatus = "Couldn’t import this library: \(error.localizedDescription)" }
            case .failure(let error): exportStatus = "Couldn’t open this library: \(error.localizedDescription)"
            }
        }
        .alert("Add these worlds?", isPresented: $confirmingImport) {
            Button("Cancel", role: .cancel) { incoming = nil }
            Button("Add Worlds") {
                if let incoming {
                    let added = appState.importLibrary(incoming)
                    exportStatus = added ? "Worlds added. Find them in the editor’s world list." : appState.libraryStatus
                }
                incoming = nil
            }
        } message: {
            Text(incoming.map { "\($0.worlds.count) world(s) and \($0.areas.count) area(s): \($0.worlds.map(\.name).joined(separator: ", ")). These will be added as separate copies. Your current desktop stays selected." } ?? "")
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "RedstoneDesktop-library") { result in
            switch result { case .success: exportStatus = "Library exported."; case .failure(let error): exportStatus = "Export failed: \(error.localizedDescription)" }
        }
    }
    private func audioBinding<Value>(_ key: WritableKeyPath<AudioSettings, Value>) -> Binding<Value> {
        Binding(get: { appState.audioSettings[keyPath: key] }, set: { value in
            var settings = appState.audioSettings; settings[keyPath: key] = value; appState.setAudioSettings(settings)
        })
    }
    private var scriptSettings: some View {
        Form {
            Section("Output behavior") {
                Toggle("Run supported scripts; open other items", isOn: Binding(
                    get: { appState.scriptOutputSettings.runScriptsOpenOtherItems }, set: { appState.setRunScriptsOpenOtherItems($0) }))
                Text("When enabled, Outputs run .sh, .command and .zsh scripts and open other files normally. You’ll be asked before running a new or changed script.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Forget Script Approvals") { appState.actionAuthorizations.revokeAll() }
            }
            Section("Desktop-folder access") {
                Text(appState.desktopScriptAccessStatus).font(.callout).textSelection(.enabled)
                Button("Check Desktop Access…") { appState.requestDesktopScriptAccess(retry: true) }.disabled(appState.desktopScriptAccessTask != nil)
                Text("Your Mac needs to allow access before the app can read desktop scripts. You’ll still choose which scripts may run.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
