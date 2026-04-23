import SwiftUI

/// Purely-visual icon for a given game. Used on:
///  - Game list cards
///  - The floating launcher button (when a specific game is selected)
///  - The ready / game-over panels
///
/// Each icon is rendered from vector primitives in the game's own accent
/// colour so they stay sharp at any size.
struct GameIcon: View {
    let kind: GameKind
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            switch kind {
            case .floatyBird:  BirdIcon(size: size)
            case .snake:       SnakeIcon(size: size)
            case .tetris:      TetrisIcon(size: size)
            case .minesweeper: MinesweeperIcon(size: size)
            case .sudoku:      SudokuIcon(size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The default launcher icon shown when no specific game is "remembered".
/// A classic d-pad + button gamepad silhouette.
struct GamepadIcon: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            // Rounded pill body
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.98, blue: 1.00),
                            Color(red: 0.80, green: 0.85, blue: 0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.92, height: size * 0.58)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.25), lineWidth: size * 0.04)
                )

            // D-pad
            ZStack {
                Rectangle()
                    .fill(Color(red: 0.30, green: 0.30, blue: 0.38))
                    .frame(width: size * 0.28, height: size * 0.08)
                Rectangle()
                    .fill(Color(red: 0.30, green: 0.30, blue: 0.38))
                    .frame(width: size * 0.08, height: size * 0.28)
            }
            .offset(x: -size * 0.22, y: 0)

            // Two action buttons
            HStack(spacing: size * 0.05) {
                Circle()
                    .fill(Color(red: 0.92, green: 0.38, blue: 0.44))
                    .frame(width: size * 0.12, height: size * 0.12)
                Circle()
                    .fill(Color(red: 0.40, green: 0.68, blue: 0.95))
                    .frame(width: size * 0.12, height: size * 0.12)
            }
            .offset(x: size * 0.22, y: 0)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: size * 0.1, y: size * 0.04)
    }
}

// MARK: - Per-game icons

private struct BirdIcon: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.96, blue: 0.66),
                            Color(red: 1.00, green: 0.82, blue: 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().strokeBorder(
                    Color(red: 0.82, green: 0.50, blue: 0.08),
                    lineWidth: size * 0.04))
            Ellipse()
                .fill(Color(red: 0.98, green: 0.68, blue: 0.12))
                .frame(width: size * 0.48, height: size * 0.26)
                .offset(x: -size * 0.08, y: size * 0.06)
            Circle().fill(Color.white)
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * 0.13, y: -size * 0.12)
            Circle().fill(Color.black)
                .frame(width: size * 0.10, height: size * 0.10)
                .offset(x: size * 0.16, y: -size * 0.12)
            IconTriangle()
                .fill(Color(red: 0.98, green: 0.50, blue: 0.10))
                .frame(width: size * 0.24, height: size * 0.18)
                .offset(x: size * 0.50, y: 0)
        }
    }
}

private struct SnakeIcon: View {
    let size: CGFloat

    var body: some View {
        // Classic game look: dark board with a chunky, clearly-segmented snake
        // shaped like an L, plus a food pellet. Reads as "snake" at a glance.
        let cell = size * 0.14
        let bg = Color(red: 0.08, green: 0.18, blue: 0.14)
        let body = Color(red: 0.38, green: 0.85, blue: 0.48)
        let bodyDark = Color(red: 0.22, green: 0.62, blue: 0.32)
        let apple = Color(red: 0.98, green: 0.34, blue: 0.30)

        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(bg)
                .frame(width: size * 0.9, height: size * 0.9)

            // Subtle grid dots (so it reads as a playfield)
            let dotGrid = size * 0.18
            Canvas { ctx, cg in
                let r: CGFloat = size * 0.014
                let step = dotGrid
                var y: CGFloat = step / 2
                while y < cg.height {
                    var x: CGFloat = step / 2
                    while x < cg.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                                       width: r * 2, height: r * 2)),
                                 with: .color(Color.white.opacity(0.05)))
                        x += step
                    }
                    y += step
                }
            }
            .frame(width: size * 0.9, height: size * 0.9)
            .allowsHitTesting(false)

            // Body segments (tail, body, body, body, head form an L).
            // Tail
            segment(color: bodyDark, cell: cell, dx: -2, dy: 1)
            segment(color: bodyDark, cell: cell, dx: -1, dy: 1)
            // Corner
            segment(color: body, cell: cell, dx: 0, dy: 1)
            segment(color: body, cell: cell, dx: 0, dy: 0)
            // Head
            SnakeHeadSegment(cell: cell, color: body)
                .frame(width: cell, height: cell)
                .offset(x: cell * 1, y: 0)

            // Apple
            ZStack {
                Circle().fill(apple)
                    .frame(width: cell * 0.75, height: cell * 0.75)
                Rectangle().fill(Color(red: 0.35, green: 0.55, blue: 0.25))
                    .frame(width: cell * 0.10, height: cell * 0.22)
                    .offset(y: -cell * 0.38)
            }
            .offset(x: cell * 2, y: -cell * 1)
        }
    }

    private func segment(color: Color, cell: CGFloat, dx: CGFloat, dy: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .frame(width: cell * 0.92, height: cell * 0.92)
            .offset(x: cell * dx, y: cell * dy)
    }
}

