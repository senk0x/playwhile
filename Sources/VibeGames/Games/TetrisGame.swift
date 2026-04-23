import SwiftUI
import SpriteKit
import AppKit

/// Classic Tetris on a 10 × 20 grid. Pieces fall at a rate that ramps up
/// with the level. Clearing N lines in one drop awards the usual bonus
/// progression (100 / 300 / 500 / 800).
final class TetrisScene: SKScene {

    // MARK: - Callbacks
    var onScoreChanged: ((Int) -> Void)?
    var onStart: (() -> Void)?
    var onGameOver: (() -> Void)?
    var onReset: (() -> Void)?
    var onPauseChanged: ((Bool) -> Void)?

    // MARK: - Tunables
    private let cols = 10
    private let rows = 20
    private var cellSize: CGFloat = 24
    private var boardOrigin: CGPoint = .zero

    // MARK: - Board state
    /// `board[r][c]` is nil for empty or the piece kind that locked there.
    /// Row 0 is the bottom; `rows - 1` is the top.
    private var board: [[PieceKind?]] = []
    private var current: ActivePiece?
    private var nextKind: PieceKind = .T

    // Simulation
    private var fallInterval: TimeInterval = 0.7
    private var accumulator: TimeInterval = 0
    private var lastUpdate: TimeInterval?

    private var linesCleared: Int = 0
    private var level: Int = 1
    private var score: Int = 0

    private enum State { case idle, playing, paused, gameOver }
    private var state: State = .idle

    // Nodes
    private var boardBackground: SKNode!
    private var stackLayer: SKNode!
    private var activeLayer: SKNode!
    private var keyMonitor: Any?

    // MARK: - Piece definitions
    enum PieceKind: Int, CaseIterable {
        case I, O, T, S, Z, L, J

