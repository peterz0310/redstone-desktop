import AppKit

/// Accept only the captured event's Finder desktop recipient, never unrelated bounds.
@MainActor
enum DesktopInteractionGate {
    static func rejectionReason(_ identity: MouseEventIdentity) -> String? {
        let rawID = identity.handlingWindowID > 0 ? identity.handlingWindowID : Int64(identity.windowNumber)
        guard rawID > 0, let windowID = CGWindowID(exactly: rawID) else {
            return "Click recipient is unavailable (event window \(identity.windowNumber), handling window \(identity.handlingWindowID), target PID \(identity.targetProcessID))."
        }
        let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]]
        guard let window = windows?.first(where: {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
        }), let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
            let layer = window[kCGWindowLayer as String] as? NSNumber else {
            return "The captured click's window metadata is unavailable (window \(windowID))."
        }
        let bundleID = NSRunningApplication(processIdentifier: owner.int32Value)?.bundleIdentifier
        return rejectionReason(identity, recipientOwnerPID: owner.int64Value,
                               recipientBundleID: bundleID, recipientLayer: layer.intValue)
    }

    static func rejectionReason(_ identity: MouseEventIdentity, recipientOwnerPID: Int64,
                                recipientBundleID: String?, recipientLayer: Int) -> String? {
        guard identity.handlingWindowID > 0 || identity.windowNumber > 0 else {
            return "Click recipient is unavailable."
        }
        if identity.targetProcessID > 0, identity.targetProcessID != recipientOwnerPID {
            return "Click recipient and target process disagree; nothing activated."
        }
        guard recipientBundleID == "com.apple.finder" else {
            return "The click belongs to another application; use the exposed desktop."
        }
        guard recipientLayer == Int(CGWindowLevelForKey(.desktopIconWindow)) else {
            return "The click belongs to a Finder window; use the exposed desktop."
        }
        return nil
    }
}
