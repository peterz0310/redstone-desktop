import AppKit
import CoreGraphics
import SpriteKit

private final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopWindowController: NSWindowController {
    let scene: DesktopScene

    init(screen: ScreenDescriptor, mapper: CoordinateMapper) {
        let frame = screen.frame
        scene = DesktopScene(screen: screen, mapper: mapper)
        let window = DesktopWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.title = "Redstone Desktop Checker"
        // Public Core Graphics levels: above the desktop, below desktop icons.
        // The owner confirmed this ordering in the Slice 2 manual check.
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
        view.presentScene(scene)
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
