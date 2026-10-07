import AppKit

/// Conservative normal-mode gate using public window metadata, never window images.
/// KNOWN FEASIBILITY BLOCKER: bounds alone do not establish click ownership;
/// macOS can report a full-display Dock window. Do not bypass it by owner-name filtering.
@MainActor
enum DesktopInteractionGate {
    static func allows(_ point: CGPoint) -> Bool { rejectionReason(point) == nil }

    static func rejectionReason(_ point: CGPoint) -> String? {
        let reference = NSScreen.screens.first.map { ScreenDescriptor(screen: $0) }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        return rejectionReason(point, finderIsFrontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
                               windows: windows, reference: reference)
    }

    static func allows(_ point: CGPoint, finderIsFrontmost: Bool, windows: [[String: Any]]?, reference: ScreenDescriptor?) -> Bool {
        rejectionReason(point, finderIsFrontmost: finderIsFrontmost, windows: windows, reference: reference) == nil
    }

    static func rejectionReason(_ point: CGPoint, finderIsFrontmost: Bool, windows: [[String: Any]]?, reference: ScreenDescriptor?) -> String? {
        guard finderIsFrontmost else { return "Finder is not active. Click blank desktop, then PRESS." }
        guard let windows, let reference else { return "Desktop window metadata is unavailable." }
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber else { return "Desktop window metadata is incomplete." }
            guard layer.intValue >= 0, alpha.doubleValue > 0 else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite else { return "A desktop window has invalid bounds." }
            if CoordinateMapper.screenRect(fromTopLeft: rect, referenceScreen: reference).contains(point) {
                let owner = window[kCGWindowOwnerName as String] as? String ?? "An application"
                return "\(owner)'s window bounds block PRESS (layer \(layer.intValue)). Bounds-based click detection is awaiting correction."
            }
        }
        return nil
    }
}
