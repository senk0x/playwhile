import SwiftUI
import SpriteKit
import AppKit

/// SpriteKit scene that renders the snake, food, and background grid. The
/// simulation itself is a simple timer-driven grid walk — every `tick`
/// seconds the head advances by one cell in the current direction. Eating
/// the food grows the tail by one segment and awards a point.
final class SnakeScene: SKScene {

    // MARK: - Callbacks
    var onScoreChanged: ((Int) -> Void)?
    var onStart: (() -> Void)?
    var onGameOver: (() -> Void)?
    var onReset: (() -> Void)?
    var onPauseChanged: ((Bool) -> Void)?

    // MARK: - Grid geometry
    private let cols = 18
    private let rows = 22
    private var cellSize: CGFloat = 20
    private var boardOrigin: CGPoint = .zero

    // MARK: - Simulation
    private enum Dir { case up, down, left, right }
    private var direction: Dir = .right
    private var queuedDirection: Dir = .right
    private var snake: [CGPoint] = []   // head first
    private var food: CGPoint = .zero
    private var accumulator: TimeInterval = 0
    private var stepInterval: TimeInterval = 0.15
    private var lastUpdate: TimeInterval?

    private enum State { case idle, playing, paused, gameOver }
    private var state: State = .idle
    private var score: Int = 0

    // MARK: - Nodes
    private var board: SKNode!
    private var snakeLayer: SKNode!
    private var foodNode: SKShapeNode!
    private var keyMonitor: Any?

