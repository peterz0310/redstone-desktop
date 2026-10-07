import AppKit
import CoreGraphics
import SpriteKit

private final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopWindowController: NSWindowController {
    init(frame: CGRect) {
        let window = DesktopWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.title = "Redstone Desktop Checker"
        // Public Core Graphics levels: above the desktop, below desktop icons.
        // This ordering is provisional until confirmed visually on the owner's Mac.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = SKView(frame: CGRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.preferredFramesPerSecond = 30
        window.contentView = view
        view.presentScene(DesktopScene(size: frame.size))
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("DesktopWindowController is created programmatically")
    }

    func enable() {
        window?.orderFrontRegardless()
    }

    func disable() {
        window?.orderOut(nil)
    }
}
