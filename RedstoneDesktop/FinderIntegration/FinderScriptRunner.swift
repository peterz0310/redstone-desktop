import Foundation

@MainActor
protocol FinderScriptRunning {
    func queryDesktopItems() throws -> NSAppleEventDescriptor
    func queryDesktopSnapshot() throws -> NSAppleEventDescriptor
}

extension FinderScriptRunning {
    func queryDesktopSnapshot() throws -> NSAppleEventDescriptor {
        let result = NSAppleEventDescriptor.list()
        result.insert(.null(), at: 1)
        result.insert(.null(), at: 2)
        result.insert(try queryDesktopItems(), at: 3)
        return result
    }
}

/// NSAppleScript must run on the main thread. The diagnostic model serializes reads.
@MainActor
struct FinderScriptRunner: FinderScriptRunning {
    static let desktopQuery = """
    with timeout of 10 seconds
        tell application id "com.apple.finder"
            set resultRows to {}
            repeat with desktopItem in (get every item of desktop)
                set itemName to name of desktopItem
                set itemPath to POSIX path of (desktopItem as alias)
                set itemPosition to desktop position of desktopItem
                set end of resultRows to {itemName, itemPath, item 1 of itemPosition, item 2 of itemPosition}
            end repeat
            return resultRows
        end tell
    end timeout
    """

    static let desktopSnapshotQuery = """
    with timeout of 10 seconds
        tell application id "com.apple.finder"
            set desktopItems to (get every item of desktop)
            set initialSize to missing value
            try
                set initialSize to icon size of icon view options of desktop window
            end try
            set resultRows to {}
            repeat with desktopItem in desktopItems
                set itemName to name of desktopItem
                set itemPath to POSIX path of (desktopItem as alias)
                set itemPosition to desktop position of desktopItem
                set end of resultRows to {itemName, itemPath, item 1 of itemPosition, item 2 of itemPosition}
            end repeat
            set finalSize to missing value
            try
                set finalSize to icon size of icon view options of desktop window
            end try
            return {initialSize, finalSize, resultRows}
        end tell
    end timeout
    """

    func queryDesktopSnapshot() throws -> NSAppleEventDescriptor {
        try Self.execute(source: Self.desktopSnapshotQuery)
    }

    func queryDesktopItems() throws -> NSAppleEventDescriptor {
        try Self.execute(source: Self.desktopQuery)
    }

    static func execute(source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw FinderReadError.scriptFailure(code: nil, message: "Could not create the AppleScript.")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil {
            throw FinderReadError.fromScriptError(error)
        }
        return result
    }
}
