import SwiftUI

/// A cached, side-effect-free projection. Selection in the editor is deliberately absent.
struct DesktopMenuSnapshot: Equatable {
    struct Area: Identifiable, Equatable {
        let id: UUID
        let title: String
        let assigned: Bool
    }
    struct WorldGroup: Identifiable, Equatable {
        let id: UUID
        let title: String
        let areas: [Area]
    }
    let status: String
    let assignedWorld: String
    let assignedArea: String
    let groups: [WorldGroup]

    init(library: WorldLibraryDocument, running: Bool, building: Bool, paused: Bool) {
        status = building ? "Build Mode · Circuit stopped" : running ? (paused ? "Running · Simulation paused" : "Running") : "Stopped"
        assignedWorld = library.activeArea.flatMap { library.world(id: $0.worldID)?.name } ?? "Unavailable world"
        assignedArea = library.activeArea?.name ?? "Unavailable area"
        func titles(_ names: [String]) -> [String] {
            var occurrences: [String: Int] = [:]
            return names.map { name in
                occurrences[name, default: 0] += 1
                return names.filter { $0 == name }.count > 1 ? "\(name) (\(occurrences[name]!))" : name
            }
        }
        let worldTitles = titles(library.worlds.map(\.name))
        groups = zip(library.worlds, worldTitles).map { world, title in
            let areas = library.areas.filter { $0.worldID == world.id }
            return WorldGroup(id: world.id, title: title, areas: zip(areas, titles(areas.map(\.name))).map { area, label in
                Area(id: area.id, title: label, assigned: area.id == library.activeAreaID)
            })
        }
    }
}

extension AppState {
    var desktopMenu: DesktopMenuSnapshot {
        DesktopMenuSnapshot(library: library, running: isDesktopWorldEnabled,
            building: isDesktopBuildMode, paused: isSimulationPaused)
    }
}

struct DesktopMenuView: View {
    let appState: AppState
    @ObservedObject private var presentation: MenuPresentation
    init(appState: AppState) { self.appState = appState; presentation = appState.menuPresentation }
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let state = presentation.snapshot
        let menu = state.menu
        Text("Redstone Desktop · \(menu.status)")
        Text("Desktop: \(menu.assignedWorld) / \(menu.assignedArea)")
        Button(state.running ? "Stop Desktop" : "Start Desktop") {
            appState.setDesktopRunning(!state.running)
        }.disabled(state.locked || state.building || (!state.running && !state.hasDisplay))
        Menu("Assign Desktop Area") {
            Text("Choose an area. A running desktop switches automatically.")
            ForEach(menu.groups) { world in
                Menu(world.title) {
                    ForEach(world.areas) { area in
                        Button { appState.assignDesktopAreaFromMenu(area.id) } label: {
                            if area.assigned { Label(area.title, systemImage: "checkmark") }
                            else { Text(area.title) }
                        }
                        .accessibilityLabel(area.title + (area.assigned ? ", assigned to Desktop" : ""))
                    }
                    if world.areas.isEmpty { Text("No saved areas") }
                }
            }
            if menu.groups.isEmpty { Text("No saved worlds") }
        }.disabled(!state.canAssign)
        if state.building { Text("Exit Build Mode to start or assign Desktop.") }
        else if !state.hasDisplay { Text("Desktop display unavailable") }
        Divider()
        Button("Open Editor") { appState.exitDesktopBuildMode(); show("editor") }
        Button("Show Assigned Area in Editor") { appState.requestAssignedAreaInEditor(); show("editor") }
        Button(state.building ? "Exit Desktop Build Mode" : "Build on Desktop") {
            if state.building { appState.exitDesktopBuildMode() }
            else { appState.enterDesktopBuildMode() }
        }.disabled(state.locked || (!state.building && !state.hasDisplay))
        Divider()
        SettingsLink { Text("Settings…") }
        Button(state.muted ? "Unmute Sounds" : "Mute Sounds") { appState.toggleAudioMute() }
        Menu("Tools") {
            Button("Appearance & Packs…") { show("asset-settings") }
            Button("Finder Diagnostics…") { show("finder-diagnostics") }
            Button("Desktop Details…") { show("desktop-controls") }

        }
        if state.locked { Text(state.maintenance) }
        Divider()
        Button("Quit Redstone Desktop") { NSApplication.shared.terminate(nil) }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}


/// Identity has no runtime-state dependency. Accessible status belongs inside the menu,
/// so MenuBarExtra never derives its item width/title from changing status text.
struct MenuBarIdentityLabel: View {
    static let side: CGFloat = 18
    var body: some View {
        Image("MenuLogo").renderingMode(.template).resizable().interpolation(.high)
            .frame(width: Self.side, height: Self.side)
            .accessibilityLabel("Redstone Desktop")
            .help("Redstone Desktop")
    }
}
