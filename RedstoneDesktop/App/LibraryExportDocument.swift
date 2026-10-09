import SwiftUI
import UniformTypeIdentifiers

struct LibraryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let library: WorldLibraryDocument
    init(library: WorldLibraryDocument) { self.library = library }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= WorldLibraryStore.maximumBytes else {
            throw MaintenanceError(message: "Export is missing or oversized.")
        }
        library = try JSONDecoder().decode(WorldLibraryDocument.self, from: data)
        try library.validate()
    }
    func encodedData() throws -> Data {
        try library.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        guard data.count <= WorldLibraryStore.maximumBytes else { throw MaintenanceError(message: "Library exceeds export limit.") }
        return data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try encodedData())
    }
}
