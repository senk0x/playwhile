import AppKit
import SwiftUI

/// Hosts the always-on-top circular floating button in a borderless, transparent
/// `NSPanel`. An `NSPanel` (rather than a plain `NSWindow`) is used because:
///
///  - With `.nonactivatingPanel`, clicks do not activate our app, so focus
///    stays with whichever app the user is currently in (Cursor, Chrome, ...).
///  - It can be assigned a high window level and participate across Spaces.
///
/// Window-layering logic:
///  - `level = .statusBar` (higher than `.floating`) keeps the button above
///    virtually every normal application window, including other "floating"
///    panels like Xcode's inspectors.
///  - `collectionBehavior` includes `.canJoinAllSpaces` + `.fullScreenAuxiliary`
///    so the button stays visible when switching Spaces or when another app
///    enters full-screen mode.
///
/// Dragging:
///  - Implemented on a bespoke `NSView` subclass at the AppKit layer rather
///    than through a SwiftUI `DragGesture`. AppKit `mouseDragged` events
///    stream in one-per-frame with no intermediate processing, so following
///    the cursor is visibly crisper than the previous SwiftUI-translated
///    deltas.
final class FloatingButtonWindowController: NSWindowController {

    /// Invoked when the user performs a click (not a drag) on the button.
    var onButtonTapped: (() -> Void)?

    private let buttonSize: CGFloat = 64
    private let panelSize = NSSize(width: 84, height: 84)
    private let buttonState = FloatingButtonState()

    convenience init() {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 84, height: 84)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Transparent background so only the SwiftUI circle is visible.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        // Always-on-top: .statusBar sits above .floating and most modal panels.
        panel.level = .statusBar

        // Stay visible across Spaces and when other apps enter full-screen.
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false // we handle drags manually
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false

        self.init(window: panel)

        // Default position: bottom-left of the main screen, with a small
        // inset so the button breathes a little from the menu bar / dock.
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let inset: CGFloat = 24
            let origin = NSPoint(
                x: visible.minX + inset,
                y: visible.minY + inset
            )
            panel.setFrameOrigin(origin)
        }

        // Build a drag-aware container that hosts the SwiftUI view. The
        // container owns the mouse events; the SwiftUI view is purely visual.
        let container = DraggableButtonContainer()
        container.frame = NSRect(origin: .zero, size: panelSize)
        container.onTap = { [weak self] in self?.onButtonTapped?() }
        container.onPressChanged = { [weak self] pressed in
            self?.buttonState.isPressed = pressed
        }

        let swiftUIView = FloatingButtonView(diameter: buttonSize, state: buttonState)
        let hosting = NSHostingView(rootView: swiftUIView)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        // Prevent SwiftUI from trying to handle clicks — the container does.
        hosting.wantsLayer = true
        container.addSubview(hosting)

        panel.contentView = container
    }

    override func showWindow(_ sender: Any?) {
        // orderFrontRegardless lets the window show without activating the app.
        window?.orderFrontRegardless()
    }

    /// Current on-screen frame of the button panel. Useful for callers (e.g.
    /// the AppDelegate) that want to position other windows relative to it.
    var buttonFrame: NSRect {
        window?.frame ?? .zero
    }

    /// Switch the foreground icon between the generic gamepad (`nil`) and
    /// a specific game — driven by the `AppDelegate` as the user plays /
    /// minimises / closes games.
    func setIcon(for kind: GameKind?) {
        buttonState.kind = kind
    }
}

/// Subclass that explicitly opts OUT of becoming key or main so clicking
/// the button never steals focus from whichever app the user is in.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - AppKit-level drag container

/// An `NSView` subclass that intercepts every mouse event inside the floating
/// panel. It owns the tap-vs-drag logic so we don't pay the latency cost of
/// SwiftUI gesture coalescing:
///
/// - `mouseDown` snapshots the cursor's screen position and the window's
///   current origin.
/// - `mouseDragged` reads `NSEvent.mouseLocation` (global screen coordinates)
///   and applies the exact screen delta to the window via
///   `setFrameOrigin(_:)`. Because we drive the window from the true cursor
///   position every event, the button glues to the pointer with zero drift.
/// - `mouseUp` fires `onTap` iff total travel stayed inside a tiny slop
///   radius, preserving the original click-vs-drag disambiguation.
private final class DraggableButtonContainer: NSView {
    var onTap: (() -> Void)?
    var onPressChanged: ((Bool) -> Void)?

    private let tapSlop: CGFloat = 4

    private var didDrag = false
    private var dragStartScreenPoint: NSPoint = .zero
    private var windowStartOrigin: NSPoint = .zero

    // Route every click here, not to the SwiftUI subview.
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    // Receive clicks even when the app is in the background (our panel is a
    // non-activating, always-visible helper).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        didDrag = false
        dragStartScreenPoint = NSEvent.mouseLocation
        windowStartOrigin = window.frame.origin
        onPressChanged?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartScreenPoint.x
        let dy = current.y - dragStartScreenPoint.y
        if !didDrag, hypot(dx, dy) > tapSlop {
            didDrag = true
        }
        if didDrag {
            // Drive the window from the absolute pointer delta — no
            // accumulated rounding, no gesture-coalescing lag.
            window.setFrameOrigin(NSPoint(
                x: windowStartOrigin.x + dx,
                y: windowStartOrigin.y + dy
            ))
        }
    }

    override func mouseUp(with event: NSEvent) {
        onPressChanged?(false)
        if !didDrag {
            onTap?()
        }
    }
}
