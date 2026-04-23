import SwiftUI

/// Every game the app ships today. The enum drives the list screen, the
/// floating-button icon, persistent best-score storage, and the colour
/// accents that keep each game visually distinct while sharing the same
/// overall chrome.
enum GameKind: String, CaseIterable, Identifiable, Hashable {
    case floatyBird
    case snake
    case tetris
    case minesweeper
    case sudoku

    var id: String { rawValue }

    var title: String {
        switch self {
        case .floatyBird:  return "Floaty Bird"
        case .snake:       return "Snake"
        case .tetris:      return "Tetris"
        case .minesweeper: return "Minesweeper"
        case .sudoku:      return "Sudoku"
        }
    }

    /// Short blurb shown on the list card under the title.
    var tagline: String {
        switch self {
        case .floatyBird:  return "Flap through pipes"
        case .snake:       return "Eat. Grow. Don't bite."
        case .tetris:      return "Stack and clear lines"
        case .minesweeper: return "Flag the mines"
        case .sudoku:      return "Fill the 9x9 grid"
        }
    }

    /// Preferred window content size. Kept compact by default so summoning
    /// a game doesn't cover the main content of the user's screen.
    var preferredSize: CGSize {
        switch self {
        case .floatyBird:  return CGSize(width: 400, height: 560)
        case .snake:       return CGSize(width: 400, height: 540)
        case .tetris:      return CGSize(width: 360, height: 600)
        case .minesweeper: return CGSize(width: 400, height: 520)
        case .sudoku:      return CGSize(width: 420, height: 560)
        }
    }

    /// `UserDefaults` key for the per-game personal best / primary stat.
    var bestScoreKey: String { "vibegames.\(rawValue).bestScore" }

    /// Label under the "Best" badge. Most games score "N", but Minesweeper
    /// and Sudoku track solves and therefore want a different noun.
    var bestLabel: String {
        switch self {
        case .minesweeper: return "Wins"
        case .sudoku:      return "Solves"
        default:           return "Best"
        }
    }

    /// Hint shown on the ready / game-over panels to remind the player of
    /// the primary controls.
    var controlsHint: String {
        switch self {
        case .floatyBird:  return "Space / click to flap"
        case .snake:       return "Arrow keys or WASD"
        case .tetris:      return "Arrow keys or WASD · Space drop"
        case .minesweeper: return "Click to reveal · ⌃click to flag"
        case .sudoku:      return "Click a cell · 1–9 to fill"
        }
    }

    /// Primary accent used for the list card and the per-game highlight.
    var accent: Color {
        switch self {
        case .floatyBird:  return Color(red: 1.00, green: 0.82, blue: 0.22)
        case .snake:       return Color(red: 0.38, green: 0.82, blue: 0.48)
        case .tetris:      return Color(red: 0.46, green: 0.58, blue: 1.00)
        case .minesweeper: return Color(red: 0.92, green: 0.40, blue: 0.35)
        case .sudoku:      return Color(red: 0.62, green: 0.48, blue: 0.95)
        }
    }

    /// Two-stop gradient used as the behind-content backdrop for each game.
    /// Kept cohesive across games — same "top darker, bottom warmer" feel.
    var background: [Color] {
        switch self {
        case .floatyBird:
            return [Color(red: 0.29, green: 0.50, blue: 0.94),
                    Color(red: 0.99, green: 0.82, blue: 0.75)]
        case .snake:
            return [Color(red: 0.10, green: 0.22, blue: 0.18),
                    Color(red: 0.18, green: 0.40, blue: 0.28)]
        case .tetris:
            return [Color(red: 0.12, green: 0.14, blue: 0.26),
                    Color(red: 0.24, green: 0.28, blue: 0.48)]
        case .minesweeper:
            return [Color(red: 0.18, green: 0.20, blue: 0.28),
                    Color(red: 0.35, green: 0.30, blue: 0.40)]
        case .sudoku:
            return [Color(red: 0.20, green: 0.18, blue: 0.32),
                    Color(red: 0.40, green: 0.30, blue: 0.55)]
        }
    }
}
