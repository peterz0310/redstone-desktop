import AppKit

/// AppKit adapter only; clipboard JSON contains component configuration, never paths or scripts.
@MainActor
enum EditorCircuitClipboard {
    static let type = NSPasteboard.PasteboardType("org.redstonedesktop.circuit-blueprint")
    static func write(_ blueprint: CircuitBlueprint, to pasteboard: NSPasteboard = .general) throws {
        try blueprint.validate()
        let data = try JSONEncoder().encode(blueprint)
        guard data.count <= CircuitBlueprintStore.maximumBytes else { throw BlueprintError("This selection is too large to copy.") }
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: type) else { throw BlueprintError("Couldn’t copy to the clipboard.") }
    }
    static func read(from pasteboard: NSPasteboard = .general) throws -> CircuitBlueprint? {
        guard let data = pasteboard.data(forType: type) else { return nil }
        guard data.count <= CircuitBlueprintStore.maximumBytes else { throw BlueprintError("Clipboard blueprint exceeds 2 MB.") }
        let blueprint = try JSONDecoder().decode(CircuitBlueprint.self, from: data)
        try blueprint.validate(); return blueprint
    }
}
