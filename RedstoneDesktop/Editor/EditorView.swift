import SwiftUI

struct EditorView: View {
    @ObservedObject var appState: AppState
    @StateObject private var editor = EditorSession()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Redstone Desktop").font(.headline)
                Spacer()
                Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") { appState.toggleDesktopWorld() }
                Button("Finder Diagnostics…") { openWindow(id: "finder-diagnostics") }
                Button("Save Now") { appState.saveWorldNow() }.disabled(!appState.canSaveWorld)
                Button("Desktop Controls…") { openWindow(id: "desktop-controls") }
            }.padding(12)
            Divider()
            WorldLibraryView(appState: appState, editor: editor)
            Divider()
            HStack {
                Text("New seed")
                TextField("Unsigned whole number", text: $editor.seedText).frame(width: 200)
                    .onSubmit { editor.previewSeed() }
                Button("Preview") { editor.previewSeed() }
                Button("Random") { editor.randomSeed() }
                Button("Cancel Preview") { editor.cancelPreview(appState) }
                    .disabled(editor.previewGeneration == nil)
                TextField("New world name", text: $editor.newWorldName).frame(width: 140)
                Button("Create World") { editor.createWorld(appState) }.disabled(appState.isDesktopWorldEnabled)
                Spacer()
                Button("Use This Area") { editor.useThisArea(appState) }
                    .disabled(appState.desktopScreen == nil || editor.isPreviewing(appState) || !appState.isEditingActiveWorld)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Text("Orange: proposed view · Blue: assigned desktop world only · Use This Area moves only that world; new-world activation is Slice 19B.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tools").font(.headline)
                    ForEach(EditorSession.Tool.allCases, id: \.self) { tool in
                        Button { editor.tool = tool } label: {
                            HStack { Text(tool.rawValue); Spacer(); if editor.tool == tool { Image(systemName: "checkmark") } }
                        }
                        .disabled((appState.isDesktopWorldEnabled || editor.isPreviewing(appState)) && tool.editsWorld)
                    }
                    Divider()
                    HStack {
                        Button("−") { editor.zoom(by: 0.8) }
                        Button("+") { editor.zoom(by: 1.25) }
                    }
                    Text("\(editor.camera.pointsPerTile, specifier: "%.0f") pt/tile").font(.caption)
                    Button("Show desktop area") { editor.showDesktopArea(appState) }
                    Button("Reset view") { editor.resetCamera() }
                    Text("Pan: drag canvas\nZoom: scroll or +/−").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Developer Placement…") { openWindow(id: "developer-placement") }
                }.padding(12).frame(width: 165)
                Divider()
                EditorCanvasView(appState: appState, editor: editor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                inspector.frame(width: 245)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.isDesktopWorldEnabled ? "Desktop running — disable it to edit. Select and Pan still work." : "Editing the selected world. Green: allowed; red: blocked. New worlds have procedural terrain and no demo patches.")
                if editor.isPreviewing(appState), let generation = editor.previewGeneration {
                    Text("New-world preview · seed \(generation.seed) · empty circuit. Create World or cancel to edit.").foregroundStyle(.secondary)
                }
                Text(editor.status).foregroundStyle(.secondary)
                Text(appState.persistenceStatus).foregroundStyle(.secondary).textSelection(.enabled)
                if let error = appState.finderDiagnostics.error {
                    Text("Finder unavailable: \(error) — open Finder Diagnostics to retry.").foregroundStyle(.red).font(.caption)
                }
                Text("Terrain: \(editor.terrainMetrics.retainedChunks) cached chunks · \(editor.terrainMetrics.chunkNodes) chunk nodes · \(editor.terrainMetrics.generatedChunks) generated · \(editor.terrainMetrics.textureBuilds) textures").font(.caption)
                Text("Slice 19A · World library")
                    .font(.caption)
            }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }
        .frame(minWidth: 1100, minHeight: 760)
        .onAppear { editor.syncSelectedWorld(appState) }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inspector").font(.headline)
                if let coordinate = editor.selectedTile {
                    Text("Tile (\(coordinate.x), \(coordinate.y))").font(.body.monospaced())
                    Text("Terrain: \(editor.browsingWorld(appState).tile(at: coordinate)?.terrain.rawValue ?? "unspecified")")
                    Text("Decoration: \(editor.browsingWorld(appState).tile(at: coordinate)?.decoration?.rawValue ?? "none")")
                    Text("Component: \(editor.browsingWorld(appState).circuit.components[coordinate]?.kind.rawValue ?? "none")")
                    Text("Power: \((editor.isPreviewing(appState) ? PowerLevel.off : appState.editorPower(at: coordinate)).rawValue)")
                    if editor.browsingWorld(appState).circuit.components[coordinate]?.kind == .repeater {
                        Text("Stored: \(editor.browsingWorld(appState).circuit.components[coordinate]!.direction.rawValue), \(editor.browsingWorld(appState).circuit.components[coordinate]!.repeaterDelay.rawValue)t")
                    }
                    Button("Erase selected component") { appState.eraseCircuitComponent(at: coordinate) }
                        .disabled(appState.isDesktopWorldEnabled || editor.isPreviewing(appState) || editor.browsingWorld(appState).circuit.components[coordinate] == nil)
                } else { Text("Use Select, then click a tile.").foregroundStyle(.secondary) }
                Divider()
                if editor.tool == .repeater || editor.selectedTile.flatMap({ editor.browsingWorld(appState).circuit.components[$0]?.kind }) == .repeater {
                    Picker("Direction", selection: $editor.direction) {
                        ForEach(Direction.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Delay", selection: $editor.delay) {
                        ForEach(RepeaterDelay.allCases, id: \.self) { Text("\($0.rawValue) redstone tick(s)").tag($0) }
                    }
                }
                if let coordinate = editor.selectedTile, editor.browsingWorld(appState).circuit.components[coordinate]?.kind == .repeater {
                    Button("Apply direction/delay") {
                        appState.configureRepeater(at: coordinate, direction: editor.direction, delay: editor.delay)
                    }.disabled(appState.isDesktopWorldEnabled || editor.isPreviewing(appState))
                }
                if let tile = editor.hoveredTile {
                    Text("Hover (\(tile.x), \(tile.y))").font(.caption.monospaced())
                    if let component = editor.proposedComponent {
                        let result = appState.developerPlacementPreview(component, at: tile)
                        Text(editor.isPreviewing(appState) ? "Create the world or cancel preview to edit." : (appState.isDesktopWorldEnabled ? "Disable Desktop World to edit." : result.message))
                            .foregroundStyle(result.isAllowed ? Color.green : Color.red)
                    }
                }
                Text(appState.developerPlacementStatus).font(.caption).textSelection(.enabled)
                Divider()
                Text("To run a circuit, enable Desktop World and press its input on the real desktop. Editor clicks select/place; they do not open files.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