    // MARK: - Palette
    private let boardLight = NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.22, alpha: 1.0)
    private let boardDark  = NSColor(calibratedRed: 0.13, green: 0.25, blue: 0.19, alpha: 1.0)
    private let snakeHead  = NSColor(calibratedRed: 0.75, green: 0.98, blue: 0.62, alpha: 1.0)
    private let snakeBody  = NSColor(calibratedRed: 0.38, green: 0.82, blue: 0.48, alpha: 1.0)
    private let snakeDark  = NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.26, alpha: 1.0)
    private let foodColor  = NSColor(calibratedRed: 0.98, green: 0.46, blue: 0.40, alpha: 1.0)

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.18, alpha: 1.0)

        board = SKNode();      addChild(board)
        snakeLayer = SKNode(); addChild(snakeLayer)

        layoutBoard()
        resetGame()
        installKeyMonitor()
    }

    override func willMove(from view: SKView) {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard board != nil else { return }
        layoutBoard()
        redrawSnake()
        redrawFood()
    }

    // MARK: - Board

    private func layoutBoard() {
        // Preserve a small margin for HUD on top and breathing room.
        let margin: CGFloat = 60
        let availableW = size.width - 24
        let availableH = size.height - margin - 24
        cellSize = max(10, min(availableW / CGFloat(cols), availableH / CGFloat(rows)))
        let boardW = cellSize * CGFloat(cols)
        let boardH = cellSize * CGFloat(rows)
        boardOrigin = CGPoint(x: (size.width - boardW) / 2,
                              y: 16)

        board.removeAllChildren()
        // Checker tiles for a subtle grid feel.
        for r in 0..<rows {
            for c in 0..<cols {
                let tile = SKSpriteNode(
                    color: (r + c).isMultiple(of: 2) ? boardLight : boardDark,
                    size: CGSize(width: cellSize, height: cellSize)
                )
                tile.anchorPoint = .zero
                tile.position = cellPoint(col: c, row: r)
                board.addChild(tile)
            }
        }

        // Subtle frame
        let frame = SKShapeNode(rect: CGRect(x: boardOrigin.x, y: boardOrigin.y,
                                              width: boardW, height: boardH),
                                 cornerRadius: 6)
        frame.strokeColor = NSColor.white.withAlphaComponent(0.12)
        frame.lineWidth = 2
        frame.fillColor = .clear
        board.addChild(frame)
    }

    private func cellPoint(col: Int, row: Int) -> CGPoint {
        CGPoint(x: boardOrigin.x + CGFloat(col) * cellSize,
                y: boardOrigin.y + CGFloat(row) * cellSize)
    }

    // MARK: - Game state

    private func resetGame() {
        state = .idle
        direction = .right
        queuedDirection = .right
        score = 0
        onScoreChanged?(0)
        onReset?()
        stepInterval = 0.15
        accumulator = 0
        lastUpdate = nil

        // Start with a 3-segment snake near the left middle.
        let midRow = rows / 2
        snake = [
            CGPoint(x: 6, y: midRow),
            CGPoint(x: 5, y: midRow),
            CGPoint(x: 4, y: midRow)
        ]
        spawnFood()
        redrawSnake()
        redrawFood()
    }

    private func beginPlay() {
        guard state != .playing else { return }
        state = .playing
        onStart?()
    }

    private func gameOver() {
        state = .gameOver
        onGameOver?()
        flashGameOver()
    }

    private func flashGameOver() {
        let flash = SKSpriteNode(color: NSColor(calibratedRed: 1, green: 0.4, blue: 0.3, alpha: 0.45),
                                  size: size)
        flash.anchorPoint = .zero
        flash.zPosition = 900
        addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.45), .removeFromParent()]))
    }

    // MARK: - Food

    private func spawnFood() {
        let occupied = Set(snake.map { Int($0.x) * 10000 + Int($0.y) })
        var candidate: CGPoint
        repeat {
            candidate = CGPoint(x: Int.random(in: 0..<cols),
                                y: Int.random(in: 0..<rows))
        } while occupied.contains(Int(candidate.x) * 10000 + Int(candidate.y))
        food = candidate
    }

    // MARK: - Rendering

    private func redrawSnake() {
        snakeLayer.removeAllChildren()
        for (idx, seg) in snake.enumerated() {
            let isHead = idx == 0
            let rect = CGRect(x: 1, y: 1,
                              width: cellSize - 2, height: cellSize - 2)
            let node = SKShapeNode(rect: rect, cornerRadius: max(2, cellSize * 0.22))
            node.fillColor = isHead ? snakeHead : snakeBody
            node.strokeColor = snakeDark
            node.lineWidth = 1
            node.position = cellPoint(col: Int(seg.x), row: Int(seg.y))
            snakeLayer.addChild(node)

            if isHead {
                // Tiny eye dots for a face on the head.
                let eye1 = SKShapeNode(circleOfRadius: max(1, cellSize * 0.08))
                eye1.fillColor = .black
                eye1.strokeColor = .clear
                eye1.position = CGPoint(x: cellSize * 0.72, y: cellSize * 0.7)
                node.addChild(eye1)
                let eye2 = SKShapeNode(circleOfRadius: max(1, cellSize * 0.08))
                eye2.fillColor = .black
                eye2.strokeColor = .clear
                eye2.position = CGPoint(x: cellSize * 0.72, y: cellSize * 0.3)
                node.addChild(eye2)
            }
        }
    }

    private func redrawFood() {
        if foodNode == nil {
            foodNode = SKShapeNode(circleOfRadius: cellSize * 0.4)
            foodNode.strokeColor = .clear
            foodNode.zPosition = 5
            addChild(foodNode)
        } else {
            foodNode.path = CGPath(ellipseIn: CGRect(x: -cellSize * 0.4,
                                                      y: -cellSize * 0.4,
                                                      width: cellSize * 0.8,
                                                      height: cellSize * 0.8),
                                    transform: nil)
        }
        foodNode.fillColor = foodColor
        let c = cellPoint(col: Int(food.x), row: Int(food.y))
        foodNode.position = CGPoint(x: c.x + cellSize / 2, y: c.y + cellSize / 2)
    }

    // MARK: - Mouse input
    //
    // "Any mouse button" should begin (or restart) a run. While the snake
    // is already moving, clicks do nothing — directional input is what
    // matters during play.
    override func mouseDown(with event: NSEvent)      { if state != .playing { primary() } }
    override func rightMouseDown(with event: NSEvent) { if state != .playing { primary() } }
    override func otherMouseDown(with event: NSEvent) { if state != .playing { primary() } }

    // MARK: - Simulation loop

    override func update(_ currentTime: TimeInterval) {
        guard state == .playing else { lastUpdate = currentTime; return }
        let last = lastUpdate ?? currentTime
        let dt = currentTime - last
        lastUpdate = currentTime
        accumulator += dt
        while accumulator >= stepInterval {
            accumulator -= stepInterval
            step()
            if state != .playing { return }
        }
    }

    private func step() {
        // Commit the queued direction (only here so the player can only
        // change direction once per tick — prevents same-frame U-turns
        // that would self-collide).
        if !isOpposite(queuedDirection, direction) {
            direction = queuedDirection
        }

        let head = snake[0]
        var next = head
        switch direction {
        case .up:    next.y += 1
        case .down:  next.y -= 1
        case .left:  next.x -= 1
        case .right: next.x += 1
        }

        // Wall collision.
        if next.x < 0 || next.x >= CGFloat(cols) ||
           next.y < 0 || next.y >= CGFloat(rows) {
            gameOver()
            return
        }
        // Self-collision. Note we compare against the tail *before* we pop
        // it, but eating-the-tail is impossible from the head step so this
        // is accurate.
        if snake.dropLast().contains(where: { $0 == next }) {
            gameOver()
            return
        }

        snake.insert(next, at: 0)
        if next == food {
            score += 1
            onScoreChanged?(score)
            spawnFood()
            // Speed up very gently every 5 points.
            if score % 5 == 0 { stepInterval = max(0.07, stepInterval * 0.92) }
            redrawFood()
        } else {
            snake.removeLast()
        }
        redrawSnake()
    }

    private func isOpposite(_ a: Dir, _ b: Dir) -> Bool {
        switch (a, b) {
        case (.up, .down), (.down, .up),
             (.left, .right), (.right, .left): return true
        default: return false
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

    /// Returns true if the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        // Pause / Escape always available.
        if event.keyCode == 35 || event.keyCode == 53 {
            togglePause()
            return true
        }
        // When the snake isn't moving we want "press anything to go".
        // Arrows / WASD in .idle additionally queue an initial direction,
        // but any other key just starts the game.
        if state == .idle || state == .gameOver || state == .paused {
            if state == .idle, let d = Self.direction(for: event.keyCode) {
                setDirection(d)
            } else {
                primary()
            }
            return true
        }
        // While playing we only care about directional input.
        if let d = Self.direction(for: event.keyCode) {
            setDirection(d)
            return true
        }
        return false
    }

    /// Arrow keys + WASD → Dir. `nil` for any other key.
    private static func direction(for code: UInt16) -> Dir? {
        switch code {
        case 126, 13: return .up     // ↑ / W
        case 125, 1:  return .down   // ↓ / S
        case 123, 0:  return .left   // ← / A
        case 124, 2:  return .right  // → / D
        default:      return nil
        }
    }

    private func setDirection(_ d: Dir) {
        switch state {
        case .idle:
            queuedDirection = d
            beginPlay()
        case .playing:
            if !isOpposite(d, direction) { queuedDirection = d }
        default: break
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

    func pauseIfActive() {
        if state == .playing { pauseGame() }
    }

    private func pauseGame() {
        guard state == .playing else { return }
        state = .paused
        isPaused = true
        onPauseChanged?(true)
    }

    private func resumeGame() {
        guard state == .paused else { return }
        state = .playing
        isPaused = false
        lastUpdate = nil       // reset dt so we don't step the clock forward
        accumulator = 0
        onPauseChanged?(false)
    }
}

// MARK: - Controller

@MainActor
final class SnakeController: GameController {
    let scene: SnakeScene

    init() {
        let scene = SnakeScene(size: GameKind.snake.preferredSize)
        scene.scaleMode = .resizeFill
        self.scene = scene
        super.init(kind: .snake)

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
