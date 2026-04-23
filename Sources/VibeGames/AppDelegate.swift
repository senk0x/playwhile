import AppKit

/// Top-level coordinator. Owns the two window controllers:
///  - `floatingButtonController`: a small always-on-top draggable circular button.
///  - `gameWindowController`: a resizable window that hosts the arcade.
///
/// The floating button is created at launch and kept alive for the app's
/// lifetime. The game window is created lazily and can be minimised /
/// restored repeatedly.
///
/// Launcher behaviour:
///  1. First click ever: open the game list.
///  2. User picks game `X` from the list: opens `X`, remembers `X`.
///  3. Button icon subsequently mirrors whatever the window was last
///     showing — `X`'s icon while a game is active or minimised; the
///     gamepad icon if the user explicitly went back to the list.
///  4. Clicking again:
///     - miniaturise if visible,
///     - deminiaturise if minimised,
///     - otherwise re-open the last screen (so a user who was playing
///       Tetris and closed the window lands straight back in Tetris).
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var floatingButtonController: FloatingButtonWindowController?
    private var gameWindowController: GameWindowController?

    /// What clicking the button should restore to. Persisted across
    /// launches so "open the thing I was last doing" works after a quit.
    private var lastScreen: GameWindowController.Screen = .list {
        didSet { persistLastScreen() }
    }

    private let lastScreenKey = "vibegames.app.lastScreen"

    func applicationDidFinishLaunching(_ notification: Notification) {
        lastScreen = loadLastScreen()

        let controller = FloatingButtonWindowController()
        controller.onButtonTapped = { [weak self] in
            self?.toggleGameWindow()
        }
        controller.showWindow(nil)
        floatingButtonController = controller

        refreshButtonIcon()
    }

    // MARK: - Toggle logic

    private func toggleGameWindow() {
        if let controller = gameWindowController, let window = controller.window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
                window.orderFrontRegardless()
                return
            }
            if window.isVisible {
                // Only close if our app is active (window is truly in front).
                // Otherwise, the window is behind other apps — bring it forward.
                if NSApp.isActive {
                    window.orderOut(nil)
                } else {
                    window.orderFrontRegardless()
                }
                return
            }
        }
        openLastScreen()
    }

    private func openLastScreen() {
        let controller = gameWindowController ?? makeGameWindowController()
        gameWindowController = controller

        switch lastScreen {
        case .list:             controller.showList()
        case .game(let kind):   controller.show(kind: kind)
        }

        if let buttonFrame = floatingButtonController?.buttonFrame {
            controller.positionAbove(buttonFrame)
        } else if let window = controller.window {
            window.center()
        }

        controller.animateShow()
    }

    private func makeGameWindowController() -> GameWindowController {
        let c = GameWindowController()
        c.onScreenChanged = { [weak self, weak c] in
            guard let self = self, let c = c else { return }
            self.lastScreen = c.currentScreen
            self.refreshButtonIcon()
        }
        return c
    }

    // MARK: - Button icon

    /// Pushes the current "next screen" down to the floating button so
    /// its icon always matches what clicking it would reveal.
    private func refreshButtonIcon() {
        switch lastScreen {
        case .list:           floatingButtonController?.setIcon(for: nil)
        case .game(let kind): floatingButtonController?.setIcon(for: kind)
        }
    }

    // MARK: - Persistence for lastScreen

    private func persistLastScreen() {
        let token: String
        switch lastScreen {
        case .list:              token = "list"
        case .game(let kind):    token = "game:\(kind.rawValue)"
        }
        UserDefaults.standard.set(token, forKey: lastScreenKey)
    }

    private func loadLastScreen() -> GameWindowController.Screen {
        let raw = UserDefaults.standard.string(forKey: lastScreenKey) ?? "list"
        if raw == "list" { return .list }
        if raw.hasPrefix("game:") {
            let rest = String(raw.dropFirst("game:".count))
            if let kind = GameKind(rawValue: rest) { return .game(kind) }
        }
        return .list
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The floating button window should keep the app alive even when
        // the game window is closed.
        return false
    }
}
