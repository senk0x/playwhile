import AppKit
import SwiftUI
import SpriteKit

/// Hosts the arcade in a standard, resizable `NSWindow`. The window can
/// display either the game list or a single active game; transitions
/// happen in-place without recreating the window.
///
/// Window-layering:
///  - `.titled, .closable, .resizable, .miniaturizable` so it behaves like
///    any ordinary app window.
///  - Level is `.normal` by default, promoted to `.floating` while the
///    window is key, so it stays above sibling windows while the user is
///    actually playing.
///  - Does NOT activate the app on open — `AppDelegate` calls
///    `orderFrontRegardless`, so clicking the launcher never steals
///    focus from the user's current app.
///
/// Pause semantics:
///  - `windowWillMiniaturize` → one-way-pause the current game.
final class GameWindowController: NSWindowController, NSWindowDelegate {

    /// What's currently on-screen inside the window. We read this from
    /// `AppDelegate` so the floating button's icon always matches what
    /// clicking it would restore.
    private(set) var currentScreen: Screen = .list

    enum Screen: Equatable {
        case list
        case game(GameKind)
    }

    /// The live game controller, if we're on the `.game` screen. Kept
    /// around so miniaturise can pause it and the list returns to the
    /// previous game's prior state would re-use.
    private(set) var activeController: GameController?

    /// Live best scores per kind, so the list card shows the right
    /// number without having to hit UserDefaults on every rebuild.
    private var bestScores: [GameKind: Int] {
        Dictionary(uniqueKeysWithValues: GameKind.allCases.map { kind in
            (kind, UserDefaults.standard.integer(forKey: kind.bestScoreKey))
        })
    }

    private var host: NSHostingView<AnyView>!

    init() {
        let contentSize = NSSize(width: 400, height: 560)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PlayWhile"
        window.minSize = NSSize(width: 320, height: 420)
        window.isReleasedWhenClosed = false

        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.level = .normal

        super.init(window: window)
        window.delegate = self

        host = NSHostingView(rootView: AnyView(EmptyView()))
        host.autoresizingMask = [.width, .height]
        window.contentView = host

        showList()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Screen routing

    /// Swap to the list, tearing down any active game first.
    func showList() {
        activeController?.teardown()
        activeController = nil
        currentScreen = .list
        window?.title = "PlayWhile"
        host.rootView = AnyView(
            GameListView(bestScores: bestScores) { [weak self] kind in
                self?.show(kind: kind)
            }
        )
        resizeForCurrentScreen()
        onScreenChanged?()
    }

    /// Open (or re-open) a specific game.
    func show(kind: GameKind) {
        if case .game(let existing) = currentScreen,
           existing == kind,
           activeController != nil {
            return
        }
        activeController?.teardown()
        let controller = makeController(for: kind)
        activeController = controller
        currentScreen = .game(kind)
        window?.title = kind.title

        host.rootView = AnyView(
            GameChrome(controller: controller,
                       onBack: { [weak self] in self?.showList() }) {
                controller.makeBody()
            }
        )
        resizeForCurrentScreen()
        onScreenChanged?()
    }

    /// Callback fired whenever the visible screen changes. `AppDelegate`
    /// uses this to keep the floating-button icon in sync.
    var onScreenChanged: (() -> Void)?

    private func makeController(for kind: GameKind) -> GameController {
        switch kind {
        case .floatyBird:  return FloatyBirdController()
        case .snake:       return SnakeController()
        case .tetris:      return TetrisController()
        case .minesweeper: return MinesweeperController()
        case .sudoku:      return SudokuController()
        }
    }

    /// Ensure the window's content size matches the current screen's
    /// preferred dimensions, but leave it untouched if the user has
    /// already resized it to something they like.
    private func resizeForCurrentScreen() {
        guard let window = window else { return }
        let preferred: CGSize
        switch currentScreen {
        case .list: preferred = CGSize(width: 400, height: 560)
        case .game(let kind): preferred = kind.preferredSize
        }
        // Only resize if the current size isn't already close to a game-
        // appropriate value — prevents the window from jumping around if
        // the user has resized it manually.
        let current = window.frame.size
        if abs(current.width - preferred.width) < 40,
           abs(current.height - preferred.height) < 40 {
            return
        }
        let origin = window.frame.origin
        let frame = NSRect(origin: origin, size: preferred)
        window.setContentSize(preferred)
        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Placement / appearance

    /// Park the window so its bottom-left sits just above the given
    /// reference rect, clamped to the visible screen.
    func positionAbove(_ reference: NSRect, gap: CGFloat = 12) {
        guard let window = window else { return }
        let size = window.frame.size

        var origin = NSPoint(
            x: reference.minX,
            y: reference.maxY + gap
        )

        let screen = window.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(reference) })
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = max(visible.minX + 8,
                           min(origin.x, visible.maxX - size.width - 8))
            origin.y = max(visible.minY + 8,
                           min(origin.y, visible.maxY - size.height - 8))
        }
        window.setFrameOrigin(origin)
    }

    /// Show the window with a subtle fade-and-rise animation.
    func animateShow() {
        guard let window = window else { return }
        let finalFrame = window.frame
        let startFrame = NSRect(
            x: finalFrame.origin.x,
            y: finalFrame.origin.y - 24,
            width: finalFrame.size.width,
            height: finalFrame.size.height
        )
        window.alphaValue = 0
        window.setFrame(startFrame, display: false)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.2, 0.9, 0.25, 1.0
            )
            ctx.allowsImplicitAnimation = true
            window.animator().alphaValue = 1.0
            window.animator().setFrame(finalFrame, display: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        window?.level = .floating
    }

    func windowDidResignKey(_ notification: Notification) {
        window?.level = .normal
    }

    /// Auto-pause whatever game is running before AppKit shrinks us into
    /// the Dock. Using `pauseIfActive` means idle / already-paused /
    /// game-over states are left alone.
    func windowWillMiniaturize(_ notification: Notification) {
        activeController?.pauseIfActive()
    }

    func windowWillClose(_ notification: Notification) {
        activeController?.teardown()
        activeController = nil
    }
}
