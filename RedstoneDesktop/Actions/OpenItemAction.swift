import AppKit

@MainActor
protocol ItemOpening {
    func open(_ url: URL) -> Bool
}

@MainActor
struct WorkspaceItemOpener: ItemOpening {
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
}

/// Action execution has no simulation or renderer dependency.
@MainActor
struct OpenItemAction {
    let opener: any ItemOpening

    func perform(occupancy: DesktopOccupancyState) -> String {
        switch occupancy {
        case .empty: return "Output is empty; nothing opened."
        case let .ambiguous(items): return "Output is ambiguous (\(items.count) items); nothing opened."
        case let .unavailable(reason): return "Output unavailable: \(reason)"
        case let .occupied(item):
            guard item.url.isFileURL else { return "Output target is not a local Finder item; nothing opened." }
            return opener.open(item.url)
                ? "Open request accepted: \(item.displayName)"
                : "macOS could not open: \(item.displayName)"
        }
    }
}
