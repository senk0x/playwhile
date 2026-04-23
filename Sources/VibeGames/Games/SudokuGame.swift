import SwiftUI
import AppKit

/// Minimal but fully-playable Sudoku. We ship with a small rotating set
/// of hand-curated puzzles (keeps the file small; a proper puzzle
/// generator could come later). The persisted "best" is the number of
/// puzzles solved so far.
@MainActor
final class SudokuController: GameController {

    struct Cell {
        var value: Int = 0       // 0 = empty
        var given: Bool = false
        var invalid: Bool = false
    }

    @Published var grid: [[Cell]] = Array(
        repeating: Array(repeating: Cell(), count: 9),
        count: 9
    )
    @Published var selected: (row: Int, col: Int)? = nil
    @Published var elapsed: Int = 0
    @Published var mistakes: Int = 0

    private var timer: Timer?
    private var puzzleIndex: Int = 0
    private var keyMonitor: Any?

    override var gameOverTitle: String { "Solved!" }

    // Hard-coded puzzles (each 81 chars, 0 = blank). Not crypto-hard,
    // just a few to cycle through so the game is immediately playable.
    private let puzzles: [String] = [
        "530070000600195000098000060800060003400803001700020006060000280000419005000080079",
        "020600400500320007080000020600090003700040006300010004040000090900061008002008030",
        "100920000524010000000000070050008102000000000402700090060000000000030945000071006"
    ]

    init() {
        super.init(kind: .sudoku)
        loadPuzzle(index: 0)
    }

    override func makeBody() -> AnyView {
        AnyView(SudokuBoardView(controller: self))
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
        removeKeyMonitor()
    }

    // MARK: - Puzzle

    func newPuzzle() {
        puzzleIndex = (puzzleIndex + 1) % puzzles.count
        loadPuzzle(index: puzzleIndex)
    }

    private func loadPuzzle(index: Int) {
        let str = puzzles[index % puzzles.count]
        let digits = str.map { Int(String($0)) ?? 0 }
        grid = Array(repeating: Array(repeating: Cell(), count: 9), count: 9)
        for i in 0..<81 {
            let r = i / 9, c = i % 9
            let v = digits[i]
            grid[r][c] = Cell(value: v, given: v != 0, invalid: false)
        }
        selected = nil
        elapsed = 0
        mistakes = 0
        stopTimer()
        markReset()
    }

    // MARK: - Input

    func select(r: Int, c: Int) {
        guard !isGameOver, !isPaused else { return }
        if !hasStarted {
            markStart()
            startTimer()
            installKeyMonitor()
        }
        if grid[r][c].given { return }
        selected = (r, c)
    }

    func enter(digit: Int) {
        guard !isGameOver, !isPaused else { return }
        guard let (r, c) = selected, !grid[r][c].given else { return }
        if digit == 0 {
            grid[r][c].value = 0
            grid[r][c].invalid = false
            revalidate()
            return
        }
        grid[r][c].value = digit
        let valid = isValidPlacement(r: r, c: c, value: digit)
        grid[r][c].invalid = !valid
        if !valid {
            mistakes += 1
        }
        revalidate()
        checkSolved()
    }

    private func isValidPlacement(r: Int, c: Int, value: Int) -> Bool {
        for i in 0..<9 {
            if i != c && grid[r][i].value == value { return false }
            if i != r && grid[i][c].value == value { return false }
        }
        let br = (r / 3) * 3
        let bc = (c / 3) * 3
        for rr in br..<br + 3 {
            for cc in bc..<bc + 3 where rr != r || cc != c {
                if grid[rr][cc].value == value { return false }
            }
        }
        return true
    }

    /// Recompute the invalid flag across the board (needed after a delete
    /// since a previously-clashing pair might now be fine).
    private func revalidate() {
        for r in 0..<9 {
            for c in 0..<9 {
                let v = grid[r][c].value
                grid[r][c].invalid = v != 0 && !isValidPlacement(r: r, c: c, value: v)
            }
        }
    }