/// Rounded cube with two white-dot eyes to make the head unambiguous.
private struct SnakeHeadSegment: View {
    let cell: CGFloat
    let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .frame(width: cell * 0.96, height: cell * 0.96)
            // Eyes
            HStack(spacing: cell * 0.18) {
                Circle().fill(Color.white).frame(width: cell * 0.20, height: cell * 0.20)
                    .overlay(Circle().fill(Color.black).frame(width: cell * 0.09, height: cell * 0.09))
                Circle().fill(Color.white).frame(width: cell * 0.20, height: cell * 0.20)
                    .overlay(Circle().fill(Color.black).frame(width: cell * 0.09, height: cell * 0.09))
            }
            .offset(x: cell * 0.10, y: -cell * 0.10)
        }
    }
}

private struct TetrisIcon: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(red: 0.12, green: 0.14, blue: 0.26))
                .frame(width: size * 0.9, height: size * 0.9)
            // T-tetromino
            let cell = size * 0.18
            ZStack {
                // top row of 3
                HStack(spacing: 1) {
                    cellRect(cell: cell, color: Color(red: 0.60, green: 0.45, blue: 0.95))
                    cellRect(cell: cell, color: Color(red: 0.60, green: 0.45, blue: 0.95))
                    cellRect(cell: cell, color: Color(red: 0.60, green: 0.45, blue: 0.95))
                }
                .offset(y: -cell * 0.55)
                // center stem
                cellRect(cell: cell, color: Color(red: 0.60, green: 0.45, blue: 0.95))
                    .offset(y: cell * 0.45)
            }
        }
    }

    private func cellRect(cell: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous)
            .fill(color)
            .frame(width: cell, height: cell)
            .overlay(
                RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
    }
}

private struct MinesweeperIcon: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(red: 0.85, green: 0.85, blue: 0.88))
                .frame(width: size * 0.9, height: size * 0.9)
            Circle()
                .fill(Color(red: 0.14, green: 0.14, blue: 0.18))
                .frame(width: size * 0.5, height: size * 0.5)
            // Spikes
            ForEach(0..<8) { i in
                Capsule()
                    .fill(Color(red: 0.14, green: 0.14, blue: 0.18))
                    .frame(width: size * 0.08, height: size * 0.18)
                    .offset(y: -size * 0.32)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            // Highlight
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: -size * 0.10, y: -size * 0.10)
            // Fuse spark
            Circle()
                .fill(Color(red: 1.0, green: 0.45, blue: 0.25))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.22, y: -size * 0.24)
        }
    }
}

private struct SudokuIcon: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(red: 0.98, green: 0.97, blue: 1.00))
                .frame(width: size * 0.9, height: size * 0.9)
            // 3x3 grid lines
            let g = size * 0.66
            ForEach(0..<4) { i in
                let offset = CGFloat(i) * g / 3 - g / 2
                Rectangle()
                    .fill(Color(red: 0.30, green: 0.25, blue: 0.45))
                    .frame(width: g, height: i == 0 || i == 3 ? 2 : 1)
                    .offset(y: offset)
                Rectangle()
                    .fill(Color(red: 0.30, green: 0.25, blue: 0.45))
                    .frame(width: i == 0 || i == 3 ? 2 : 1, height: g)
                    .offset(x: offset)
            }
            // A single "9"
            Text("9")
                .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.60, green: 0.40, blue: 0.90))
        }
    }
}

private struct IconTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
