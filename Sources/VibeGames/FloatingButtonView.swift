import SwiftUI

/// The visible circular floating button. It renders a scenic "sky disc"
/// backdrop common to every state, and then swaps the foreground content:
///
///  - When `kind` is nil, a generic gamepad icon is shown.
///  - When `kind` is set, that game's icon is shown — so whatever game the
///    user last played / minimised is what the button advertises.
///
/// All mouse interaction (tap / drag) is handled by the NSView container
/// that owns this view (see `FloatingButtonWindowController`).
struct FloatingButtonView: View {
    let diameter: CGFloat
    @ObservedObject var state: FloatingButtonState

    @State private var bob: CGFloat = 0
    @State private var glint: CGFloat = -1

    var body: some View {
        ZStack {
            // Sky disc base
            Circle()
                .fill(
                    LinearGradient(
                        colors: backdropColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Distant hill silhouette
            Ellipse()
                .fill(Color.black.opacity(0.22))
                .frame(width: diameter * 1.35, height: diameter * 0.55)
                .offset(y: diameter * 0.38)
                .clipShape(Circle())

            // Foreground — either the game icon or a gamepad.
            Group {
                if let kind = state.kind {
                    GameIcon(kind: kind, size: diameter * 0.58)
                } else {
                    GamepadIcon(size: diameter * 0.60)
                }
            }
            .offset(y: bob)

            // Diagonal shine sweep
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.22), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .rotationEffect(.degrees(20))
                .offset(x: glint * diameter)
                .blendMode(.plusLighter)
                .clipShape(Circle())

            Circle()
                .strokeBorder(Color.white.opacity(0.65), lineWidth: 1.6)

            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 3)
                .blur(radius: 2)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(state.isPressed ? 0.90 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.55),
                   value: state.isPressed)
        // Spring the icon swap so changing games feels intentional.
        .animation(.spring(response: 0.35, dampingFraction: 0.7),
                   value: state.kind)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                bob = -3
            }
            withAnimation(.linear(duration: 5.5).repeatForever(autoreverses: false)) {
                glint = 1
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Backdrop colours track the highlighted game's own background so the
    /// launcher feels "themed" to whatever it would open next.
    private var backdropColors: [Color] {
        if let kind = state.kind {
            return kind.background
        }
        return [
            Color(red: 0.29, green: 0.50, blue: 0.94),
            Color(red: 0.99, green: 0.82, blue: 0.75)
        ]
    }
}

/// Observable bridge from the AppKit-level drag/tap container to SwiftUI.
/// Also carries the `kind` so the button icon stays in sync with the
/// current/minimised game without needing to rebuild the SwiftUI view
/// hierarchy.
final class FloatingButtonState: ObservableObject {
    @Published var isPressed: Bool = false
    /// `nil` → show the gamepad icon; `.someKind` → show that game.
    @Published var kind: GameKind? = nil
}
