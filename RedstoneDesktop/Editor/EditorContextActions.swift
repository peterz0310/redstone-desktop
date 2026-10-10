import Foundation

enum EditorContextAction: Equatable {
    case inspect, copy, paste, move, rotate, delay(RepeaterDelay), delete, saveBlueprint, clearDecoration, restoreTerrain
}
struct EditorContextOption {
    let title: String
    let action: EditorContextAction
    let enabled: Bool
}

extension EditorSession {
    /// Right-click selection never places a component or activates an input.
    func prepareContext(at tile: WorldCoordinate, appState: AppState) {
        cancelPlacement(); cancelTerrainStroke()
        selectContextTile(tile, appState: appState)
    }
    func contextOptions(at tile: WorldCoordinate, appState: AppState) -> [EditorContextOption] {
        let canEdit = circuitTest == nil && !isPreviewing(appState) && !appState.isEditorConfigurationLocked
        var options = [EditorContextOption(title: "Inspect", action: .inspect, enabled: true)]
        if let component = browsingWorld(appState).circuit.components[tile] {
            let count = selection(appState).count
            options += [EditorContextOption(title: "Copy", action: .copy, enabled: !isPreviewing(appState)),
                EditorContextOption(title: "Save Selection as Blueprint…", action: .saveBlueprint, enabled: circuitTest == nil && !isPreviewing(appState)),
                EditorContextOption(title: "Move Selection", action: .move, enabled: canEdit)]
            if count > 1 || [.repeater, .torch].contains(component.kind) {
                options.append(EditorContextOption(title: count > 1 ? "Rotate Selection Clockwise" : "Rotate Clockwise", action: .rotate, enabled: canEdit))
            }
            if component.kind == .repeater, count <= 1 {
                for delay in RepeaterDelay.allCases {
                    options.append(EditorContextOption(title: "Delay: \(delay.rawValue) tick\(delay == .one ? "" : "s")", action: .delay(delay), enabled: canEdit))
                }
            }
            options.append(EditorContextOption(title: count > 1 ? "Delete Selection (\(count))" : "Delete Component", action: .delete, enabled: canEdit))
        } else { options.append(EditorContextOption(title: "Paste", action: .paste, enabled: canEdit)) }
        if let decoration = browsingWorld(appState).tile(at: tile)?.decoration {
            let world = browsingWorld(appState), appearance = DecorationAppearance.choose(decoration, at: tile, seed: world.generation?.seed ?? 0, terrain: world.tile(at: tile)?.terrain)
            options.append(EditorContextOption(title: "Remove \(appearance.name.capitalized)", action: .clearDecoration, enabled: canEdit))
        }
        if appState.selectedDocument.terrainOverrides[tile] != nil {
            options.append(EditorContextOption(title: "Restore Original Terrain", action: .restoreTerrain, enabled: canEdit))
        }
        return options
    }
    func performContext(_ action: EditorContextAction, at tile: WorldCoordinate, worldID: UUID, appState: AppState) {
        guard worldID == appState.selectedWorldID,
              contextOptions(at: tile, appState: appState).contains(where: { $0.action == action && $0.enabled }) else { return }
        switch action {
        case .inspect: sidebarTab = .build; selectContextTile(tile, appState: appState)
        case .copy: copyToClipboard(appState)
        case .paste: pasteFromClipboard(appState)
        case .saveBlueprint: requestBlueprintSave()
        case .move: beginMove(appState)
        case .rotate:
            if selection(appState).count > 1 { rotateSelection(appState) }
            else if let component = appState.editorWorld.circuit.components[tile] {
                if component.kind == .repeater { _ = appState.configureRepeater(at: tile, direction: component.direction.clockwise, delay: component.repeaterDelay) }
                if component.kind == .torch { _ = appState.configureTorch(at: tile, direction: component.direction.clockwise) }
                direction = component.direction.clockwise
            }
        case .delay(let delay):
            if let component = appState.editorWorld.circuit.components[tile] {
                _ = appState.configureRepeater(at: tile, direction: component.direction, delay: delay)
                self.delay = delay
            }
        case .delete: deleteSelection(appState)
        case .clearDecoration:
            _ = appState.applyTerrain(brush: .clearDecorations, tiles: [tile]); setContextStatus(appState.developerPlacementStatus)
        case .restoreTerrain:
            _ = appState.applyTerrain(brush: .restore, tiles: [tile]); setContextStatus(appState.developerPlacementStatus)
        }
    }
}
