import SwiftUI

/// A small rule-testing form, not the general circuit editor.
struct DeveloperPlacementView: View {
    @ObservedObject var appState: AppState
    @State private var kind = CircuitComponentKind.dust
    @State private var direction = Direction.east
    @State private var delay = RepeaterDelay.one
    @State private var coordinate = WorldCoordinate(x: 10, y: 3)

    private var component: CircuitComponent {
        CircuitComponent(kind: kind, direction: direction, repeaterDelay: delay)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Developer Placement")
                    .font(.title)
                Text("Edits affect the selected editor world and autosave. The migrated world retains its developer patch to the right of the original circuits; procedural worlds use their own terrain. Disable Desktop World to edit its active world; inactive worlds remain editable.")
                    .fixedSize(horizontal: false, vertical: true)
                Form {
                    Picker("Component", selection: $kind) {
                        ForEach(CircuitComponentKind.allCases.filter { $0 != .empty }, id: \.self) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }
                    Picker("Test tile", selection: $coordinate) {
                        ForEach(DeveloperPlacementFixture.targets) { target in
                            Text("\(appState.editorWorld.tile(at: target.coordinate)?.terrain.rawValue ?? "unspecified") (\(target.coordinate.x), \(target.coordinate.y))").tag(target.coordinate)
                        }
                    }
                    if kind == .repeater {
                        Picker("Direction", selection: $direction) {
                            ForEach(Direction.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        Picker("Delay", selection: $delay) {
                            ForEach(RepeaterDelay.allCases, id: \.self) { Text("\($0.rawValue) redstone tick(s)").tag($0) }
                        }
                    }
                }
                let result = appState.developerPlacementPreview(component, at: coordinate)
                Text(appState.isEditorConfigurationLocked ? "Disable Desktop World before editing." : result.message)
                    .foregroundStyle(result.isAllowed ? Color.green : Color.orange)
                HStack {
                    Button("Place component") { appState.placeDeveloperComponent(component, at: coordinate) }
                    Button("Reset test placements") { appState.resetDeveloperPlacements() }
                        .disabled(appState.selectedDocument.terrainProfile != .legacyFixtureV1)
                }
                .disabled(appState.isEditorConfigurationLocked)
                Text(appState.developerPlacementStatus)
                    .textSelection(.enabled)
                Divider()
                Text("Test patch contents")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(DeveloperPlacementFixture.targets) { target in
                        HStack {
                            Text("\(appState.editorWorld.tile(at: target.coordinate)?.terrain.rawValue ?? "unspecified") (\(target.coordinate.x), \(target.coordinate.y))")
                            Spacer()
                            Text(appState.editorWorld.circuit.components[target.coordinate]?.kind.rawValue ?? "empty")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption.monospaced())
                    }
                }
                Text("Reset removes only components placed in this test patch. Terrain, decorations, and the three original circuits are preserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}
