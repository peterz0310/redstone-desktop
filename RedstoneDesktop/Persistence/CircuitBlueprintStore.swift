import Foundation
import Combine

struct CircuitBlueprintDocument: Codable, Equatable, Sendable {
    var formatVersion = 1
    var blueprints: [CircuitBlueprint] = []
    func validate() throws {
        guard formatVersion == 1, blueprints.count <= 128, Set(blueprints.map(\.id)).count == blueprints.count else {
            throw BlueprintError("Unsupported or oversized blueprint library.")
        }
        for blueprint in blueprints { try blueprint.validate() }
    }
}
protocol CircuitBlueprintStoring { func load() throws -> CircuitBlueprintDocument; func save(_ document: CircuitBlueprintDocument) throws }
struct CircuitBlueprintStore: CircuitBlueprintStoring {
    static let maximumBytes = 2 * 1024 * 1024
    let fileURL: URL
    static func applicationDefault() -> Self {
        Self(fileURL: URL.applicationSupportDirectory.appendingPathComponent("RedstoneDesktop/blueprints.json"))
    }
    func load() throws -> CircuitBlueprintDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return CircuitBlueprintDocument() }
        let data = try BoundedFileReader.read(fileURL, maximumBytes: Self.maximumBytes)
        guard data.count <= Self.maximumBytes else { throw BlueprintError("The blueprint library exceeds 2 MB.") }
        let document = try JSONDecoder().decode(CircuitBlueprintDocument.self, from: data)
        try document.validate(); return document
    }
    func save(_ document: CircuitBlueprintDocument) throws {
        try document.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumBytes else { throw BlueprintError("The blueprint library exceeds 2 MB.") }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
@MainActor
final class BlueprintLibrary: ObservableObject {
    @Published private(set) var saved: [CircuitBlueprint] = []
    @Published private(set) var status = ""
    private let store: (any CircuitBlueprintStoring)?
    private var loadFailed = false
    init(store: (any CircuitBlueprintStoring)? = nil) {
        self.store = store
        do { if let store { saved = try store.load().blueprints } }
        catch { loadFailed = true; status = "Couldn’t read saved blueprints: \(error.localizedDescription) The file is preserved." }
    }
    @discardableResult func save(_ blueprint: CircuitBlueprint) -> Bool {
        guard !loadFailed else { return false }
        var document = CircuitBlueprintDocument(blueprints: saved)
        var copy = blueprint; copy.id = UUID()
        document.blueprints.append(copy)
        return commit(document)
    }
    @discardableResult func delete(_ id: UUID) -> Bool {
        guard !loadFailed else { return false }
        var document = CircuitBlueprintDocument(blueprints: saved)
        document.blueprints.removeAll { $0.id == id }
        return commit(document)
    }
    @discardableResult func rename(_ id: UUID, to name: String) -> Bool {
        guard !loadFailed, let index = saved.firstIndex(where: { $0.id == id }) else { return false }
        var document = CircuitBlueprintDocument(blueprints: saved)
        document.blueprints[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return commit(document)
    }
    private func commit(_ document: CircuitBlueprintDocument) -> Bool {
        do {
            try document.validate(); try store?.save(document)
            saved = document.blueprints; status = "Blueprint library saved."
            return true
        } catch { status = "Couldn’t save blueprints: \(error.localizedDescription) Previous library preserved."; return false }
    }
    static let examples: [CircuitBlueprint] = {
        func make(_ name: String, _ number: Int, _ cells: [WorldCoordinate: CircuitComponent]) -> CircuitBlueprint {
            var result = try! CircuitBlueprint.capture(name: name, components: cells)
            result.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
            return result
        }
        func p(_ x: Int, _ y: Int = 0) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
        let output = CircuitComponent(kind: .output, outputAction: .none)
        let delayed = make("Delayed Button", 1, [p(0): CircuitComponent(kind: .button), p(1): CircuitComponent(kind: .dust),
            p(2): CircuitComponent(kind: .repeater, direction: .east, repeaterDelay: .four), p(3): CircuitComponent(kind: .dust), p(4): output])
        let toggle = make("Toggle Switch", 2, [p(0): CircuitComponent(kind: .lever), p(1): CircuitComponent(kind: .dust), p(2): output])
        var clock: [WorldCoordinate: CircuitComponent] = [p(1,1): CircuitComponent(kind: .torch, direction: .east),
            p(3,1): CircuitComponent(kind: .repeater, direction: .east, repeaterDelay: .four), p(5,1): output]
        for tile in [p(2,1), p(4,1), p(4,0), p(3,0), p(2,0), p(1,0), p(0,0), p(0,1)] { clock[tile] = CircuitComponent(kind: .dust) }
        // The front repeater isolates the return wire, so the disable signal cannot hold the Output on.
        var switched: [WorldCoordinate: CircuitComponent] = [
            p(-4,1): CircuitComponent(kind: .lever), p(-3,1): CircuitComponent(kind: .torch, direction: .east),
            p(0,1): CircuitComponent(kind: .repeater, direction: .east),
            p(1,1): CircuitComponent(kind: .torch, direction: .east),
            p(3,1): CircuitComponent(kind: .repeater, direction: .east, repeaterDelay: .four), p(2,2): output]
        for tile in [p(-2,1), p(-1,1), p(2,1), p(4,1), p(4,0), p(4,-1), p(4,-2), p(3,-2), p(2,-2), p(1,-2), p(0,-2), p(-1,-2), p(-1,-1), p(-1,0)] { switched[tile] = CircuitComponent(kind: .dust) }
        let inverter = make("Inverted Switch", 5, [p(0): CircuitComponent(kind: .lever), p(1): CircuitComponent(kind: .torch, direction: .east), p(2): CircuitComponent(kind: .dust), p(3): output])
        let either = make("Either Button", 6, [p(0,0): CircuitComponent(kind: .button), p(0,2): CircuitComponent(kind: .button), p(0,1): CircuitComponent(kind: .dust), p(1,1): CircuitComponent(kind: .dust), p(2,1): output])
        let pdf = make("PDF Detector", 7, [p(0): CircuitComponent(kind: .fileSensor, sensorFilter: FileSensorFilter(match: .fileExtension, value: "pdf")), p(1): CircuitComponent(kind: .dust), p(2): CircuitComponent(kind: .repeater, direction: .east), p(3): output])
        let plate = make("Desktop Plate", 8, [p(0): CircuitComponent(kind: .pressurePlate), p(1): CircuitComponent(kind: .dust), p(2): output])
        return [delayed, toggle, make("Pulse Generator", 3, clock), make("Switched Pulse Generator", 4, switched), inverter, either, pdf, plate]
    }()
    static func description(for blueprint: CircuitBlueprint) -> String? {
        guard examples.contains(where: { $0.id == blueprint.id }) else { return nil }
        switch blueprint.name {
        case "Delayed Button": return "Press the button for a pulse delayed by four redstone ticks."
        case "Toggle Switch": return "The lever holds the Output on until you switch it off."
        case "Pulse Generator": return "A clock that pulses continuously without a switch."
        case "Switched Pulse Generator": return "Lever ON runs the clock; OFF stops it. Allow a moment to settle. Torches can produce a brief startup pulse."
        case "Inverted Switch": return "The Output is on while the lever is off, and off while it is on."
        case "Either Button": return "Either button triggers the shared Output."
        case "PDF Detector": return "Detects a PDF file on the sensor tile; click the sensor to simulate detection in Test Circuit."
        case "Desktop Plate": return "An item on the plate powers the Output; click the plate to simulate it in Test Circuit."
        default: return nil
        }
    }
}
