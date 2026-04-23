import SpriteKit
import AppKit

/// A polished Flappy-Bird-style mini-game implemented entirely with SpriteKit
/// primitives — no external image assets. On top of the core loop we layer:
///
///  • A baked gradient sky that re-renders on resize.
///  • Two parallax tiers of rolling hills plus slow-drifting clouds.
///  • A continuously scrolling tiled ground (with a stationary collider so
///    collisions don't wobble).
///  • A hand-built bird with an animated wing, squash-and-stretch on flap,
///    smooth velocity-based tilt, and a drop shadow.
///  • Pipes with caps, rim highlights and shadow strips, and a compound
///    physics body.
///  • Screen flash, screen shake and a feather-burst particle effect on
///    death, plus a floating "+1" popup that bubbles up from the bird on
///    every score.
///  • Monotonic clamping of each random gap center so consecutive pipes are
///    always physically reachable within the horizontal travel time.
///
/// Mechanics:
///  - Gravity pulls the bird down continuously.
///  - Space / mouse click / tap sends an upward impulse (a "flap").
///  - Pipe pairs spawn on the right and scroll left at a constant speed.
///  - Collision with a pipe, the ceiling or the floor ends the game.
///  - Score increments when the bird passes the horizontal center of a pipe.
final class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Callbacks consumed by the SwiftUI HUD
    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: (() -> Void)?
    var onStart: (() -> Void)?
    var onReset: (() -> Void)?
    var onPauseChanged: ((Bool) -> Void)?

    // MARK: - Physics category bitmasks
    private struct Category {
        static let bird: UInt32   = 1 << 0
        static let pipe: UInt32   = 1 << 1
        static let ground: UInt32 = 1 << 2
        static let score: UInt32  = 1 << 3
    }

    // MARK: - Tunables
    private let gravity: CGFloat = -9.0
    // Tuned against the bird's implicit mass (SKPhysicsBody(circleOfRadius: 14)
    // with default density 1.0, which works out to ~0.027 kg once SpriteKit's
    // 150 pt/m physics scaling is applied). Much larger sends the bird
    // straight through the ceiling guard on the very first click.
    private let flapImpulse: CGFloat = 6.0
    private let pipeSpeed: CGFloat = 130            // points per second
    private let pipeSpawnInterval: TimeInterval = 2.0
    private let pipeGap: CGFloat = 170
    private let pipeWidth: CGFloat = 64
    private let pipeCapHeight: CGFloat = 22
    private let pipeCapOverhang: CGFloat = 8
    private let groundHeight: CGFloat = 56
    /// Maximum vertical difference between the centers of two consecutive
    /// pipe gaps. Without this clamp the RNG occasionally produces two
    /// adjacent pipes whose gaps are further apart than the bird can climb in
    /// the horizontal time between them, making the course unplayable.
    private let maxGapCenterDelta: CGFloat = 130

    // MARK: - Palette
    private let skyTop     = NSColor(calibratedRed: 0.29, green: 0.50, blue: 0.94, alpha: 1.0)
    private let skyBottom  = NSColor(calibratedRed: 0.99, green: 0.82, blue: 0.75, alpha: 1.0)
    private let hillFar    = NSColor(calibratedRed: 0.45, green: 0.56, blue: 0.78, alpha: 0.55)
    private let hillNear   = NSColor(calibratedRed: 0.33, green: 0.46, blue: 0.66, alpha: 0.78)
    private let pipeMain   = NSColor(calibratedRed: 0.38, green: 0.80, blue: 0.38, alpha: 1.0)
    private let pipeLight  = NSColor(calibratedRed: 0.70, green: 0.95, blue: 0.50, alpha: 1.0)
    private let pipeDark   = NSColor(calibratedRed: 0.22, green: 0.55, blue: 0.22, alpha: 1.0)
    private let pipeStroke = NSColor(calibratedRed: 0.12, green: 0.33, blue: 0.12, alpha: 1.0)
    private let dirtLight  = NSColor(calibratedRed: 0.86, green: 0.74, blue: 0.44, alpha: 1.0)
    private let dirtDark   = NSColor(calibratedRed: 0.56, green: 0.40, blue: 0.22, alpha: 1.0)
    private let grass      = NSColor(calibratedRed: 0.48, green: 0.75, blue: 0.32, alpha: 1.0)
    private let birdYellow = NSColor(calibratedRed: 1.00, green: 0.83, blue: 0.22, alpha: 1.0)
    private let birdBelly  = NSColor(calibratedRed: 1.00, green: 0.96, blue: 0.66, alpha: 1.0)
    private let birdOrange = NSColor(calibratedRed: 0.98, green: 0.50, blue: 0.10, alpha: 1.0)
    private let birdWing   = NSColor(calibratedRed: 0.98, green: 0.68, blue: 0.12, alpha: 1.0)

    // MARK: - Z ordering
    private enum Z {
        static let sky: CGFloat      = -100
        static let hillFar: CGFloat  = -80
        static let hillNear: CGFloat = -70
        static let cloud: CGFloat    = -60
        static let pipe: CGFloat     = 1
        static let ground: CGFloat   = 5
        static let bird: CGFloat     = 10
        static let popup: CGFloat    = 11
        static let flash: CGFloat    = 1000
    }

    // MARK: - Node refs
    private var world: SKNode!
    private var background: SKSpriteNode!
    private var hillLayerFar: SKNode!
    private var hillLayerNear: SKNode!
    private var cloudLayer: SKNode!
    private var pipesLayer: SKNode!
    private var groundLayer: SKNode!
    private var groundCollider: SKNode!
    private var bird: SKNode!
    private var birdBody: SKShapeNode!
    private var wing: SKShapeNode!
    private var liveEye: SKNode!   // sclera + pupil, shown while alive
    private var deadEye: SKNode!   // "X" cross, shown on death
    private var flashNode: SKSpriteNode!

    // MARK: - Runtime state
    private var lastSpawnTime: TimeInterval = 0
    private var lastGapCenter: CGFloat = 0
    private var score: Int = 0 {
        didSet { onScoreChanged?(score) }
    }
    private enum State { case idle, playing, paused, gameOver }
    private var state: State = .idle
    private var keyMonitor: Any?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = skyTop
        physicsWorld.gravity = CGVector(dx: 0, dy: gravity)
        physicsWorld.contactDelegate = self

        world = SKNode()
        addChild(world)

        buildBackground()
        buildHills()
        buildClouds()
        buildPipesLayer()
        buildGround()
        buildBird()
        buildFlash()

        resetGame(initial: true)

        // Key events inside a SwiftUI `SpriteView` don't reliably reach
        // `SKScene.keyDown`, so we install a local monitor scoped to this
        // process. We only act on the event if the scene's host view is
        // inside the current key window — this keeps us from "flapping" in
        // response to keystrokes the user is sending to other windows.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let view = self.view else { return event }
            guard view.window?.isKeyWindow == true else { return event }
            // Pause / Escape always available.
            if event.keyCode == 35 || event.keyCode == 53 { // P or Escape
                self.togglePause()
                return nil
            }
            // When not actively playing, any key starts / resumes / resets.
            // Once you're in the air, only Space / Return count as a "flap"
            // so typing other keys doesn't cause accidental flaps.
            switch self.state {
            case .idle, .gameOver, .paused:
                self.handlePrimaryInput()
                return nil
            case .playing:
                if event.keyCode == 49 || event.keyCode == 36 {
                    self.handlePrimaryInput()
                    return nil
                }
                return event
            }
        }
    }

    override func willMove(from view: SKView) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Rebuild every size-dependent layer so a resize doesn't leave gaps.
        guard bird != nil else { return }
        rebuildBackground()
        rebuildHills()
        rebuildClouds()
        rebuildGround()
        flashNode.size = size
        flashNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        if state != .playing {
            bird.position = CGPoint(x: size.width * 0.28, y: size.height * 0.55)
        }
    }

    // MARK: - Background (gradient sky)

    private func buildBackground() {
        background = SKSpriteNode(color: skyTop, size: size)
        background.zPosition = Z.sky
        background.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        world.addChild(background)
        rebuildBackground()
    }

    private func rebuildBackground() {
        let drawSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        background.size = drawSize
        background.position = CGPoint(x: drawSize.width / 2, y: drawSize.height / 2)
        background.texture = makeGradientTexture(size: drawSize, top: skyTop, bottom: skyBottom)
    }

    private func makeGradientTexture(size: CGSize, top: NSColor, bottom: NSColor) -> SKTexture {
        let image = NSImage(size: size)
        image.lockFocus()
        if let gradient = NSGradient(colors: [top, bottom]) {
            // angle −90° draws from top to bottom in AppKit's coordinate system.
            gradient.draw(in: NSRect(origin: .zero, size: size), angle: -90)
        }
        image.unlockFocus()
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }

    // MARK: - Hills (two parallax layers)

    private func buildHills() {
        hillLayerFar = SKNode()
        hillLayerFar.zPosition = Z.hillFar
        world.addChild(hillLayerFar)

        hillLayerNear = SKNode()
        hillLayerNear.zPosition = Z.hillNear
        world.addChild(hillLayerNear)

        rebuildHills()
    }

    private func rebuildHills() {
        hillLayerFar.removeAllChildren()
        hillLayerNear.removeAllChildren()

        let baseY = groundHeight + 4
        hillLayerFar.addChild(makeHillNode(
            path: makeHillPath(baseY: baseY, step: 110, minPeak: 70, maxPeak: 130, seed: 1),
            color: hillFar))
        hillLayerNear.addChild(makeHillNode(
            path: makeHillPath(baseY: baseY, step: 170, minPeak: 40, maxPeak: 95, seed: 2),
            color: hillNear))
    }

    private func makeHillPath(baseY: CGFloat, step: CGFloat, minPeak: CGFloat,
                              maxPeak: CGFloat, seed: Int) -> CGPath {
        // Deterministic per-layer RNG so resizes don't reshuffle hills wildly.
        var rng = SeededRNG(seed: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -20, y: 0))
        path.addLine(to: CGPoint(x: -20, y: baseY))
        var x: CGFloat = -20
        while x < size.width + 20 {
            let next = x + step
            let peak = CGFloat.random(in: minPeak...maxPeak, using: &rng)
            path.addQuadCurve(to: CGPoint(x: next, y: baseY),
                              control: CGPoint(x: x + step / 2, y: baseY + peak))
            x = next
        }
        path.addLine(to: CGPoint(x: size.width + 20, y: 0))
        path.closeSubpath()
        return path
    }

    private func makeHillNode(path: CGPath, color: NSColor) -> SKShapeNode {
        let node = SKShapeNode(path: path)
        node.fillColor = color
        node.strokeColor = .clear
        return node
    }

    // MARK: - Clouds

    private func buildClouds() {
        cloudLayer = SKNode()
        cloudLayer.zPosition = Z.cloud
        world.addChild(cloudLayer)
        rebuildClouds()
    }

    private func rebuildClouds() {
        cloudLayer.removeAllChildren()
        for _ in 0..<5 {
            spawnCloud(
                at: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: size.height * 0.55 ... size.height * 0.92)
                ),
                scale: CGFloat.random(in: 0.7...1.3)
            )
        }
    }

    private func spawnCloud(at point: CGPoint, scale: CGFloat) {
        let cloud = makeCloudNode()
        cloud.position = point
        cloud.xScale = scale
        cloud.yScale = scale
        cloud.alpha = 0.88
        cloudLayer.addChild(cloud)
        scheduleCloudDrift(cloud)
    }

    private func makeCloudNode() -> SKNode {
        let cloud = SKNode()
        let bubbles: [CGRect] = [
            CGRect(x: -38, y:  0,   width: 48, height: 30),
            CGRect(x: -18, y:  8,   width: 44, height: 36),
            CGRect(x:  8,  y:  2,   width: 44, height: 30),
            CGRect(x: -10, y: -10,  width: 34, height: 22)
        ]
        for b in bubbles {
            let node = SKShapeNode(ellipseOf: CGSize(width: b.width, height: b.height))
            node.position = CGPoint(x: b.midX, y: b.midY)
            node.fillColor = NSColor(white: 1.0, alpha: 0.92)
            node.strokeColor = .clear
            cloud.addChild(node)
        }
        return cloud
    }

    private func scheduleCloudDrift(_ cloud: SKNode) {
        let speed = CGFloat.random(in: 10...22)
        let distance = size.width + 120
        let move = SKAction.moveBy(x: -distance, y: 0,
                                   duration: TimeInterval(distance / speed))
        let reset = SKAction.run { [weak self, weak cloud] in
            guard let self = self, let cloud = cloud else { return }
            cloud.position = CGPoint(
                x: self.size.width + 60,
                y: CGFloat.random(in: self.size.height * 0.55 ... self.size.height * 0.92)
            )
        }
        cloud.removeAllActions()
        cloud.run(.repeatForever(.sequence([move, reset])))
    }

    // MARK: - Ground (scrolling visual + fixed collider)

    private func buildGround() {
        groundLayer = SKNode()
        groundLayer.zPosition = Z.ground
        world.addChild(groundLayer)

        groundCollider = SKNode()
        groundCollider.zPosition = Z.ground - 0.1
        world.addChild(groundCollider)

        rebuildGround()
    }

    private func rebuildGround() {
        groundLayer.removeAllActions()
        groundLayer.removeAllChildren()
        groundCollider.removeAllChildren()
        groundCollider.physicsBody = nil

        // Scrolling tiles: three identical copies side-by-side so we always
        // have full coverage as they slide leftward and snap back.
        let tileW = max(size.width, 400)
        let template = makeGroundTile(width: tileW)
        for i in 0..<3 {
            let tile = template.copy() as! SKNode
            tile.position = CGPoint(x: CGFloat(i) * tileW, y: 0)
            groundLayer.addChild(tile)
        }
        let scroll = SKAction.moveBy(x: -tileW, y: 0,
                                     duration: TimeInterval(tileW / pipeSpeed))
        let snap = SKAction.moveBy(x: tileW, y: 0, duration: 0)
        groundLayer.run(.repeatForever(.sequence([scroll, snap])))

        // Static collider. Its top edge is the floor; leaving it outside the
        // scrolling layer keeps the collision plane from wobbling every time
        // the tiles snap back.
        groundCollider.position = CGPoint(x: size.width / 2, y: groundHeight / 2)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 3,
                                                     height: groundHeight))
        body.isDynamic = false
        body.categoryBitMask = Category.ground
        body.collisionBitMask = Category.bird
        body.contactTestBitMask = Category.bird
        groundCollider.physicsBody = body
    }

    private func makeGroundTile(width: CGFloat) -> SKNode {
        // Seed the per-tile RNG deterministically so all three copies are
        // visually identical — otherwise the snap-back would jump.
        var rng = SeededRNG(seed: 0xF1A1_BEE0)
        let tile = SKNode()

        let dirt = SKShapeNode(rectOf: CGSize(width: width, height: groundHeight))
        dirt.fillColor = dirtLight
        dirt.strokeColor = .clear
        dirt.position = CGPoint(x: width / 2, y: groundHeight / 2)
        tile.addChild(dirt)

        let stripeW: CGFloat = 32
        var x: CGFloat = 0
        var stripeOn = false
        while x < width {
            if stripeOn {
                let s = SKShapeNode(rectOf: CGSize(width: stripeW, height: groundHeight - 14))
                s.fillColor = dirtDark.withAlphaComponent(0.18)
                s.strokeColor = .clear
                s.position = CGPoint(x: x + stripeW / 2, y: (groundHeight - 14) / 2)
                tile.addChild(s)
            }
            x += stripeW
            stripeOn.toggle()
        }

        let grassBand = SKShapeNode(rectOf: CGSize(width: width, height: 12))
        grassBand.fillColor = grass
        grassBand.strokeColor = .clear
        grassBand.position = CGPoint(x: width / 2, y: groundHeight - 6)
        tile.addChild(grassBand)

        let highlight = SKShapeNode(rectOf: CGSize(width: width, height: 2))
        highlight.fillColor = grass.highlight(withLevel: 0.4) ?? .white
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: width / 2, y: groundHeight - 1)
        tile.addChild(highlight)

        let tuftCount = max(Int(width / 36), 4)
        for _ in 0..<tuftCount {
            let tuft = SKShapeNode(ellipseOf: CGSize(width: 10, height: 6))
            tuft.fillColor = grass.highlight(withLevel: 0.25) ?? grass
            tuft.strokeColor = .clear
            tuft.position = CGPoint(
                x: CGFloat.random(in: 0...width, using: &rng),
                y: groundHeight - CGFloat.random(in: 1...3, using: &rng)
            )
            tile.addChild(tuft)
        }

        return tile
    }

    // MARK: - Pipes

    private func buildPipesLayer() {
        pipesLayer = SKNode()
        pipesLayer.zPosition = Z.pipe
        world.addChild(pipesLayer)
    }

    private func spawnPipePair() {
        let baseMin = pipeGap / 2 + groundHeight + 24
        let baseMax = size.height - pipeGap / 2 - 30
        guard baseMax > baseMin else { return }

        // Clamp the next gap to within maxGapCenterDelta of the previous one
        // so the course is always physically flyable.
        let seedCenter = lastGapCenter > 0 ? lastGapCenter : (size.height / 2)
        let lower = max(baseMin, seedCenter - maxGapCenterDelta)
        let upper = min(baseMax, seedCenter + maxGapCenterDelta)
        let gapCenter = CGFloat.random(in: lower...upper)
        lastGapCenter = gapCenter

        let pair = SKNode()
        pair.name = "pipePair"
        pair.position = CGPoint(x: size.width + pipeWidth, y: 0)
        pair.zPosition = Z.pipe

        // Bottom pipe — cap on the top (facing the gap).
        let bottomHeight = gapCenter - pipeGap / 2
        let bottom = makePipeNode(width: pipeWidth, height: bottomHeight, capOnTop: true)
        bottom.position = CGPoint(x: 0, y: bottomHeight / 2)
        pair.addChild(bottom)

        // Top pipe — cap on the bottom (facing the gap).
        let topHeight = size.height - (gapCenter + pipeGap / 2)
        let top = makePipeNode(width: pipeWidth, height: topHeight, capOnTop: false)
        top.position = CGPoint(x: 0, y: size.height - topHeight / 2)
        pair.addChild(top)

        // Invisible scoring sensor.
        let scoreNode = SKNode()
        scoreNode.position = CGPoint(x: pipeWidth / 2, y: gapCenter)
        let scoreBody = SKPhysicsBody(rectangleOf: CGSize(width: 2, height: pipeGap))
        scoreBody.isDynamic = false
        scoreBody.categoryBitMask = Category.score
        scoreBody.collisionBitMask = 0
        scoreBody.contactTestBitMask = Category.bird
        scoreNode.physicsBody = scoreBody
        pair.addChild(scoreNode)

        pair.alpha = 0
        pair.run(.fadeAlpha(to: 1.0, duration: 0.25))
        pipesLayer.addChild(pair)

        let distance = size.width + pipeWidth * 2
        let duration = TimeInterval(distance / pipeSpeed)
        pair.run(.sequence([
            .moveBy(x: -distance, y: 0, duration: duration),
            .removeFromParent()
        ]))
    }

    private func makePipeNode(width: CGFloat, height: CGFloat, capOnTop: Bool) -> SKNode {
        let node = SKNode()

        let body = SKShapeNode(rectOf: CGSize(width: width, height: height))
        body.fillColor = pipeMain
        body.strokeColor = pipeStroke
        body.lineWidth = 2
        node.addChild(body)

        let hi = SKShapeNode(rectOf: CGSize(width: width * 0.18,
                                            height: max(height - 4, 0)))
        hi.fillColor = pipeLight
        hi.strokeColor = .clear
        hi.position = CGPoint(x: -width * 0.28, y: 0)
        node.addChild(hi)

        let sh = SKShapeNode(rectOf: CGSize(width: width * 0.22,
                                            height: max(height - 4, 0)))
        sh.fillColor = pipeDark
        sh.strokeColor = .clear
        sh.position = CGPoint(x: width * 0.26, y: 0)
        node.addChild(sh)

        let capWidth = width + pipeCapOverhang * 2
        let capY: CGFloat = capOnTop
            ? (height / 2 - pipeCapHeight / 2)
            : (-height / 2 + pipeCapHeight / 2)
        let cap = SKShapeNode(rectOf: CGSize(width: capWidth, height: pipeCapHeight))
        cap.fillColor = pipeMain
        cap.strokeColor = pipeStroke
        cap.lineWidth = 2
        cap.position = CGPoint(x: 0, y: capY)
        node.addChild(cap)

        let capHi = SKShapeNode(rectOf: CGSize(width: capWidth - 10, height: 4))
        capHi.fillColor = pipeLight
        capHi.strokeColor = .clear
        capHi.position = CGPoint(x: 0, y: capY + pipeCapHeight / 2 - 6)
        node.addChild(capHi)

        let capSh = SKShapeNode(rectOf: CGSize(width: capWidth - 10, height: 3))
        capSh.fillColor = pipeDark
        capSh.strokeColor = .clear
        capSh.position = CGPoint(x: 0, y: capY - pipeCapHeight / 2 + 4)
        node.addChild(capSh)

        // Compound physics body: main stalk + slightly wider cap. Using a
        // compound body (rather than just the stalk) keeps the bird from
        // slipping inside the cap overhang.
        let mainBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        let capBody = SKPhysicsBody(
            rectangleOf: CGSize(width: capWidth, height: pipeCapHeight),
            center: CGPoint(x: 0, y: capY)
        )
        let combined = SKPhysicsBody(bodies: [mainBody, capBody])
        combined.isDynamic = false
        combined.categoryBitMask = Category.pipe
        combined.collisionBitMask = Category.bird
        combined.contactTestBitMask = Category.bird
        node.physicsBody = combined

        return node
    }

    // MARK: - Bird

    private func buildBird() {
        bird = SKNode()
        bird.zPosition = Z.bird
        bird.position = CGPoint(x: size.width * 0.28, y: size.height * 0.55)

        let radius: CGFloat = 14

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 30, height: 10))
        shadow.fillColor = NSColor(white: 0, alpha: 0.18)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2, y: -radius - 4)
        shadow.zPosition = -1
        bird.addChild(shadow)

        birdBody = SKShapeNode(circleOfRadius: radius)
        birdBody.fillColor = birdYellow
        birdBody.strokeColor = NSColor(calibratedRed: 0.82, green: 0.50, blue: 0.08, alpha: 1.0)
        birdBody.lineWidth = 2
        bird.addChild(birdBody)

        let belly = SKShapeNode(ellipseOf: CGSize(width: 20, height: 14))
        belly.fillColor = birdBelly
        belly.strokeColor = .clear
        belly.position = CGPoint(x: -2, y: -4)
        bird.addChild(belly)

        wing = SKShapeNode(ellipseOf: CGSize(width: 18, height: 10))
        wing.fillColor = birdWing
        wing.strokeColor = NSColor(calibratedRed: 0.68, green: 0.40, blue: 0.05, alpha: 0.9)
        wing.lineWidth = 1
        wing.position = CGPoint(x: -3, y: 2)
        bird.addChild(wing)

        let beakPath = CGMutablePath()
        beakPath.move(to: CGPoint(x: 0, y: -3.5))
        beakPath.addLine(to: CGPoint(x: 10, y: 0))
        beakPath.addLine(to: CGPoint(x: 0, y: 3.5))
        beakPath.closeSubpath()
        let beak = SKShapeNode(path: beakPath)
        beak.fillColor = birdOrange
        beak.strokeColor = NSColor(calibratedRed: 0.68, green: 0.28, blue: 0.05, alpha: 1.0)
        beak.lineWidth = 1
        beak.position = CGPoint(x: radius + 1, y: 0)
        bird.addChild(beak)

        // Eye is a pair of nodes (liveEye, deadEye) anchored to the same
        // point so we can swap between them on death without re-laying out.
        let eyePos = CGPoint(x: 5, y: 4)

        liveEye = SKNode()
        liveEye.position = eyePos
        let sclera = SKShapeNode(circleOfRadius: 4)
        sclera.fillColor = .white
        sclera.strokeColor = NSColor(white: 0.25, alpha: 0.6)
        sclera.lineWidth = 0.5
        liveEye.addChild(sclera)
        let pupil = SKShapeNode(circleOfRadius: 1.8)
        pupil.fillColor = .black
        pupil.strokeColor = .clear
        pupil.position = CGPoint(x: 1, y: 0)
        liveEye.addChild(pupil)
        bird.addChild(liveEye)

        deadEye = makeDeadEyeNode()
        deadEye.position = eyePos
        deadEye.isHidden = true
        deadEye.setScale(0.01) // will pop to full size when shown
        bird.addChild(deadEye)

        let pbody = SKPhysicsBody(circleOfRadius: radius)
        pbody.isDynamic = false   // becomes dynamic on first flap
        pbody.allowsRotation = false
        pbody.restitution = 0
        pbody.categoryBitMask = Category.bird
        pbody.collisionBitMask = Category.pipe | Category.ground
        pbody.contactTestBitMask = Category.pipe | Category.ground | Category.score
        bird.physicsBody = pbody

        world.addChild(bird)
    }

    /// Two crossed strokes forming a small "X" — the classic cartoon
    /// dead-eye. Returned centered at (0,0) so the caller can position it
    /// wherever the live eye is.
    private func makeDeadEyeNode() -> SKNode {
        let node = SKNode()
        let length: CGFloat = 5.5
        let lineWidth: CGFloat = 1.6
        let strokeColor = NSColor(white: 0.05, alpha: 1.0)

        for angle in [CGFloat.pi / 4, -CGFloat.pi / 4] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -length, y: 0))
            path.addLine(to: CGPoint(x:  length, y: 0))
            let stroke = SKShapeNode(path: path)
            stroke.strokeColor = strokeColor
            stroke.lineWidth = lineWidth
            stroke.lineCap = .round
            stroke.zRotation = angle
            node.addChild(stroke)
        }
        return node
    }

    private func runIdleBob() {
        guard state == .idle else { return }
        bird.removeAction(forKey: "idleBob")
        let up = SKAction.moveBy(x: 0, y: 10, duration: 0.6)
        up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -10, duration: 0.6)
        down.timingMode = .easeInEaseOut
        bird.run(.repeatForever(.sequence([up, down])), withKey: "idleBob")

        wing.removeAction(forKey: "wing")
        let wu = SKAction.rotate(toAngle: 0.18, duration: 0.35, shortestUnitArc: true)
        wu.timingMode = .easeInEaseOut
        let wd = SKAction.rotate(toAngle: -0.18, duration: 0.35, shortestUnitArc: true)
        wd.timingMode = .easeInEaseOut
        wing.run(.repeatForever(.sequence([wu, wd])), withKey: "wing")
    }

    private func stopIdleBob() {
        bird.removeAction(forKey: "idleBob")
        wing.removeAction(forKey: "wing")
    }

    private func showDeadEye() {
        liveEye.isHidden = true
        deadEye.isHidden = false
        deadEye.removeAllActions()
        deadEye.setScale(0.01)
        // A tiny spring-pop sells the "*bonk*".
        let pop = SKAction.scale(to: 1.15, duration: 0.12)
        pop.timingMode = .easeOut
        let settle = SKAction.scale(to: 1.0, duration: 0.10)
        settle.timingMode = .easeInEaseOut
        deadEye.run(.sequence([pop, settle]))
    }

    private func restoreLiveEye() {
        deadEye.removeAllActions()
        deadEye.isHidden = true
        deadEye.setScale(0.01)
        liveEye.isHidden = false
    }

    // MARK: - Flash / shake / feathers / popup

    private func buildFlash() {
        flashNode = SKSpriteNode(color: .white, size: size)
        flashNode.zPosition = Z.flash
        flashNode.alpha = 0
        flashNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        // Parented to scene (NOT world) so screen shake doesn't drag it around.
        addChild(flashNode)
    }

    private func flashScreen() {
        flashNode.removeAllActions()
        flashNode.alpha = 0.55
        flashNode.run(.fadeOut(withDuration: 0.28))
    }

    private func shakeWorld() {
        world.removeAction(forKey: "shake")
        let seq = SKAction.sequence([
            .moveBy(x: -9, y:  3, duration: 0.035),
            .moveBy(x: 14, y: -5, duration: 0.040),
            .moveBy(x: -11, y:  4, duration: 0.040),
            .moveBy(x:  7, y: -3, duration: 0.035),
            .moveBy(x: -4, y:  1, duration: 0.030),
            .moveBy(x:  3, y:  0, duration: 0.025)
        ])
        world.run(seq, withKey: "shake")
    }

    private func emitFeathers(at point: CGPoint) {
        let palette: [NSColor] = [birdYellow, birdBelly, birdWing, birdOrange]
        for _ in 0..<16 {
            let feather = SKShapeNode(ellipseOf: CGSize(width: 7, height: 3))
            feather.fillColor = palette.randomElement() ?? birdYellow
            feather.strokeColor = .clear
            feather.position = point
            feather.zRotation = CGFloat.random(in: 0...(.pi * 2))
            feather.zPosition = Z.bird + 1
            world.addChild(feather)

            let dx = CGFloat.random(in: -150...150)
            let dy = CGFloat.random(in:  80...220)
            let fall: CGFloat = -280
            let rot = CGFloat.random(in: -6...6)
            let up = SKAction.moveBy(x: dx, y: dy, duration: 0.4)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: dx / 3, y: fall, duration: 0.9)
            let rotate = SKAction.rotate(byAngle: rot, duration: 1.3)
            let fade = SKAction.fadeOut(withDuration: 1.3)
            feather.run(.sequence([
                .group([.sequence([up, down]), rotate, fade]),
                .removeFromParent()
            ]))
        }
    }

    private func spawnScorePopup() {
        let label = SKLabelNode(text: "+1")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 22
        label.fontColor = NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.45, alpha: 1.0)
        label.position = CGPoint(x: bird.position.x + 22, y: bird.position.y + 20)
        label.zPosition = Z.popup
        label.setScale(0.3)

        // Cheap drop shadow — a duplicate label offset and darkened.
        let shadow = SKLabelNode(text: label.text)
        shadow.fontName = label.fontName
        shadow.fontSize = label.fontSize
        shadow.fontColor = NSColor(white: 0.0, alpha: 0.45)
        shadow.position = CGPoint(x: 1, y: -1)
        shadow.zPosition = -1
        label.addChild(shadow)

        world.addChild(label)
        let pop = SKAction.scale(to: 1.0, duration: 0.12)
        pop.timingMode = .easeOut
        let hold = SKAction.wait(forDuration: 0.15)
        let rise = SKAction.moveBy(x: 0, y: 60, duration: 0.5)
        let fade = SKAction.fadeOut(withDuration: 0.5)
        label.run(.sequence([pop, hold, .group([rise, fade]), .removeFromParent()]))
    }

    // MARK: - Game flow

    private func resetGame(initial: Bool = false) {
        pipesLayer.removeAllChildren()

        let wasPaused = (state == .paused)

        pipesLayer.isPaused = false
        groundLayer.isPaused = false
        cloudLayer.isPaused = false
        hillLayerFar.isPaused = false
        hillLayerNear.isPaused = false
        physicsWorld.speed = 1

        world.removeAction(forKey: "shake")
        world.position = .zero

        bird.removeAllActions()
        birdBody.removeAllActions()
        wing.removeAllActions()
        bird.position = CGPoint(x: size.width * 0.28, y: size.height * 0.55)
        bird.physicsBody?.isDynamic = false
        bird.physicsBody?.velocity = .zero
        bird.physicsBody?.collisionBitMask = Category.pipe | Category.ground
        bird.physicsBody?.contactTestBitMask = Category.pipe | Category.ground | Category.score
        bird.zRotation = 0
        bird.setScale(1.0)
        birdBody.setScale(1.0)
        wing.zRotation = 0
        restoreLiveEye()

        score = 0
        state = .idle
        lastSpawnTime = 0
        lastGapCenter = size.height / 2

        runIdleBob()

        // If we bulldozed a paused state (e.g. the window was force-reset
        // while the pause panel was up), tell the HUD to take its pause
        // overlay down before onReset() rearranges the rest of the state.
        if wasPaused {
            onPauseChanged?(false)
        }

        if !initial {
            onReset?()
        }
    }

    private func startGame() {
        guard state == .idle else { return }
        state = .playing
        stopIdleBob()
        bird.physicsBody?.isDynamic = true
        flap()
        onStart?()
    }

    private func flap() {
        guard state == .playing else { return }
        bird.physicsBody?.velocity = CGVector(dx: 0, dy: 0)
        bird.physicsBody?.applyImpulse(CGVector(dx: 0, dy: flapImpulse))

        // Wing flap
        wing.removeAction(forKey: "wing")
        let down = SKAction.rotate(toAngle: -0.9, duration: 0.06, shortestUnitArc: true)
        let up = SKAction.rotate(toAngle: 0.3, duration: 0.18, shortestUnitArc: true)
        let settle = SKAction.rotate(toAngle: 0, duration: 0.12, shortestUnitArc: true)
        wing.run(.sequence([down, up, settle]), withKey: "wing")

        // Squash-and-stretch on the body
        birdBody.removeAction(forKey: "squash")
        let squash = SKAction.group([
            .scaleX(to: 0.92, duration: 0.06),
            .scaleY(to: 1.12, duration: 0.06)
        ])
        let rebound = SKAction.group([
            .scaleX(to: 1.0, duration: 0.14),
            .scaleY(to: 1.0, duration: 0.14)
        ])
        birdBody.run(.sequence([squash, rebound]), withKey: "squash")
    }

    private func endGame() {
        guard state == .playing else { return }
        state = .gameOver

        flashScreen()
        shakeWorld()
        emitFeathers(at: bird.position)
        showDeadEye()

        // Freeze the scrolling world so the final moment stays on screen.
        pipesLayer.isPaused = true
        groundLayer.isPaused = true
        cloudLayer.isPaused = true

        // Bird keels over. Leave it dynamic but drop pipe collisions so it
        // doesn't bounce off them on the way down — it still collides with
        // the ground for a final thud.
        bird.physicsBody?.collisionBitMask = Category.ground
        bird.physicsBody?.contactTestBitMask = Category.ground
        bird.physicsBody?.velocity = .zero
        bird.physicsBody?.applyImpulse(CGVector(dx: -1, dy: 3))
        bird.run(.rotate(byAngle: -CGFloat.pi * 1.3, duration: 0.9))

        onGameOver?()
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        switch state {
        case .idle, .paused:
            return

        case .gameOver:
            // Even after death, keep the bird oriented toward its motion.
            if let v = bird.physicsBody?.velocity.dy {
                let target = max(min(v / 400, 0.6), -1.2)
                bird.zRotation = bird.zRotation * 0.82 + target * 0.18
            }
            return

        case .playing:
            break
        }

        if lastSpawnTime == 0 {
            lastSpawnTime = currentTime
        }
        if currentTime - lastSpawnTime >= pipeSpawnInterval {
            spawnPipePair()
            lastSpawnTime = currentTime
        }

        if let v = bird.physicsBody?.velocity.dy {
            // Smooth blend toward the target tilt so the bird doesn't snap
            // between orientations on every flap.
            let target = max(min(v / 400, 0.6), -1.0)
            bird.zRotation = bird.zRotation * 0.82 + target * 0.18
        }

        if bird.position.y > size.height + 20 {
            endGame()
        }
    }

    // MARK: - Physics contact

    func didBegin(_ contact: SKPhysicsContact) {
        let mask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if mask & Category.score == Category.score,
           mask & Category.bird == Category.bird {
            score += 1
            spawnScorePopup()
            if contact.bodyA.categoryBitMask == Category.score {
                contact.bodyA.node?.removeFromParent()
            } else {
                contact.bodyB.node?.removeFromParent()
            }
            return
        }

        if mask & Category.bird == Category.bird,
           (mask & Category.pipe == Category.pipe || mask & Category.ground == Category.ground) {
            endGame()
        }
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        handlePrimaryInput()
    }

    // Accept right-click / middle-click as "any mouse button" only while
    // we're waiting for the player to begin (or restart) a run. While
    // playing, we deliberately ignore them so the player can't flap with
    // stray gestures.
    override func rightMouseDown(with event: NSEvent) {
        if state != .playing { handlePrimaryInput() }
    }

    override func otherMouseDown(with event: NSEvent) {
        if state != .playing { handlePrimaryInput() }
    }

    override func keyDown(with event: NSEvent) {
        // 49 = Space, 36 = Return, 35 = P, 53 = Escape
        if event.keyCode == 49 || event.keyCode == 36 {
            handlePrimaryInput()
        } else if event.keyCode == 35 || event.keyCode == 53 {
            togglePause()
        } else {
            super.keyDown(with: event)
        }
    }

    private func handlePrimaryInput() {
        switch state {
        case .idle:     startGame()
        case .playing:  flap()
        case .paused:   resumeGame()   // click-to-resume, without flapping
        case .gameOver: resetGame()
        }
    }

    // MARK: - Pause

    /// Exposed so the SwiftUI HUD's pause button can drive the same flow as
    /// the P / Escape keyboard shortcut.
    func togglePause() {
        switch state {
        case .playing: pauseGame()
        case .paused:  resumeGame()
        case .idle, .gameOver: break
        }
    }

    /// One-way pause: pauses the simulation if (and only if) we're currently
    /// mid-run. Calling this while idle, already paused, or on the game-over
    /// screen is a no-op — useful from external triggers like
    /// `windowWillMiniaturize` where we never want to accidentally unpause.
    func pauseIfActive() {
        if state == .playing {
            pauseGame()
        }
    }

    private func pauseGame() {
        guard state == .playing else { return }
        state = .paused

        // Stop the simulation dead — velocities are preserved and will resume
        // from where they left off when we restore speed = 1.
        physicsWorld.speed = 0

        // Halt every scrolling layer. The hill layers don't actually have
        // running actions today, but pausing them defensively costs nothing
        // and matches the freeze-frame look we get on death.
        pipesLayer.isPaused = true
        groundLayer.isPaused = true
        cloudLayer.isPaused = true
        hillLayerFar.isPaused = true
        hillLayerNear.isPaused = true

        onPauseChanged?(true)
    }

    private func resumeGame() {
        guard state == .paused else { return }
        state = .playing

        physicsWorld.speed = 1

        pipesLayer.isPaused = false
        groundLayer.isPaused = false
        cloudLayer.isPaused = false
        hillLayerFar.isPaused = false
        hillLayerNear.isPaused = false

        // Re-seed the pipe-spawn clock so a long pause doesn't immediately
        // dump a backlog of pipes on the player.
        lastSpawnTime = 0

        onPauseChanged?(false)
    }
}

// MARK: - Seeded RNG

/// Tiny splittable-hash PRNG. Used for hill shapes and ground-tuft layout so
/// they're stable across redraws and identical across tiles.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEAD_BEEF : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
