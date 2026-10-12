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
        return try WorldLibraryStore.encodedData(library)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try encodedData())
    }
}
