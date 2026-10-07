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
                Text("Disable Desktop World to place components, then enable it to view the result. The test patch is to the right of the original circuits. Changes last for this app session.")
                    .fixedSize(horizontal: false, vertical: true)
                Form {
                    Picker("Component", selection: $kind) {
                        ForEach(CircuitComponentKind.allCases.filter { $0 != .empty }, id: \.self) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }
                    Picker("Test tile", selection: $coordinate) {
                        ForEach(DeveloperPlacementFixture.targets) { target in
                            Text("\(target.name) (\(target.coordinate.x), \(target.coordinate.y))").tag(target.coordinate)
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
                Text(appState.isDesktopWorldEnabled ? "Disable Desktop World before editing." : result.message)
                    .foregroundStyle(result.isAllowed ? Color.green : Color.orange)
                HStack {
                    Button("Place component") { appState.placeDeveloperComponent(component, at: coordinate) }
                    Button("Reset test placements") { appState.resetDeveloperPlacements() }
                }
                .disabled(appState.isDesktopWorldEnabled)
                Text(appState.developerPlacementStatus)
                    .textSelection(.enabled)
                Divider()
                Text("Test patch contents")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(DeveloperPlacementFixture.targets) { target in
                        HStack {
                            Text("\(target.name) (\(target.coordinate.x), \(target.coordinate.y))")
                            Spacer()
                            Text(appState.desktopWorld.circuit.components[target.coordinate]?.kind.rawValue ?? "empty")
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
