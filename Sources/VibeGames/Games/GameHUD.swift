import SwiftUI

/// Reusable glassy card used by every center panel (ready / paused /
/// game-over / list).
struct GlassPanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.32))
            )
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

/// Compact "Best N" capsule. The label noun depends on the game (Best,
/// Wins, Solves) so it comes from `GameKind.bestLabel`.
struct BestScoreLabel: View {
    let value: Int
    var label: String = "Best"

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 1.0, green: 0.86, blue: 0.35))
            Text("\(label) \(value)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(Color.white.opacity(0.95))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.28)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

/// Round pause/resume toggle shown in the top-right corner of the HUD.
struct PauseToggleButton: View {
    let isPaused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph(named: isPaused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(.plain)
        .help(isPaused ? "Resume (P)" : "Pause (P)")
        .contentShape(Circle())
    }

    private func glyph(named name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .black))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.black.opacity(0.32)))
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
    }
}

/// Round "Back to list" chip shown in the top-left corner of every game.
struct MenuButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.32)))
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .help("All games")
        .contentShape(Circle())
    }
}

/// The full chrome (top bar, centre panels) that wraps every game. Games
/// provide their body via `content`; this view overlays HUD and panels on
/// top based on the shared `GameController` state.
struct GameChrome<Content: View>: View {
    @ObservedObject var controller: GameController
    let onBack: () -> Void
    let content: Content

    init(controller: GameController,
         onBack: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.controller = controller
        self.onBack = onBack
        self.content = content()
    }

    @State private var scorePulse: Bool = false
    @State private var bestPulse: Bool = false

    var body: some View {
        ZStack {
            // The game itself (e.g. SpriteView, SwiftUI grid).
            content

            // Top bar — back button · score (centre) · pause button
            VStack {
                HStack(alignment: .top) {
                    MenuButton(action: onBack)
                        .padding(.top, 12)
                        .padding(.leading, 14)

                    Spacer()

                    VStack(spacing: 0) {
                        Text("\(controller.score)")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.white, Color(white: 0.88)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2)
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                            .scaleEffect(scorePulse ? 1.15 : 1.0)

                        BestScoreLabel(value: controller.bestScore,
                                       label: controller.kind.bestLabel)
                            .scaleEffect(bestPulse ? 1.12 : 1.0)
                            .padding(.top, -2)
                    }
                    .padding(.top, 10)
                    .opacity(controller.hasStarted && !controller.isGameOver ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.25),
                               value: controller.hasStarted && !controller.isGameOver)

                    Spacer()

                    PauseToggleButton(isPaused: controller.isPaused) {
                        controller.togglePause()
                    }
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                    .opacity(controller.hasStarted && !controller.isGameOver ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.25),
                               value: controller.hasStarted && !controller.isGameOver)
                }
                Spacer()
            }

            // Center state panels
            ZStack {
                if controller.isGameOver {
                    GameOverPanel(controller: controller)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else if controller.isPaused {
                    PausePanel()
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else if !controller.hasStarted {
                    ReadyPanel(controller: controller)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .allowsHitTesting(false)
            .animation(.spring(response: 0.35, dampingFraction: 0.78),
                       value: controller.isGameOver)
            .animation(.spring(response: 0.35, dampingFraction: 0.78),
                       value: controller.hasStarted)
            .animation(.spring(response: 0.35, dampingFraction: 0.78),
                       value: controller.isPaused)
        }
        .onChange(of: controller.score) { _ in pulse($scorePulse) }
        .onChange(of: controller.bestScore) { _ in pulse($bestPulse) }
    }

    private func pulse(_ binding: Binding<Bool>) {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) {
            binding.wrappedValue = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                binding.wrappedValue = false
            }
        }
    }
}

// MARK: - Centre panels

struct ReadyPanel: View {
    @ObservedObject var controller: GameController

    var body: some View {
        GlassPanel {
            VStack(spacing: 10) {
                GameIcon(kind: controller.kind, size: 44)
                    .padding(.bottom, 2)
                Text(controller.kind.title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)

                if controller.bestScore > 0 {
                    BestScoreLabel(value: controller.bestScore,
                                   label: controller.kind.bestLabel)
                }

                Text(controller.kind.controlsHint)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.92))
                    .multilineTextAlignment(.center)

                Text("P or Esc to pause during play")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
    }
}

struct PausePanel: View {
    var body: some View {
        GlassPanel {
            VStack(spacing: 10) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                Text("Paused")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                Text("Click or press P to resume")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.85))
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
        }
    }
}

struct GameOverPanel: View {
    @ObservedObject var controller: GameController

    var body: some View {
        GlassPanel {
            VStack(spacing: 10) {
                Text(controller.gameOverTitle)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)

                HStack(spacing: 8) {
                    Text("Score")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                    Text("\(controller.score)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }

                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.86, blue: 0.35))
                    Text("\(controller.kind.bestLabel) \(controller.bestScore)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    if controller.isNewBest {
                        Text("NEW!")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 1.0, green: 0.98, blue: 0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.35)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                    }
                }

                Text("Press Space or click to try again")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.85))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
    }
}

/// Gradient backdrop used as the very back layer for every game. Matches
/// `GameKind.background` so each game has its own mood while sharing the
/// same wrapper chrome.
struct GameBackdrop: View {
    let kind: GameKind

    var body: some View {
        LinearGradient(
            colors: kind.background,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
