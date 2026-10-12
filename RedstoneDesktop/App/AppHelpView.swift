import SwiftUI

/// Offline instructions; opening Help never starts Finder tracking, simulation or an action.
struct AppHelpView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    var body: some View {
        GeometryReader { viewport in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Image("AppLogo").resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading) {
                        Text("Welcome to Redstone Desktop").font(.title)
                        Text("Version \(version) · Early preview").foregroundStyle(.secondary)
                    }
                }
                section("Your first circuit", symbol: "play.circle") {
                    Text("1. Place a Button, a short path of Dust, and an Output on clear ground. Use Terrain → Grass if you need room.")
                    Text("2. Try Test Circuit first. Click the button and watch the wire. Testing never opens files or runs scripts.")
                    Text("3. Save the view as an Area, choose Activate on Desktop, then Start Desktop. Put a harmless folder on the Output and press your circuit’s button.")
                    Text("Keep Finder icons away from buttons and levers so the app can tell a circuit press from selecting a file.")
                }
                section("Find your way around", symbol: "map") {
                    Text("Worlds keep separate builds. Areas are saved views into a world; areas in the same world share their circuits. Browsing another area doesn’t change your desktop until you activate it.")
                    Text("Move: drag to pan, click to inspect. Scroll or pinch to zoom. Select: drag around a group. Right-click for relevant actions. Copy, paste and undo work when the map has keyboard focus.")
                    Text("Blueprints includes ready-made circuits and your saved selections. Example Outputs start with Do nothing; change the action in Inspector when you want to open a file.")
                    Text("Build on Desktop edits beneath your files with the circuit stopped. Exit Build Mode, then Start Desktop when you’re ready. The menu-bar logo can stop Desktop or assign another area.")
                }
                section("Textures, light and sound", symbol: "paintpalette") {
                    Text("Settings → Appearance lets you import graphics and short sounds from your local Minecraft Java installation or a pack. Minecraft isn’t required; the original look works on its own.")
                    Text("The animation, scenery and particle switches are independent. Your Mac’s Reduce Motion setting pauses these effects. World Settings controls daylight, a moving clock or your Mac’s local time; Settings → Sound controls effects and volume.")
                }
                section("If a circuit doesn’t respond", symbol: "questionmark.circle") {
                    Text("Check that Desktop is started and the intended area is assigned. Keep inputs clear of files and other app windows. Make sure repeaters face along the path. An Output acts once when its power turns on; wait for power to turn off before trying again.")
                    Text("Connect to Finder in Setup, or check Settings → General → Finder Diagnostics. macOS may need permission under System Settings → Privacy & Security → Automation → Finder.")
                    Text("Sensors follow Finder’s latest icon positions and may take a moment after a move. In Test Circuit, click a sensor to simulate detection without moving real files.")
                }
                section("Keep your builds safe", symbol: "externaldrive") {
                    Text("Edits save automatically. Settings → Data can export all worlds and areas or import copies. The separate saved blueprint shelf isn’t included in a library export.")
                    Text("Your whole library has a 2 MB limit. A change that won’t fit is refused before altering your build. Remove unused worlds or restore painted terrain to make room.")
                    Text("If saving fails, Quit lets you stay open, retry, or save a recovery copy elsewhere. Don’t Force Quit while you have unsaved changes. Start Over backs up app data before resetting; it does not delete desktop files or reset Mac permissions.")
                }
                section("Your files and privacy", symbol: "lock.shield") {
                    Text("Everything runs locally on your Mac, without an account. Finder reads names, paths and icon positions to connect your circuit to the current file. Texture packs never execute code.")
                    Text("Outputs open items by default. Running supported shell scripts is optional and needs separate approval for a new or changed file. Remembered approvals can be forgotten in Settings → Outputs. Only run scripts you trust.")
                    Text("The app includes original artwork and an owner-provided logo. Minecraft graphics and audio are optional local imports; none is bundled.")
                    HStack {
                        Button("View License") { revealResource("LICENSE") }
                        Button("Artwork Notices") { revealResource("THIRD_PARTY_NOTICES", extension: "md") }
                    }
                }
            }.frame(width: max(0, viewport.size.width - 56), alignment: .leading).padding(28)
        }
        }.frame(minWidth: 580, minHeight: 460)
    }
    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content().fixedSize(horizontal: false, vertical: true)
        }
    }
    private func revealResource(_ name: String, extension suffix: String? = nil) {
        if let url = Bundle.main.url(forResource: name, withExtension: suffix) { NSWorkspace.shared.open(url) }
    }
}
