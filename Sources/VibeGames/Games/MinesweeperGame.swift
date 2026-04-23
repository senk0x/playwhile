import SwiftUI

/// Classic Minesweeper on a 9×9 board with 10 mines. The "score" we
/// persist as a personal best is the number of wins the player has racked
/// up. A small live timer and mine counter live in the top of the grid.
@MainActor
final class MinesweeperController: GameController {

    // Board is 9x9 with 10 mines — the classic "Beginner" layout that fits
    // comfortably inside the smaller default window.
    let cols = 9
    let rows = 9
    let mines = 10

    @Published var cells: [[Cell]] = []
    @Published var flagsPlaced: Int = 0
    @Published var elapsed: Int = 0

    private var timer: Timer?
    private var minesPlaced = false

    struct Cell: Identifiable, Equatable {
        let id = UUID()
        var isMine: Bool = false
        var isRevealed: Bool = false
        var isFlagged: Bool = false
        var adjacent: Int = 0
    }

    override var gameOverTitle: String { didWin ? "Solved!" : "Boom!" }

    private var didWin: Bool = false

    init() {
        super.init(kind: .minesweeper)
        newBoard()
    }

    override func makeBody() -> AnyView {
        AnyView(MinesweeperBoardView(controller: self))
    }

    override func togglePause() {
        if !hasStarted || isGameOver { return }
        if isPaused {
            isPaused = false
            startTimer()
        } else {
            isPaused = true
            stopTimer()
        }
    }

    override func pauseIfActive() {
        if hasStarted && !isGameOver && !isPaused { togglePause() }
    }

    override func teardown() {
        stopTimer()
    }

    // MARK: - Board setup

    func newBoard() {
        stopTimer()
        cells = Array(
            repeating: Array(repeating: Cell(), count: cols),
            count: rows
        )
        flagsPlaced = 0
        elapsed = 0
        minesPlaced = false
        didWin = false
        markReset()
    }

    /// Mines are placed only *after* the first click so the first reveal
    /// is guaranteed safe — the classic fair-first-click rule.
    private func placeMines(avoiding origin: (Int, Int)) {
        var positions = Set<Int>()
        while positions.count < mines {
            let r = Int.random(in: 0..<rows)
            let c = Int.random(in: 0..<cols)
            let avoid = abs(r - origin.0) <= 1 && abs(c - origin.1) <= 1
            if !avoid { positions.insert(r * cols + c) }
        }
        for p in positions {
            cells[p / cols][p % cols].isMine = true
        }
        for r in 0..<rows {
            for c in 0..<cols where !cells[r][c].isMine {
                cells[r][c].adjacent = neighbours(r, c).reduce(0) { a, n in
                    a + (cells[n.0][n.1].isMine ? 1 : 0)
                }
            }
        }
        minesPlaced = true
    }

