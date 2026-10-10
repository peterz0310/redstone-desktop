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
        let handle = try FileHandle(forReadingFrom: fileURL); defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
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
    private func commit(_ document: CircuitBlueprintDocument) -> Bool {
        do {
            try document.validate(); try store?.save(document)
            saved = document.blueprints; status = "Blueprint library saved."
            return true
        } catch { status = "Couldn’t save blueprints: \(error.localizedDescription) Previous library preserved."; return false }
    }
    static var examples: [CircuitBlueprint] {
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
        return [delayed, toggle, make("Pulse Generator", 3, clock)]
    }
}
