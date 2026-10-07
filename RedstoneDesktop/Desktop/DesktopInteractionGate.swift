import AppKit

/// Conservative normal-mode gate using public window metadata, never window images.
@MainActor
enum DesktopInteractionGate {
    static func allows(_ point: CGPoint) -> Bool {
        let reference = NSScreen.screens.first.map { ScreenDescriptor(screen: $0) }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        return allows(point, finderIsFrontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
                      windows: windows, reference: reference)
    }

    static func allows(_ point: CGPoint, finderIsFrontmost: Bool, windows: [[String: Any]]?, reference: ScreenDescriptor?) -> Bool {
        guard finderIsFrontmost, let windows, let reference else { return false }
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber else { return false }
            // The desktop renderer is below normal windows; invisible windows cannot own a click.
            guard layer.intValue >= 0, alpha.doubleValue > 0 else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite else { return false }
            if CoordinateMapper.screenRect(fromTopLeft: rect, referenceScreen: reference).contains(point) { return false }
        }
        return true
    }
}
