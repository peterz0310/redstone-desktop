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
    private var durationLabel: String {
        let minutes = Int(settings.cycleMinutes)
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60, remainder = minutes % 60
        return remainder == 0 ? "\(hours) \(hours == 1 ? "hour" : "hours")" : "\(hours) hr \(remainder) min"
    }
    // A logarithmic slider leaves usable room for short cycles as well as a full real day.
    private var durationSlider: Binding<Double> {
        Binding(get: { log(settings.cycleMinutes) }, set: {
            settings.cycleMinutes = min(1440, max(2, exp($0).rounded()))
        })
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
                Text("Match System Time").tag(WorldLightingSettings.Mode.systemTime)
            }.pickerStyle(.menu)
            if settings.mode == .cycle || settings.mode == .fixed {
                if settings.mode == .cycle {
                    HStack { Text("Full day"); Spacer(); Text(durationLabel).monospacedDigit() }
                    Slider(value: durationSlider, in: log(2)...log(1440))
                        .accessibilityLabel("Full day duration").accessibilityValue(durationLabel)
                    HStack { Text("2 minutes"); Spacer(); Text("24 hours") }.font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("20 minutes") { settings.cycleMinutes = 20 }
                        Button("1 hour") { settings.cycleMinutes = 60 }
                        Button("24 hours") { settings.cycleMinutes = 1440 }
                    }.controlSize(.small)
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
            if settings.mode == .systemTime {
                Text("Follow your Mac’s local clock: noon in real life is noon here, and midnight is night. It stays in sync after sleep or reopening, and follows changes to your time zone.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Dawn is around 6 AM and dusk around 6 PM. No location access is needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Light nearby ground with torches, lava and redstone", isOn: $settings.localLights)
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