        var color: NSColor {
            switch self {
            case .I: return NSColor(calibratedRed: 0.40, green: 0.85, blue: 0.95, alpha: 1)
            case .O: return NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.30, alpha: 1)
            case .T: return NSColor(calibratedRed: 0.70, green: 0.45, blue: 0.95, alpha: 1)
            case .S: return NSColor(calibratedRed: 0.45, green: 0.88, blue: 0.50, alpha: 1)
            case .Z: return NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.48, alpha: 1)
            case .L: return NSColor(calibratedRed: 0.98, green: 0.65, blue: 0.25, alpha: 1)
            case .J: return NSColor(calibratedRed: 0.40, green: 0.58, blue: 0.98, alpha: 1)
            }
        }

        /// Cell offsets (x, y) for rotation state 0. We'll rotate in code
        /// so every piece only needs its base shape here.
        var baseCells: [(Int, Int)] {
            switch self {
            case .I: return [(0,0), (1,0), (2,0), (3,0)]
            case .O: return [(0,0), (1,0), (0,1), (1,1)]
            case .T: return [(0,0), (1,0), (2,0), (1,1)]
            case .S: return [(0,0), (1,0), (1,1), (2,1)]
            case .Z: return [(1,0), (2,0), (0,1), (1,1)]
            case .L: return [(0,0), (1,0), (2,0), (2,1)]
            case .J: return [(0,0), (1,0), (2,0), (0,1)]
            }
        }
    }

    struct ActivePiece {
        var kind: PieceKind
        var cells: [(Int, Int)]        // current-rotation offsets
        var origin: (x: Int, y: Int)   // bottom-left anchor in board coords
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.18, alpha: 1.0)

        boardBackground = SKNode(); addChild(boardBackground)
        stackLayer = SKNode();      addChild(stackLayer)
        activeLayer = SKNode();     addChild(activeLayer)

        layoutBoard()
        resetGame()
        installKeyMonitor()
    }

    override func willMove(from view: SKView) {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard boardBackground != nil else { return }
        layoutBoard()
        redrawStack()
        redrawActive()
    }

    // MARK: - Layout

    private func layoutBoard() {
        let topMargin: CGFloat = 70
        let availableW = size.width - 20
        let availableH = size.height - topMargin - 20
        cellSize = max(10, min(availableW / CGFloat(cols), availableH / CGFloat(rows)))
        let w = cellSize * CGFloat(cols)
        let h = cellSize * CGFloat(rows)
        boardOrigin = CGPoint(x: (size.width - w) / 2, y: 12)

        boardBackground.removeAllChildren()
        let outer = SKShapeNode(rect: CGRect(x: boardOrigin.x - 2,
                                              y: boardOrigin.y - 2,
                                              width: w + 4, height: h + 4),
                                 cornerRadius: 6)
        outer.fillColor = NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.26, alpha: 1)
        outer.strokeColor = NSColor.white.withAlphaComponent(0.18)
        outer.lineWidth = 1.5
        boardBackground.addChild(outer)

        // Faint grid
        for c in 1..<cols {
            let x = boardOrigin.x + CGFloat(c) * cellSize
            let line = SKShapeNode(rect: CGRect(x: x, y: boardOrigin.y,
                                                  width: 1, height: h))
            line.fillColor = NSColor.white.withAlphaComponent(0.05)
            line.strokeColor = .clear
            boardBackground.addChild(line)
        }
    }

    private func cellPoint(col: Int, row: Int) -> CGPoint {
        CGPoint(x: boardOrigin.x + CGFloat(col) * cellSize,
                y: boardOrigin.y + CGFloat(row) * cellSize)
    }

    // MARK: - Game lifecycle

    private func resetGame() {
        board = Array(repeating: Array(repeating: nil, count: cols), count: rows)
        current = nil
        score = 0
        linesCleared = 0
        level = 1
        fallInterval = 0.7
        accumulator = 0
        lastUpdate = nil
        state = .idle

        nextKind = PieceKind.allCases.randomElement()!
        onScoreChanged?(0)
        onReset?()

        redrawStack()
        redrawActive()
    }

    private func beginPlay() {
        guard state != .playing else { return }
        state = .playing
        spawnNextPiece()
        onStart?()
    }

    private func spawnNextPiece() {
        let kind = nextKind
        nextKind = PieceKind.allCases.randomElement()!
        let cells = kind.baseCells
        // Spawn roughly centered on the top two rows.
        let widthExtent = (cells.map { $0.0 }.max() ?? 0) + 1
        let startX = (cols - widthExtent) / 2
        let startY = rows - 2
        let piece = ActivePiece(kind: kind, cells: cells,
                                origin: (startX, startY))

        if !pieceFits(piece) {
            // Can't place — game over.
            current = nil
            gameOverFinish()
            return
        }
        current = piece
        redrawActive()
    }

    private func gameOverFinish() {
        state = .gameOver
        onGameOver?()
        // Flash a losing red tint.
        let flash = SKSpriteNode(color: NSColor(calibratedRed: 1, green: 0.35, blue: 0.35, alpha: 0.35),
                                  size: size)
        flash.anchorPoint = .zero
        flash.zPosition = 900
        addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    // MARK: - Piece mechanics

    private func pieceFits(_ piece: ActivePiece) -> Bool {
        for (dx, dy) in piece.cells {
            let x = piece.origin.x + dx
            let y = piece.origin.y + dy
            if x < 0 || x >= cols { return false }
            if y < 0 { return false }
            if y < rows, board[y][x] != nil { return false }
        }
        return true
    }

    /// Rotate cells 90° clockwise within their bounding box.
    private func rotated(_ cells: [(Int, Int)]) -> [(Int, Int)] {
        let maxY = cells.map { $0.1 }.max() ?? 0
        return cells.map { (dx, dy) in (dy, maxY - dx) }
    }

    private func tryMove(dx: Int, dy: Int) -> Bool {
        guard var piece = current else { return false }
        piece.origin.x += dx
        piece.origin.y += dy
        if pieceFits(piece) {
            current = piece
            redrawActive()
            return true
        }
        return false
    }

    private func tryRotate() {
        guard var piece = current, piece.kind != .O else { return }
        piece.cells = rotated(piece.cells)
        // Simple wall kicks: try original, then shift ±1, ±2 horizontally.
        for dx in [0, -1, 1, -2, 2] {
            var test = piece
            test.origin.x += dx
            if pieceFits(test) {
                current = test
                redrawActive()
                return
            }
        }
    }

    private func lockPiece() {
        guard let piece = current else { return }
        for (dx, dy) in piece.cells {
            let x = piece.origin.x + dx
            let y = piece.origin.y + dy
            if y >= 0 && y < rows && x >= 0 && x < cols {
                board[y][x] = piece.kind
            }
        }
        current = nil
        clearLinesAndScore()
        redrawStack()
        redrawActive()
        if state == .playing { spawnNextPiece() }
    }

    private func clearLinesAndScore() {
        var cleared = 0
        var r = 0
        while r < rows {
            if board[r].allSatisfy({ $0 != nil }) {
                board.remove(at: r)
                board.append(Array(repeating: nil, count: cols))
                cleared += 1
            } else {
                r += 1
            }
        }
        if cleared == 0 { return }
        let bonus: [Int] = [0, 100, 300, 500, 800]
        score += bonus[min(cleared, 4)] * level
        linesCleared += cleared
        let newLevel = max(1, linesCleared / 10 + 1)
        if newLevel != level {
            level = newLevel
            fallInterval = max(0.08, 0.7 * pow(0.85, Double(level - 1)))
        }
        onScoreChanged?(score)
    }

    private func hardDrop() {
        guard current != nil else { return }
        while tryMove(dx: 0, dy: -1) { }
        lockPiece()
    }

    private func softTick() {
        if !tryMove(dx: 0, dy: -1) {
            lockPiece()
        }
    }

    // MARK: - Rendering

    private func cellNode(color: NSColor, at col: Int, row: Int) -> SKNode {
        let inset: CGFloat = max(1, cellSize * 0.07)
        let rect = CGRect(x: inset, y: inset,
                          width: cellSize - inset * 2,
                          height: cellSize - inset * 2)
        let node = SKShapeNode(rect: rect, cornerRadius: cellSize * 0.18)
        node.fillColor = color
        node.strokeColor = color.blended(withFraction: 0.4, of: .black) ?? color
        node.lineWidth = 1
        node.position = cellPoint(col: col, row: row)
        return node
    }

    private func redrawStack() {
        stackLayer.removeAllChildren()
        for r in 0..<rows {
            for c in 0..<cols {
                if let kind = board[r][c] {
                    stackLayer.addChild(cellNode(color: kind.color, at: c, row: r))
                }
            }
        }
    }

    private func redrawActive() {
        activeLayer.removeAllChildren()
        guard let p = current else { return }
        for (dx, dy) in p.cells {
            activeLayer.addChild(cellNode(color: p.kind.color,
                                           at: p.origin.x + dx,
                                           row: p.origin.y + dy))
        }
    }

    // MARK: - Update loop

    // MARK: - Mouse input
    //
    // Any mouse button starts (or restarts) a run; once a piece is falling,
    // clicks are ignored so the player moves / rotates with keys only.
    override func mouseDown(with event: NSEvent)      { if state != .playing { primary() } }
    override func rightMouseDown(with event: NSEvent) { if state != .playing { primary() } }
    override func otherMouseDown(with event: NSEvent) { if state != .playing { primary() } }

    override func update(_ currentTime: TimeInterval) {
        guard state == .playing else { lastUpdate = currentTime; return }
        let last = lastUpdate ?? currentTime
        accumulator += currentTime - last
        lastUpdate = currentTime
        while accumulator >= fallInterval {
            accumulator -= fallInterval
            softTick()
            if state != .playing { return }
        }
    }

    // MARK: - Input

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handleKey(event) { return nil }
            return event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // Pause / Escape always available.
        if event.keyCode == 35 || event.keyCode == 53 {
            togglePause()
            return true
        }
        // Any key starts (or restarts) the game when we're not actively
        // playing. Users shouldn't have to remember which specific key
        // summons the first piece.
        if state == .idle || state == .gameOver {
            primary()
            return true
        }
        if state == .paused {
            resumeGame()
            return true
        }
        guard state == .playing else { return false }
        switch event.keyCode {
        // Arrow keys
        case 123: _ = tryMove(dx: -1, dy: 0); return true   // ←
        case 124: _ = tryMove(dx:  1, dy: 0); return true   // →
        case 125: _ = tryMove(dx:  0, dy: -1); return true  // ↓ (soft drop)
        case 126: tryRotate(); return true                  // ↑ (rotate)
        // WASD
        case 0:   _ = tryMove(dx: -1, dy: 0); return true   // A
        case 2:   _ = tryMove(dx:  1, dy: 0); return true   // D
        case 1:   _ = tryMove(dx:  0, dy: -1); return true  // S
        case 13:  tryRotate(); return true                  // W
        // Hard drop
        case 49:  hardDrop(); return true                   // space
        default:  return false
        }
    }

    func primary() {
        switch state {
        case .idle:     beginPlay()
        case .paused:   resumeGame()
        case .gameOver: resetGame()
        case .playing:  break
        }
    }

    func togglePause() {
        switch state {
        case .playing: pauseGame()
        case .paused:  resumeGame()
        default: break
        }
    }

    func pauseIfActive() { if state == .playing { pauseGame() } }

    private func pauseGame() {
        guard state == .playing else { return }
        state = .paused
        onPauseChanged?(true)
    }

    private func resumeGame() {
        guard state == .paused else { return }
        state = .playing
        lastUpdate = nil
        accumulator = 0
        onPauseChanged?(false)
    }
}

// MARK: - Controller

@MainActor
final class TetrisController: GameController {
    let scene: TetrisScene

    init() {
        let scene = TetrisScene(size: GameKind.tetris.preferredSize)
        scene.scaleMode = .resizeFill
        self.scene = scene
        super.init(kind: .tetris)

        scene.onScoreChanged = { [weak self] s in
            DispatchQueue.main.async { self?.recordScore(s) }
        }
        scene.onStart    = { [weak self] in DispatchQueue.main.async { self?.markStart() } }
        scene.onGameOver = { [weak self] in DispatchQueue.main.async { self?.markGameOver() } }
        scene.onReset    = { [weak self] in DispatchQueue.main.async { self?.markReset() } }
        scene.onPauseChanged = { [weak self] p in
            DispatchQueue.main.async { self?.isPaused = p }
        }
    }

    override func makeBody() -> AnyView {
        AnyView(SpriteView(scene: scene, options: [.ignoresSiblingOrder]))
    }

    override func togglePause()   { scene.togglePause() }
    override func pauseIfActive() { scene.pauseIfActive() }
}
