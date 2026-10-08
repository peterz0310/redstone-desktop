import Foundation
import CoreServices

@MainActor
struct FinderDesktopItemProvider: DesktopItemProviding {
    let runner: any FinderScriptRunning

    init(runner: any FinderScriptRunning = FinderScriptRunner()) {
        self.runner = runner
    }

    func currentDesktopItems() async throws -> [DesktopItem] {
        try await currentDesktopSnapshot().items
    }

    func currentDesktopSnapshot() async throws -> FinderDesktopSnapshot {
        try Self.parseSnapshot(runner.queryDesktopSnapshot())
    }

    static func parseSnapshot(_ result: NSAppleEventDescriptor) throws -> FinderDesktopSnapshot {
        guard result.descriptorType == typeAEList, result.numberOfItems == 3, let rows = result.atIndex(3) else {
            throw FinderReadError.malformedResponse("Expected icon-size samples and desktop item rows.")
        }
        let before = number(result.atIndex(1)).flatMap { FinderViewSettings(iconSize: $0) }
        let after = number(result.atIndex(2)).flatMap { FinderViewSettings(iconSize: $0) }
        // Unsupported/invalid optional settings must not hide valid item positions.
        return FinderDesktopSnapshot(items: try parse(rows), viewSettings: after,
            layoutIsStable: before == nil || after == nil || before == after)
    }

    static func parse(_ result: NSAppleEventDescriptor) throws -> [DesktopItem] {
        guard result.descriptorType == typeAEList else {
            throw FinderReadError.malformedResponse("Expected a list of items.")
        }
        guard result.numberOfItems > 0 else { return [] }
        return try (1...result.numberOfItems).map { index in
            guard let row = result.atIndex(index), row.descriptorType == typeAEList, row.numberOfItems == 4,
                  let nameField = row.atIndex(1), let pathField = row.atIndex(2),
                  isText(nameField), isText(pathField),
                  let name = nameField.stringValue, let path = pathField.stringValue,
                  path.hasPrefix("/"), !path.contains("\0"),
                  let x = number(row.atIndex(3)), let y = number(row.atIndex(4)) else {
                throw FinderReadError.malformedResponse("Item \(index) needs a name, absolute path, and two numeric coordinates.")
            }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .isDirectoryKey, .isApplicationKey, .isAliasFileKey, .isRegularFileKey])
            let id: String
            if let identifier = values?.fileResourceIdentifier as? Data {
                id = "file-id:" + identifier.base64EncodedString()
            } else {
                id = "url:" + url.absoluteString
            }
            let kind: DesktopItemKind
            if values?.isAliasFile == true { kind = .alias }
            else if values?.isApplication == true { kind = .application }
            else if values?.isDirectory == true { kind = .folder }
            else if values?.isRegularFile == true { kind = .file }
            else { kind = .unknown }
            return DesktopItem(id: id, url: url, displayName: name, position: CGPoint(x: x, y: y), estimatedIconSize: nil, kind: kind)
        }
    }

    private static func isText(_ descriptor: NSAppleEventDescriptor) -> Bool {
        [typeUnicodeText, typeUTF8Text, typeChar].contains(descriptor.descriptorType)
    }

    private static func number(_ descriptor: NSAppleEventDescriptor?) -> Double? {
        guard let descriptor,
              [typeSInt16, typeSInt32, typeSInt64, typeUInt32, typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint].contains(descriptor.descriptorType) else { return nil }
        let value = descriptor.doubleValue
        return value.isFinite ? value : nil
    }
}