    private func neighbours(_ r: Int, _ c: Int) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let rr = r + dr, cc = c + dc
                if rr >= 0 && rr < rows && cc >= 0 && cc < cols {
                    out.append((rr, cc))
                }
            }
        }
        return out
    }

    // MARK: - Actions

    func tap(r: Int, c: Int) {
        guard !isGameOver, !isPaused else { return }
        guard !cells[r][c].isRevealed, !cells[r][c].isFlagged else { return }
        if !hasStarted {
            markStart()
            startTimer()
        }
        if !minesPlaced {
            placeMines(avoiding: (r, c))
        }
        reveal(r: r, c: c)
        checkWin()
    }

    func flag(r: Int, c: Int) {
        guard !isGameOver, !isPaused else { return }
        guard !cells[r][c].isRevealed else { return }
        if !hasStarted {
            markStart()
            startTimer()
        }
        cells[r][c].isFlagged.toggle()
        flagsPlaced += cells[r][c].isFlagged ? 1 : -1
    }

    private func reveal(r: Int, c: Int) {
        if cells[r][c].isRevealed || cells[r][c].isFlagged { return }
        cells[r][c].isRevealed = true
        if cells[r][c].isMine {
            for r2 in 0..<rows {
                for c2 in 0..<cols where cells[r2][c2].isMine {
                    cells[r2][c2].isRevealed = true
                }
            }
            didWin = false
            stopTimer()
            markGameOver()
            return
        }
        if cells[r][c].adjacent == 0 {
            for n in neighbours(r, c) { reveal(r: n.0, c: n.1) }
        }
    }

    private func checkWin() {
        for r in 0..<rows {
            for c in 0..<cols {
                if !cells[r][c].isMine && !cells[r][c].isRevealed { return }
            }
        }
        // All non-mines revealed — win.
        didWin = true
        stopTimer()
        recordScore(bestScore + 1)    // persists as total wins
        markGameOver()
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - View

struct MinesweeperBoardView: View {
    @ObservedObject var controller: MinesweeperController

    var body: some View {
        ZStack {
            GameBackdrop(kind: .minesweeper)

            VStack(spacing: 12) {
                // Little status strip above the grid: mines left + timer.
                HStack {
                    StatusChip(systemName: "flag.fill",
                               text: "\(controller.mines - controller.flagsPlaced)")
                    Spacer()
                    StatusChip(systemName: "timer",
                               text: String(format: "%03d", controller.elapsed))
                }
                .padding(.horizontal, 14)
                .padding(.top, 76)

                GridView(controller: controller)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)

                Button {
                    controller.newBoard()
                } label: {
                    Label("New game", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.32)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
            }
        }
    }
}

private struct GridView: View {
    @ObservedObject var controller: MinesweeperController

    var body: some View {
        let cellSize = cellSize()
        VStack(spacing: 2) {
            ForEach(0..<controller.rows, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(0..<controller.cols, id: \.self) { c in
                        CellView(cell: controller.cells[r][c],
                                 size: cellSize,
                                 didWin: controller.isGameOver,
                                 onTap: { controller.tap(r: r, c: c) },
                                 onFlag: { controller.flag(r: r, c: c) })
                    }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    /// Grid is square; we aim for 34pt cells but squeeze a bit if the
    /// window is narrower than expected.
    private func cellSize() -> CGFloat { 32 }
}

private struct CellView: View {
    let cell: MinesweeperController.Cell
    let size: CGFloat
    let didWin: Bool
    let onTap: () -> Void
    let onFlag: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(cell.isRevealed ? revealedFill : hiddenFill)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.black.opacity(cell.isRevealed ? 0.22 : 0.10),
                              lineWidth: 1)

            if cell.isRevealed {
                if cell.isMine {
                    Image(systemName: "burst.fill")
                        .font(.system(size: size * 0.55, weight: .heavy))
                        .foregroundColor(Color(red: 0.25, green: 0.10, blue: 0.10))
                } else if cell.adjacent > 0 {
                    Text("\(cell.adjacent)")
                        .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
                        .foregroundColor(color(for: cell.adjacent))
                }
            } else if cell.isFlagged {
                Image(systemName: "flag.fill")
                    .font(.system(size: size * 0.55, weight: .heavy))
                    .foregroundColor(Color(red: 0.95, green: 0.35, blue: 0.30))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        // Right-click or control-click plants / removes a flag.
        .simultaneousGesture(
            TapGesture()
                .modifiers(.control)
                .onEnded { onFlag() }
        )
        .contextMenu {
            Button("Flag / Unflag") { onFlag() }
        }
    }

    private var hiddenFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.86, green: 0.78, blue: 0.68),
                Color(red: 0.72, green: 0.62, blue: 0.52)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var revealedFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.94, green: 0.90, blue: 0.84),
                Color(red: 0.88, green: 0.82, blue: 0.74)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func color(for n: Int) -> Color {
        switch n {
        case 1: return Color(red: 0.20, green: 0.30, blue: 0.85)
        case 2: return Color(red: 0.18, green: 0.55, blue: 0.22)
        case 3: return Color(red: 0.85, green: 0.25, blue: 0.20)
        case 4: return Color(red: 0.25, green: 0.18, blue: 0.60)
        case 5: return Color(red: 0.55, green: 0.18, blue: 0.20)
        case 6: return Color(red: 0.18, green: 0.55, blue: 0.60)
        case 7: return Color(red: 0.10, green: 0.10, blue: 0.12)
        default: return Color(red: 0.30, green: 0.30, blue: 0.32)
        }
    }
}

private struct StatusChip: View {
    let systemName: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
            Text(text)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.32)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
    }
}
