import SwiftUI

struct WorldLightingSettingsView: View {
    @ObservedObject var appState: AppState
    let world: WorldDocument
    @Environment(\.dismiss) private var dismiss
    @State private var settings: WorldLightingSettings
    @State private var error = ""

    init(appState: AppState, world: WorldDocument) {
        self.appState = appState; self.world = world
        var draft = world.lighting
        if draft.mode == .cycle { draft.startPhase = draft.phase(at: Date().timeIntervalSince1970) }
        draft.anchorTime = Date().timeIntervalSince1970
        _settings = State(initialValue: draft)
    }
    private var clockLabel: String {
        let minutes = Int((settings.startPhase * 1440 + 360).rounded()) % 1440
        let hour = minutes / 60
        return "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minutes % 60)) \(hour < 12 ? "AM" : "PM")"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("World Settings").font(.title2.bold())
            Text(world.name).font(.headline)
            Text("Set the mood for every area in this world. Other worlds keep their own lighting.")
                .foregroundStyle(.secondary)
            Picker("Lighting", selection: $settings.mode) {
                Text("Always Day").tag(WorldLightingSettings.Mode.day)
                Text("Day & Night").tag(WorldLightingSettings.Mode.cycle)
                Text("Always Night").tag(WorldLightingSettings.Mode.night)
                Text("Fixed Time").tag(WorldLightingSettings.Mode.fixed)
            }.pickerStyle(.menu)
            if settings.mode == .cycle || settings.mode == .fixed {
                if settings.mode == .cycle {
                    Stepper("Full day: \(Int(settings.cycleMinutes)) minutes", value: $settings.cycleMinutes, in: 2...120, step: 1)
                }
                HStack { Text(settings.mode == .fixed ? "Keep at" : "Start at"); Spacer(); Text(clockLabel).monospacedDigit() }
                Slider(value: $settings.startPhase, in: 0...1, step: 1.0 / 96)
                HStack {
                    Button("Dawn") { settings.startPhase = 0 }
                    Button("Noon") { settings.startPhase = 0.25 }
                    Button("Dusk") { settings.startPhase = 0.5 }
                    Button("Midnight") { settings.startPhase = 0.75 }
                }.controlSize(.small)
                Text(settings.mode == .fixed
                    ? "This world stays at this time, even when you reopen the app."
                    : "Time continues while the app is closed. Areas in this world share the same clock.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Light nearby ground with lava and powered redstone", isOn: $settings.localLights)
            Text("Lights are easiest to see at night. They change the look of your world, not how circuits work.")
                .font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    settings.anchorTime = Date().timeIntervalSince1970
                    if appState.updateWorldLighting(world.id, settings: settings) { dismiss() }
                    else { error = appState.libraryStatus }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 450)
    }
}
