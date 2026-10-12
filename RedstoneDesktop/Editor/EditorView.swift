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
                Menu {
                    SettingsLink { Text("Settings…") }
                    Button("Appearance & Packs…") { openWindow(id: "asset-settings") }
                    Button("Finder Diagnostics…") { openWindow(id: "finder-diagnostics") }
                    Button("Desktop Details…") { openWindow(id: "desktop-controls") }
                    Divider()
                    Button("Save Now") { appState.saveWorldNow() }.disabled(!appState.canSaveWorld)
                } label: { Label("Advanced", systemImage: "ellipsis.circle") }
                Button { appState.setDesktopRunning(!appState.isDesktopWorldEnabled) } label: {
                    Label(appState.isDesktopWorldEnabled ? "Stop Desktop" : "Start Desktop", systemImage: appState.isDesktopWorldEnabled ? "stop.fill" : "play.fill")
                }.disabled(appState.isDesktopBuildMode)
            }.padding(12)
            Divider()
            HStack(spacing: 0) {
                WorldLibraryView(appState: appState, editor: editor, sheet: $sheet)
                Divider()
                VStack(spacing: 0) {
                    HStack {
                        Text(editor.proposedDesktopCamera(appState) == appState.selectedAreaCamera
                            ? "Viewing your saved area"
                            : "Moved somewhere new? Save this view or update the current area.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }.padding(10)
                    testControls
                    EditorCanvasView(appState: appState, editor: editor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topLeading) {
                Button(appState.isDesktopBuildMode ? "Exit Build Mode" : "Build on Desktop") {
                    if appState.isDesktopBuildMode { appState.exitDesktopBuildMode() }
                    else { appState.enterDesktopBuildMode() }
                }
                    .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(10)
                        }
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
                            Text("Use this area on your desktop when you’re ready.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Activate on Desktop") { editor.activateArea(appState) }
                            .disabled(appState.desktopScreen == nil || editor.isPreviewing(appState))
                    }.padding(.horizontal, 12).padding(.bottom, 10)
                }
                Divider()
                inspector.frame(width: 290)
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
        .disabled(appState.isMaintenanceLocked)
        .frame(minWidth: 1060, minHeight: 760)
        .background(EditorWindowRegistration(windows: appState.editorWindows))
        .onAppear {
            editor.syncSelectedWorld(appState)
            if appState.needsSetup { openWindow(id: "setup") }
            if appState.consumeEditorAreaRequest() { editor.showDesktopArea(appState) }
        }
        .onChange(of: appState.requestedEditorArea) { _, request in
            if request != nil, appState.consumeEditorAreaRequest() { editor.showDesktopArea(appState) }
        }
        .onChange(of: editor.tool) { _, tool in if tool != .select { editor.cancelPlacement() }; editor.cancelTerrainStroke() }
        .onChange(of: appState.selectedWorldID) { _, _ in editor.syncSelectedWorld(appState) }
        .onChange(of: appState.selectedDocument.circuit) { _, _ in editor.invalidateTestIfNeeded(appState) }
        .onChange(of: appState.isEditorConfigurationLocked) { _, locked in if locked { editor.cancelPlacement(); editor.cancelTerrainStroke() } }
        .onChange(of: appState.isMaintenanceLocked) { _, _ in editor.invalidateTestIfNeeded(appState) }
        .onDisappear { editor.stopTesting(); editor.cancelTerrainStroke(); appState.setEditorFinderItemsVisible(false) }
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
                HStack {
                    Button { editor.undo(appState) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .disabled(!appState.canUndoCircuit || editor.circuitTest != nil || editor.isPreviewing(appState)).help("Undo a circuit edit (⌘Z with the canvas focused)")
                    Button { editor.undo(appState, redo: true) } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                        .disabled(!appState.canRedoCircuit || editor.circuitTest != nil || editor.isPreviewing(appState)).help("Redo (⇧⌘Z with the canvas focused)")
                }
                Picker("Editor panel", selection: Binding(get: { editor.sidebarTab }, set: { editor.selectSidebar($0) })) {
                    ForEach(EditorSession.SidebarTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                switch editor.sidebarTab {
                case .blueprints:
                    BlueprintShelfView(library: appState.blueprints, editor: editor, appState: appState)
                case .build:
                    buildControls
                    configurationControls
                    if let tile = editor.hoveredTile {
                        Text("Hover (\(tile.x), \(tile.y))").font(.caption.monospaced())
                        if let component = editor.proposedComponent {
                            let result = appState.developerPlacementPreview(component, at: tile)
                            Text(editor.isPreviewing(appState) ? "Create the world or cancel preview to edit." : (appState.isEditorConfigurationLocked ? appState.editorConfigurationLockMessage : result.message))
                                .foregroundStyle(result.isAllowed ? Color.green : Color.red)
                        }
                    }
                    Divider()
                    Text("When you’re ready, start Desktop and press a button on your desktop to try your circuit.")
                        .font(.caption).foregroundStyle(.secondary)
                case .inspector:
                    componentInspector
                    configurationControls
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedComponent: CircuitComponent? {
        editor.selectedTile.flatMap { editor.browsingWorld(appState).circuit.components[$0] }
    }

    private var selectedKind: CircuitComponentKind? { selectedComponent?.kind }

    private var showsDirection: Bool {
        editor.sidebarTab == .inspector ? selectedKind.map { [.repeater, .torch].contains($0) } == true : [.repeater, .torch].contains(editor.tool)
    }

    private var showsDelay: Bool {
        editor.sidebarTab == .inspector ? selectedKind == .repeater : editor.tool == .repeater
    }

    private var buildControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Build").font(.headline); HelpButton(title: "Building circuits", text: "Connect a button or lever to an Output with redstone dust. Place a file or folder on the Output, then start Desktop and press the button. Move lets you inspect and pan. Select lets you drag a box around components; Shift-click adds to your selection.") }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(EditorSession.Tool.allCases, id: \.self) { tool in
                    Button { editor.tool = tool } label: {
                        HStack(spacing: 4) {
                            ToolIcon(name: tool.rawValue)
                            Text(tool.rawValue)
                            if editor.tool == tool { Image(systemName: "checkmark").font(.caption2) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 3)
                    }
                    .tint(editor.tool == tool ? .accentColor : .secondary).help(tool.description)
                    .disabled((appState.isEditorConfigurationLocked || editor.isPreviewing(appState) || editor.circuitTest != nil) && tool.editsWorld)
                }
            }
            Text(editor.tool.description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(appState.isEditorConfigurationLocked ? (appState.isDesktopBuildMode ? "This world is in Build Mode. Exit Build Mode to edit here." : "This world is running. Stop Desktop to edit it.") : editor.tool == .region ? "Drag a box around components. Shift-click adds or removes one." : editor.tool == .select ? "Click to inspect, drag to pan. Pinch or scroll to zoom." : "Choose a tool, then click clear ground to build.")
                .font(.caption).foregroundStyle(.secondary)
            if editor.tool == .output {
                Text("With Show Finder Items enabled, Output snaps within 24 points of an icon center. Red markers mean several items share a tile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if editor.tool == .terrain {
                TerrainBrushControls(brush: $editor.terrainBrush, size: $editor.terrainBrushSize)
                    .disabled(appState.isEditorConfigurationLocked || editor.isPreviewing(appState) || editor.circuitTest != nil)
            }
            if editor.tool == .fileSensor {
                Text("New sensors").font(.caption.bold())
                FileSensorConfigurationView(filter: editor.sensorFilter) { editor.sensorFilter = $0 }
                    .disabled(editor.isPreviewing(appState) || editor.circuitTest != nil || appState.isEditorConfigurationLocked)
            }
            if editor.tool == .pressurePlate || editor.tool == .fileSensor {
                HelpButton(title: "Desktop detectors", text: "A plate holds power while a Finder item is on its tile. A sensor can match an item name or a comma-separated list of file extensions, such as pdf, png, jpg. Press Save to apply its filter. Icon centers determine the tile; Finder refresh detects changes about twice a second. Empty or unavailable readings turn detectors off. In Test Circuit, click detectors to toggle simulated detection without moving files.")
            }
            Divider()
            selectionControls
        }
    }

    private var componentInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector").font(.headline)
            if let coordinate = editor.selectedTile {
                Text("Tile (\(coordinate.x), \(coordinate.y))").font(.body.monospaced())
                Text("Terrain: \(editor.browsingWorld(appState).tile(at: coordinate).map { TerrainAppearance.tile($0, generated: editor.browsingWorld(appState).generation != nil && editor.browsingWorld(appState).tiles[coordinate] == nil).terrain.rawValue } ?? "unspecified")")
                Text("Decoration: \(editor.browsingWorld(appState).tile(at: coordinate)?.decoration.map { DecorationAppearance.choose($0, at: coordinate, seed: editor.browsingWorld(appState).generation?.seed ?? 0, terrain: editor.browsingWorld(appState).tile(at: coordinate)?.terrain).name } ?? "none")")
                Text("Component: \(editor.browsingWorld(appState).circuit.components[coordinate]?.kind.title ?? "none")")
                Text(occupancyText(at: coordinate)).font(.caption)
                Text("Power: \(editor.displayedPower(at: coordinate, appState: appState).rawValue)")
                if editor.browsingWorld(appState).circuit.components[coordinate]?.kind == .repeater {
                    Text("Stored: \(editor.browsingWorld(appState).circuit.components[coordinate]!.direction.rawValue), \(editor.browsingWorld(appState).circuit.components[coordinate]!.repeaterDelay.rawValue)t")
                }
                if let component = editor.browsingWorld(appState).circuit.components[coordinate], component.kind == .torch {
                    Text("Stored: \(component.direction.rawValue), fixed 1-tick inversion")
                }
                if let component = editor.browsingWorld(appState).circuit.components[coordinate], component.kind == .output {
                    Picker("Output action", selection: Binding(get: {
                        editor.browsingWorld(appState).circuit.components[coordinate]?.outputAction ?? .openOccupant
                    }, set: { appState.configureOutput(at: coordinate, mode: $0) })) {
                        Text(appState.scriptOutputSettings.runScriptsOpenOtherItems ? "Default: scripts run, others open" : "Open item").tag(OutputActionMode.openOccupant)
                        Text("Run script").tag(OutputActionMode.executeOccupant)
                        Text("Do nothing").tag(OutputActionMode.none)
                    }.disabled(appState.isEditorConfigurationLocked || editor.isPreviewing(appState) || editor.circuitTest != nil)
                    if component.outputAction == .executeOccupant {
                        Text("Run a .sh, .command or .zsh script on this Output. You’ll be asked before a new or changed script runs.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let component = editor.browsingWorld(appState).circuit.components[coordinate], component.kind.isDesktopSensor {
                    FileSensorConfigurationView(filter: component.sensorFilter, initialMatch: editor.sensorEditRequest.flatMap { $0.tile == coordinate && $0.worldID == appState.selectedWorldID ? $0.match : nil }) { appState.configureFileSensor(at: coordinate, filter: $0) }
                        .id("sensor:\(appState.selectedWorldID):\(coordinate):\(editor.sensorEditRequest?.id.uuidString ?? "")")
                        .disabled(appState.isEditorConfigurationLocked || editor.isPreviewing(appState) || editor.circuitTest != nil)
                }
                Button("Erase selected component") {
                    appState.eraseCircuitComponent(at: coordinate, audioMapper: editor.mapper(size: editor.viewport))
                }
                    .disabled(appState.isEditorConfigurationLocked || editor.isPreviewing(appState) || editor.circuitTest != nil || editor.browsingWorld(appState).circuit.components[coordinate] == nil)
            } else { Text("Choose Move, then click a component or terrain tile to inspect it.").foregroundStyle(.secondary) }
        }
    }

    private var configurationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsDirection {
                Picker("Direction", selection: Binding(get: { editor.sidebarTab == .inspector ? selectedComponent?.direction ?? editor.direction : editor.direction }, set: { if editor.sidebarTab == .inspector { editor.setDirection($0, appState: appState) } else { editor.direction = $0 } })) {
                    ForEach(Direction.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.disabled(appState.isEditorConfigurationLocked || editor.isPreviewing(appState) || editor.circuitTest != nil)
            }
            if showsDelay {
                Picker("Delay", selection: Binding(get: { editor.sidebarTab == .inspector ? selectedComponent?.repeaterDelay ?? editor.delay : editor.delay }, set: { if editor.sidebarTab == .inspector { editor.setDelay($0, appState: appState) } else { editor.delay = $0 } })) {
                    ForEach(RepeaterDelay.allCases, id: \.self) { Text("\($0.rawValue) tick\($0 == .one ? "" : "s")").tag($0) }
                }.disabled(appState.isEditorConfigurationLocked || editor.isPreviewing(appState) || editor.circuitTest != nil)
            }
            if editor.sidebarTab == .build && editor.tool == .torch {
                Text("A torch turns on when its rear input is off. Its arrow points toward the output.").font(.caption)
            }
        }
    }

    private var selectionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Selection · \(editor.selection(appState).count)").font(.headline)
                HelpButton(title: "Working with a group", text: "Choose Select and drag a box. Shift-click adds or removes components. Copy (⌘C), Paste (⌘V), Select All (⌘A), Undo (⌘Z) and Redo (⇧⌘Z) work when the canvas is focused. Move Selection asks you to click a destination. R rotates a selected group or placement preview; Escape cancels. Every group edit can be undone in one step.")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                Button("Copy") { editor.copyToClipboard(appState) }.disabled(editor.selection(appState).isEmpty)
                Button("Paste") { editor.pasteFromClipboard(appState) }.disabled(editor.clipboard == nil || appState.isEditorConfigurationLocked)
                Button("Move Selection") { editor.beginMove(appState) }.disabled(editor.selection(appState).isEmpty || appState.isEditorConfigurationLocked)
                Button("Rotate") { if editor.pendingPlacement != nil { editor.rotatePending() } else { editor.rotateSelection(appState) } }.disabled((editor.selection(appState).isEmpty && editor.pendingPlacement == nil) || appState.isEditorConfigurationLocked)
                Button("Erase Group") { editor.deleteSelection(appState) }.disabled(editor.selection(appState).isEmpty || appState.isEditorConfigurationLocked)
                Button("Clear") { editor.clearSelection() }
            }.disabled(editor.circuitTest != nil || editor.isPreviewing(appState))
            if editor.pendingPlacement != nil {
                Text("Click to place · R rotates · Escape cancels").font(.caption).foregroundStyle(.secondary)
                Button("Cancel Placement") { editor.cancelPlacement() }
            }
        }
    }

    private var testControls: some View {
        HStack(spacing: 10) {
            if let test = editor.circuitTest {
                Button { editor.stopTesting() } label: { Label("Stop", systemImage: "stop.fill") }
                    .help("Stop testing and return to editing")
                Label("Test mode", systemImage: "testtube.2").foregroundStyle(.teal)
                Button { editor.toggleTestPlayback(appState) } label: { Label(test.isPlaying ? "Pause" : "Play", systemImage: test.isPlaying ? "pause.fill" : "play.fill") }
                Button("Step") { editor.stepTest(appState) }.disabled(test.isPlaying).help("Advance one simulation tick (50 ms)")
                Button("Reset") { editor.resetTest(appState) }
                Text("Tick \(test.tick) · \(test.outputPulses.values.reduce(0, +)) output pulses").font(.caption.monospacedDigit())
                Spacer()
                Button("Done Testing") { editor.stopTesting() }
            } else {
                Button { editor.startTesting(appState) } label: { Label("Test Circuit", systemImage: "play.rectangle") }
                    .disabled(editor.isPreviewing(appState))
                Text("Try your circuit here without opening files.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }.padding(.horizontal, 10).padding(.bottom, 8)
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