    private func checkSolved() {
        for r in 0..<9 {
            for c in 0..<9 {
                if grid[r][c].value == 0 || grid[r][c].invalid { return }
            }
        }
        stopTimer()
        recordScore(bestScore + 1)
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

    // MARK: - Keyboard

    private func installKeyMonitor() {
        if keyMonitor != nil { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handleKey(event) { return nil }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 35 || event.keyCode == 53 {
            Task { @MainActor in self.togglePause() }
            return true
        }
        // Digit keys
        if let chars = event.charactersIgnoringModifiers,
           let digit = Int(chars), (1...9).contains(digit) {
            Task { @MainActor in self.enter(digit: digit) }
            return true
        }
        // Delete / backspace
        if event.keyCode == 51 || event.keyCode == 117 {
            Task { @MainActor in self.enter(digit: 0) }
            return true
        }
        // Arrow keys to move selection.
        if let sel = selected {
            var dr = 0, dc = 0
            switch event.keyCode {
            case 126: dr = -1
            case 125: dr = 1
            case 123: dc = -1
            case 124: dc = 1
            default: return false
            }
            let nr = max(0, min(8, sel.row + dr))
            let nc = max(0, min(8, sel.col + dc))
            Task { @MainActor in self.selected = (nr, nc) }
            return true
        }
        return false
    }
}

// MARK: - View

struct SudokuBoardView: View {
    @ObservedObject var controller: SudokuController

    var body: some View {
        ZStack {
            GameBackdrop(kind: .sudoku)

            VStack(spacing: 10) {
                HStack {
                    StatusChip(systemName: "xmark.circle.fill",
                               text: "\(controller.mistakes)")
                    Spacer()
                    StatusChip(systemName: "timer",
                               text: String(format: "%03d", controller.elapsed))
                }
                .padding(.horizontal, 14)
                .padding(.top, 76)

                Grid(controller: controller)
                    .padding(.horizontal, 14)

                Keypad(controller: controller)
                    .padding(.horizontal, 14)

                Button {
                    controller.newPuzzle()
                } label: {
                    Label("New puzzle", systemImage: "shuffle")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.32)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
        }
    }

    private struct Grid: View {
        @ObservedObject var controller: SudokuController

        var body: some View {
            VStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { c in
                            CellView(cell: controller.grid[r][c],
                                     isSelected: controller.selected?.row == r
                                        && controller.selected?.col == c,
                                     r: r, c: c)
                                .onTapGesture { controller.select(r: r, c: c) }
                        }
                    }
                }
            }
            .background(Color(red: 0.08, green: 0.06, blue: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private struct CellView: View {
        let cell: SudokuController.Cell
        let isSelected: Bool
        let r: Int
        let c: Int

        private let size: CGFloat = 34

        var body: some View {
            ZStack {
                Rectangle()
                    .fill(background)
                if cell.value > 0 {
                    Text("\(cell.value)")
                        .font(.system(size: 18, weight: cell.given ? .black : .semibold,
                                      design: .rounded))
                        .foregroundColor(
                            cell.invalid
                                ? Color(red: 1.0, green: 0.48, blue: 0.40)
                                : cell.given
                                    ? .white
                                    : Color(red: 0.72, green: 0.88, blue: 1.00)
                        )
                }
            }
            .frame(width: size, height: size)
            .overlay(borderOverlay)
        }

        private var background: Color {
            if isSelected {
                return Color(red: 0.38, green: 0.32, blue: 0.58)
            }
            // 3x3 alternating shade.
            let boxR = r / 3, boxC = c / 3
            return (boxR + boxC).isMultiple(of: 2)
                ? Color(red: 0.14, green: 0.12, blue: 0.24)
                : Color(red: 0.20, green: 0.16, blue: 0.30)
        }

        @ViewBuilder
        private var borderOverlay: some View {
            // Thick lines between 3x3 boxes, thin elsewhere.
            Rectangle()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
            if c % 3 == 2 && c != 8 {
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 1.5)
                    .offset(x: size / 2 - 0.5)
            }
            if r % 3 == 2 && r != 8 {
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(height: 1.5)
                    .offset(y: size / 2 - 0.5)
            }
        }
    }

    private struct Keypad: View {
        @ObservedObject var controller: SudokuController

        var body: some View {
            HStack(spacing: 6) {
                ForEach(1...9, id: \.self) { d in
                    Button { controller.enter(digit: d) } label: {
                        Text("\(d)")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Capsule().fill(Color.black.opacity(0.32)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Button { controller.enter(digit: 0) } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Capsule().fill(Color.black.opacity(0.32)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
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
}
