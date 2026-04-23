import SwiftUI

/// The "home" screen of the window: a compact grid of every game the app
/// ships, each card showing the game icon, its title, tagline, and the
/// player's best score for that game.
///
/// Visual style is deliberately consistent with the in-game chrome: sky-blue
/// → warm peach gradient (same palette as the launcher button's default
/// backdrop), soft decorative clouds, and `GlassPanel`-style cards with
/// white-rim borders. Nothing here should feel AI-generated — the menu is
/// the lobby of the same little game world you see inside each game.
struct GameListView: View {
    let bestScores: [GameKind: Int]
    let onPick: (GameKind) -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack {
            // Same sky-blue → peach gradient the launcher button wears when
            // no game is selected. Keeps the menu visually tethered to the
            // button that summons it.
            LinearGradient(
                colors: [
                    Color(red: 0.29, green: 0.50, blue: 0.94),
                    Color(red: 0.65, green: 0.72, blue: 0.96),
                    Color(red: 0.99, green: 0.82, blue: 0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // A couple of soft decorative clouds drifting behind the cards.
            // Non-interactive, very low contrast — they just add texture.
            MenuClouds()
                .allowsHitTesting(false)

            // Subtle sun glow in the top-right — echoes the in-game scenes.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.93, blue: 0.70).opacity(0.55),
                            Color(red: 1.0, green: 0.93, blue: 0.70).opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: 140, y: -220)
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                header
                    .padding(.top, 22)
                    .padding(.horizontal, 18)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(GameKind.allCases) { kind in
                            GameCard(kind: kind,
                                     best: bestScores[kind] ?? 0,
                                     action: { onPick(kind) })
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            // Tiny gamepad badge to echo the launcher button's "home" icon.
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
                    .frame(width: 40, height: 40)
                GamepadIcon(size: 28)
            }
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text("PlayWhile")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                Text("Pick a game")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }

            Spacer()
        }
    }
}

// MARK: - Decorative clouds drifting in the background

/// Two soft, blurred "clouds" that gently drift across the menu. Same visual
/// vocabulary as the in-game Floaty Bird backdrop, but much more restrained
/// so card text stays readable.
private struct MenuClouds: View {
    @State private var drift: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                cloud(size: 160, opacity: 0.55)
                    .offset(x: -geo.size.width * 0.25 + drift * 30,
                            y: geo.size.height * 0.28)
                cloud(size: 220, opacity: 0.35)
                    .offset(x: geo.size.width * 0.22 - drift * 20,
                            y: geo.size.height * 0.62)
                cloud(size: 120, opacity: 0.45)
                    .offset(x: geo.size.width * 0.30 + drift * 40,
                            y: -geo.size.height * 0.10)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                    drift = 1
                }
            }
        }
    }

    private func cloud(size: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().frame(width: size, height: size)
            Circle().frame(width: size * 0.75, height: size * 0.75)
                .offset(x: size * 0.35, y: size * 0.08)
            Circle().frame(width: size * 0.55, height: size * 0.55)
                .offset(x: -size * 0.32, y: size * 0.08)
        }
        .foregroundColor(Color.white.opacity(opacity))
        .blur(radius: 8)
    }
}

// MARK: - Card

/// A single tappable card on the list screen. Same glass treatment as
/// `GlassPanel` (ultra-thin material over a translucent dark fill with a
/// white rim), plus a soft accent rim-glow on hover so each game still
/// feels distinct.
private struct GameCard: View {
    let kind: GameKind
    let best: Int
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                GameIcon(kind: kind, size: 52)
                    .padding(.top, 14)

                Text(kind.title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)

                Text(kind.tagline)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)

                bestBadge
                    .padding(.bottom, 12)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovering ? 0.70 : 0.40),
                                  lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(kind.accent.opacity(isHovering ? 0.85 : 0.0),
                                  lineWidth: 2)
                    .blur(radius: 2)
            )
            .shadow(color: .black.opacity(isHovering ? 0.28 : 0.18),
                    radius: isHovering ? 14 : 8, y: 4)
            .scaleEffect(isPressed ? 0.96 : (isHovering ? 1.02 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovering)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    @ViewBuilder
    private var bestBadge: some View {
        if best > 0 {
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.86, blue: 0.35))
                Text("\(kind.bestLabel) \(best)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.28)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        } else {
            // Reserve the same vertical space so cards line up evenly.
            Text(" ")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .padding(.vertical, 3)
        }
    }
}
