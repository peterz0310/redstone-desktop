import SwiftUI

struct EditorView: View {
    @ObservedObject var appState: AppState
    @StateObject private var editor = EditorSession()
    @Environment(\.openWindow) private var openWindow

    @State private var sheet: LibrarySheetRequest?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Editing: \(appState.selectedDocument.name) / \(appState.selectedArea.name)").font(.headline)
                    Text("Desktop: \(appState.activeWorldName) / \(appState.library.activeArea!.name) · \(appState.isDesktopBuildMode ? "BUILD MODE" : appState.isDesktopWorldEnabled ? "Running" : "Stopped")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(appState.isDesktopBuildMode ? "Exit Build Mode" : "Build on Desktop") {
                    if appState.isDesktopBuildMode { appState.exitDesktopBuildMode() }
                    else { appState.enterDesktopBuildMode() }
                }
                Button(appState.isDesktopWorldEnabled ? "Stop Desktop" : "Start Desktop") { appState.toggleDesktopWorld() }
                    .disabled(appState.isDesktopBuildMode)
                Menu {
                    Button("Appearance & Packs…") { openWindow(id: "asset-settings") }
                    Button("Finder Diagnostics…") { openWindow(id: "finder-diagnostics") }
                    Button("Desktop Details…") { openWindow(id: "desktop-controls") }
                    Divider()
                    Button("Save Now") { appState.saveWorldNow() }.disabled(!appState.canSaveWorld)
                } label: { Label("Advanced", systemImage: "ellipsis.circle") }
            }.padding(12)
            Divider()
            HStack(spacing: 0) {
                WorldLibraryView(appState: appState, editor: editor, sheet: $sheet)
                Divider()
                VStack(spacing: 0) {
                    HStack {
                        Text(editor.proposedDesktopCamera(appState) == appState.selectedAreaCamera
                            ? "Browsing saved area · Orange: proposed view · Blue: desktop"
                            : "Unsaved view · Save a new bookmark or Update Current Area")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }.padding(10)
                    EditorCanvasView(appState: appState, editor: editor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topTrailing) { viewportControls.padding(10) }
                    if appState.editorFinderItemsVisible {
                        Text(appState.isFinderLayoutSettling ? "Finder icon size changed · waiting for fresh positions…" : appState.isDisplaySettling ? "Display changed · waiting for fresh Finder positions…" : editor.isPreviewing(appState) ? "Finder projection hidden during seed preview" : "Finder projection: \(appState.selectedDocument.name) · proposed view · desktop assignment unchanged")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 6)
                    }
                    Divider()
                    AreaShelfView(appState: appState, editor: editor, sheet: $sheet)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Desktop target: \(appState.selectedArea.name)").font(.callout)
                            Text("Saved origin (\(appState.selectedAreaCamera.worldOrigin.x, specifier: "%.1f"), \(appState.selectedAreaCamera.worldOrigin.y, specifier: "%.1f")) · browsing never activates it")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Activate on Desktop") { editor.activateArea(appState) }
                            .disabled(appState.desktopScreen == nil || editor.isPreviewing(appState))
                    }.padding(.horizontal, 12).padding(.bottom, 10)
                }
                Divider()
                inspector.frame(width: 230)
            }
            Divider()
            HStack {
                Text(editor.status)
                    .lineLimit(2)
                Spacer()
                Text(appState.persistenceStatus).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }.font(.caption).padding(8)
            if let error = appState.finderDiagnostics.error {
                HStack {
                    Text("Finder unavailable: \(error)").foregroundStyle(.red).lineLimit(2)
                    Spacer()
                    Button("Finder Diagnostics…") { openWindow(id: "finder-diagnostics") }
                }.font(.caption).padding(8)
            }
        }
        .frame(minWidth: 1060, minHeight: 760)
        .background(EditorWindowRegistration(windows: appState.editorWindows))
        .onAppear { editor.syncSelectedWorld(appState) }
        .onDisappear { appState.setEditorFinderItemsVisible(false) }
        .sheet(item: $sheet, onDismiss: { if editor.isPreviewing(appState) { editor.cancelPreview(appState) } }) { request in
            LibrarySheetView(kind: request.kind, appState: appState, editor: editor, targetID: request.targetID)
        }
    }

    private func occupancyText(at coordinate: WorldCoordinate) -> String {
        switch editor.finderProjection(appState).occupancy.state(at: coordinate) {
        case .empty: return "Projected Finder: empty"
        case let .occupied(item): return "Projected Finder: \(item.displayName)"
        case let .ambiguous(items): return "Projected Finder: \(items.count) items — ambiguous"
        case let .unavailable(reason): return "Projected Finder: \(reason)"
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Build").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(EditorSession.Tool.allCases, id: \.self) { tool in
                        Button { editor.tool = tool } label: {
                            HStack(spacing: 4) {
                                Text(tool.rawValue)
                                if editor.tool == tool { Image(systemName: "checkmark").font(.caption2) }
                            }.frame(maxWidth: .infinity).padding(.vertical, 3)
                        }
                        .tint(editor.tool == tool ? .accentColor : .secondary)
                        .disabled((appState.isEditorConfigurationLocked || editor.isPreviewing(appState)) && tool.editsWorld)
                    }
                }
                Text(appState.isEditorConfigurationLocked ? (appState.isDesktopBuildMode ? "This world is in Build Mode. Exit Build Mode to edit here." : "This world is running. Stop Desktop to edit it.") : editor.tool == .select ? "Click to inspect, drag to pan. Pinch or scroll to zoom." : "Choose a component, then click a green tile to place it.")
                    .font(.caption).foregroundStyle(.secondary)
                if editor.tool == .output {
                    Text("With Show Finder Items enabled, Output snaps within 24 points of an icon center. Red markers mean several items share a tile.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text("Inspector").font(.headline)
                if let coordinate = editor.selectedTile {
                    Text("Tile (\(coordinate.x), \(coordinate.y))").font(.body.monospaced())
                    Text("Terrain: \(editor.browsingWorld(appState).tile(at: coordinate).map { TerrainAppearance.tile($0, generated: editor.browsingWorld(appState).generation != nil && editor.browsingWorld(appState).tiles[coordinate] == nil).terrain.rawValue } ?? "unspecified")")
                    Text("Decoration: \(editor.browsingWorld(appState).tile(at: coordinate)?.decoration.map { DecorationAppearance.choose($0, at: coordinate, seed: editor.browsingWorld(appState).generation?.seed ?? 0, terrain: editor.browsingWorld(appState).tile(at: coordinate)?.terrain).name } ?? "none")")
                    Text("Component: \(editor.browsingWorld(appState).circuit.components[coordinate]?.kind.rawValue ?? "none")")
                    Text(occupancyText(at: coordinate)).font(.caption)
                    Text("Power: \((editor.isPreviewing(appState) ? PowerLevel.off : appState.editorPower(at: coordinate)).rawValue)")
                    if editor.browsingWorld(appState).circuit.components[coordinate]?.kind == .repeater {
                        Text("Stored: \(editor.browsingWorld(appState).circuit.components[coordinate]!.direction.rawValue), \(editor.browsingWorld(appState).circuit.components[coordinate]!.repeaterDelay.rawValue)t")
                    }
                    Button("Erase selected component") {
                        appState.eraseCircuitComponent(at: coordinate, audioMapper: editor.mapper(size: editor.viewport))
                    }
                        .disabled(appState.isEditorConfigurationLocked || editor.isPreviewing(appState) || editor.browsingWorld(appState).circuit.components[coordinate] == nil)
                } else { Text("Navigate: click to inspect, drag to pan. Pinch or scroll to zoom.").foregroundStyle(.secondary) }
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
                    }.disabled(appState.isEditorConfigurationLocked || editor.isPreviewing(appState))
                }
                if let tile = editor.hoveredTile {
                    Text("Hover (\(tile.x), \(tile.y))").font(.caption.monospaced())
                    if let component = editor.proposedComponent {
                        let result = appState.developerPlacementPreview(component, at: tile)
                        Text(editor.isPreviewing(appState) ? "Create the world or cancel preview to edit." : (appState.isEditorConfigurationLocked ? appState.editorConfigurationLockMessage : result.message))
                            .foregroundStyle(result.isAllowed ? Color.green : Color.red)
                    }
                }
                DisclosureGroup("Technical Details") {
                    Text(appState.developerPlacementStatus).font(.caption).textSelection(.enabled)
                    Text("Terrain: \(editor.terrainMetrics.retainedChunks) cached chunks · \(editor.terrainMetrics.chunkNodes) nodes · \(editor.terrainMetrics.generatedChunks) generated · \(editor.terrainMetrics.textureBuilds) textures").font(.caption)
                    Text("Slice 22 · Finder icon size").font(.caption)
                }
                Divider()
                Text("To run a circuit, enable Desktop World and press its input on the real desktop. Editor clicks select/place; they do not open files.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var viewportControls: some View {
        VStack(spacing: 8) {
            Button { editor.showDesktopArea(appState) } label: { Image(systemName: "house.fill") }
                .help("Show active desktop area (may switch the world you are browsing)").accessibilityLabel("Show active desktop area")
            Divider().frame(width: 22)
            Button { editor.zoom(by: 1.25) } label: { Image(systemName: "plus") }.help("Zoom in").accessibilityLabel("Zoom in")
            Button { editor.zoom(by: 0.8) } label: { Image(systemName: "minus") }.help("Zoom out").accessibilityLabel("Zoom out")
            Menu {
                Toggle("Show Finder Items", isOn: Binding(get: { appState.editorFinderItemsVisible }, set: { appState.setEditorFinderItemsVisible($0) }))
                Button("Return to saved view") { editor.selectArea(appState.selectedAreaID, appState: appState) }
                Button("Reset to Origin") { editor.resetCamera() }
            } label: { Image(systemName: "eye") }.menuIndicator(.hidden).help("View options · Return to this area's saved view").accessibilityLabel("View options")
        }
        .buttonStyle(.borderless).controlSize(.large)
        .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
