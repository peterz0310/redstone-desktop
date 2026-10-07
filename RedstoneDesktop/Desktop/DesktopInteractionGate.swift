import AppKit

struct DesktopInteractionAssessment {
    let rejectionReason: String?
    let details: String
}

/// Validate the associated window; a monitored CGEvent target PID is diagnostic only.
@MainActor
enum DesktopInteractionGate {
    static func selectedWindowID(_ identity: MouseEventIdentity) -> CGWindowID? {
        // NSEvent documents windowNumber as the window associated with this event.
        let rawID = identity.windowNumber > 0 ? Int64(identity.windowNumber) : identity.handlingWindowID
        guard rawID > 0 else { return nil }
        return CGWindowID(exactly: rawID)
    }

    static func assess(_ identity: MouseEventIdentity) -> DesktopInteractionAssessment {
        let rawDetails = "Event window: \(identity.windowNumber) · Handling window: \(identity.handlingWindowID) · Target PID: \(identity.targetProcessID)"
        guard let windowID = selectedWindowID(identity) else {
            return DesktopInteractionAssessment(rejectionReason: "Click recipient is unavailable.", details: rawDetails)
        }
        let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]]
        guard let window = windows?.first(where: {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
        }), let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
            let layer = window[kCGWindowLayer as String] as? NSNumber else {
            return DesktopInteractionAssessment(rejectionReason: "The captured click's window metadata is unavailable.",
                details: "\(rawDetails) · Selected window: \(windowID)")
        }
        let bundleID = NSRunningApplication(processIdentifier: owner.int32Value)?.bundleIdentifier
        let reason = rejectionReason(identity, recipientBundleID: bundleID, recipientLayer: layer.intValue)
        let details = "\(rawDetails) · Selected window: \(windowID) · Owner: \(bundleID ?? "unknown") · Owner PID: \(owner.int64Value) · Layer: \(layer.intValue)"
        return DesktopInteractionAssessment(rejectionReason: reason, details: details)
    }

    static func rejectionReason(_ identity: MouseEventIdentity,
                                recipientBundleID: String?, recipientLayer: Int) -> String? {
        guard selectedWindowID(identity) != nil else { return "Click recipient is unavailable." }
        guard recipientBundleID == "com.apple.finder" else {
            return "The click belongs to another application; use the exposed desktop."
        }
        guard recipientLayer == Int(CGWindowLevelForKey(.desktopIconWindow)) else {
            return "The click belongs to a Finder window; use the exposed desktop."
        }
        return nil
    }
}
