import SwiftUI
import SpriteKit

/// `GameController` wrapper around the existing Floaty Bird `GameScene`.
/// The scene already exposes the callbacks we need (`onScoreChanged`,
/// `onGameOver`, `onStart`, `onReset`, `onPauseChanged`) — we just pipe
/// them into the shared controller state so the generic HUD picks them up.
@MainActor
final class FloatyBirdController: GameController {
    let scene: GameScene

    init() {
        let scene = GameScene(size: GameKind.floatyBird.preferredSize)
        scene.scaleMode = .resizeFill
        self.scene = scene

        super.init(kind: .floatyBird)

        scene.onScoreChanged = { [weak self] s in
            DispatchQueue.main.async { self?.recordScore(s) }
        }
        scene.onStart = { [weak self] in
            DispatchQueue.main.async { self?.markStart() }
        }
        scene.onGameOver = { [weak self] in
            DispatchQueue.main.async { self?.markGameOver() }
        }
        scene.onReset = { [weak self] in
            DispatchQueue.main.async { self?.markReset() }
        }
        scene.onPauseChanged = { [weak self] paused in
            DispatchQueue.main.async { self?.isPaused = paused }
        }
    }

    override func makeBody() -> AnyView {
        AnyView(SpriteView(scene: scene, options: [.ignoresSiblingOrder]))
    }

    override func togglePause() { scene.togglePause() }

    override func pauseIfActive() { scene.pauseIfActive() }
}
