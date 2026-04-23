import SwiftUI

/// Abstract base for every game. Centralises the five things the shared
/// HUD and window chrome need to know about *any* game:
///
///  1. `hasStarted` / `isPaused` / `isGameOver` — drive the centre panels.
///  2. `score` / `bestScore` / `isNewBest` — drive the top-bar and the
///     "best" badge, plus persistence.
///  3. The visual body of the game (`makeBody()`).
///  4. A one-way "please pause if still running" hook for window-level
///     triggers (miniaturise, menu changes).
///  5. A `reset()` hook the list screen calls when the user switches back.
///
/// Concrete games only override what they need; most state mutations
/// flow through the base `recordScore` / `markGameOver` helpers so
/// every game persists high scores identically.
@MainActor
class GameController: ObservableObject, Identifiable {
    let kind: GameKind

    @Published var score: Int = 0
    @Published var bestScore: Int = 0
    @Published var isGameOver: Bool = false
    @Published var hasStarted: Bool = false
    @Published var isPaused: Bool = false
    @Published var isNewBest: Bool = false

    /// Optional custom text on the center ready / game-over panel. Most
    /// games use the defaults from `GameKind`, but some (Sudoku) override
    /// to say things like "Solved!" instead of "Game Over".
    var gameOverTitle: String { "Game Over" }

    init(kind: GameKind) {
        self.kind = kind
        self.bestScore = UserDefaults.standard.integer(forKey: kind.bestScoreKey)
    }

    // MARK: - Subclass API

    /// The main game content, excluding HUD/panels. Can be a SpriteKit
    /// `SpriteView`, a SwiftUI canvas, whatever the game needs.
    func makeBody() -> AnyView { AnyView(Color.clear) }

    /// Toggle pause ↔ resume. Only meaningful mid-run; idle / game-over
    /// states must be no-ops.
    func togglePause() {}

    /// One-way pause triggered by window miniaturise. MUST only pause if
    /// actively playing — never un-pause.
    func pauseIfActive() {
        if !isPaused && hasStarted && !isGameOver {
            togglePause()
        }
    }

    /// Called when the user leaves the game (back to list). Override to
    /// stop timers / tear down listeners that survive view disappearance.
    func teardown() {}

    // MARK: - Shared helpers (subclasses call these)

    func recordScore(_ value: Int) {
        score = value
        if value > bestScore {
            bestScore = value
            isNewBest = true
            UserDefaults.standard.set(value, forKey: kind.bestScoreKey)
        }
    }

    func markStart() {
        hasStarted = true
        isGameOver = false
        isPaused = false
        isNewBest = false
    }

    func markGameOver() {
        isGameOver = true
        isPaused = false
    }

    func markReset() {
        score = 0
        hasStarted = false
        isGameOver = false
        isPaused = false
        isNewBest = false
    }
}
