# PlayWhile — Floating arcade for macOS

A lightweight macOS utility that sits quietly in the background and puts a
small, always-on-top **floating button** on your screen. Click it to open a
compact game window containing a five-game arcade:

- **Floaty Bird** — flap through pipes
- **Snake** — eat, grow, don't bite yourself
- **Tetris** — stack and clear lines
- **Minesweeper** — flag the mines
- **Sudoku** — fill the 9×9 grid

Pure Swift + SwiftUI + AppKit + SpriteKit. No third-party dependencies.

## Features

- Circular floating button, always on top of every app, on every Space and
  even over full-screen apps.
- Draggable anywhere on screen — click vs. drag is disambiguated by distance.
- Clicking the button opens the game window without stealing focus from the
  app you were using (Cursor, Chrome, Terminal, …).
- Clicking the button **again** minimizes the game. Minimizing the window
  auto-pauses the active game.
- The button's icon adapts: a generic gamepad while you're browsing the
  list, or the icon of the last game you played.
- Each game saves its own best score / personal record locally.
- Background-only (accessory) app: no Dock icon, no menu bar clutter.

## Requirements

- macOS 13 (Ventura) or later
- Xcode command-line tools (Swift 5.9+). The repo was developed against
  Swift 6.2 / macOS 26 SDK but targets macOS 13 at runtime.

## Build & Run

```bash
make run
```

That compiles a release build, assembles `.build/PlayWhile.app`, and opens it.

Sub-targets:

```bash
make build    # just compile
make bundle   # compile + produce .build/PlayWhile.app
make clean    # remove build artifacts
```

Because the app is marked as `LSUIElement=true` in `Info.plist`, launching it
does **not** add a Dock icon. To quit, right-click the floating button window
in the macOS app switcher (Cmd-Tab) and choose Quit, or run:

```bash
pkill PlayWhile
```

## How to play

Click the floating button (bottom-left of the screen by default) to open the
game window. The window appears just above the button.

Pick a game from the list, or — if you were playing something last time —
you'll be taken straight back to it. Tap the small grid button in the
top-left of any game to return to the list.

Controls per game:

| Game        | Controls                                   |
| ----------- | ------------------------------------------ |
| Floaty Bird | Space / click to flap                      |
| Snake       | Arrow keys or WASD                         |
| Tetris      | Arrow keys or WASD · Space hard drop        |
| Minesweeper | Click to reveal · ⌃Click / right-click flag |
| Sudoku      | Click a cell · 1–9 to fill · Delete to clear |

In any of the action games (Floaty Bird, Snake, Tetris) pressing **any**
key — or clicking **any** mouse button — while on the ready / game-over
screen will start (or restart) the run.

Every game honours **P** or **Esc** to pause, and the pause button in the
top-right of the HUD. Minimizing the window (traffic light yellow, `⌘M`, or
clicking the floating launcher again) **also** auto-pauses the game so you
never come back to a dead bird.

## Project layout

```
Package.swift                   # SwiftPM manifest (executable target)
Makefile                        # Build + .app bundling
Resources/Info.plist            # App bundle metadata (LSUIElement etc.)
Sources/VibeGames/
  main.swift                        # NSApplication bootstrap
  AppDelegate.swift                 # Owns window controllers + last-screen routing
  FloatingButtonWindowController.swift  # Always-on-top NSPanel host
  FloatingButtonView.swift          # Gamepad / per-game launcher icon
  GameWindowController.swift        # Resizable NSWindow hosting the arcade
  GameListView.swift                # Grid of game cards
  GameScene.swift                   # SpriteKit Floaty Bird implementation
  Games/
    GameKind.swift                  # The six games + per-game metadata
    GameController.swift            # Abstract base for every game
    GameHUD.swift                   # Shared HUD (top bar, panels, chrome)
    GameIcons.swift                 # Vector icons per game + gamepad icon
    FloatyBirdController.swift      # Wraps the existing SKScene
    SnakeGame.swift                 # SpriteKit snake
    TetrisGame.swift                # SpriteKit tetris
    MinesweeperGame.swift           # SwiftUI grid
    SudokuGame.swift                # SwiftUI 9×9 puzzle
```

## Design notes

### Always-on-top overlay

The floating button lives in an `NSPanel` subclass with:

- `styleMask = [.borderless, .nonactivatingPanel]` — no chrome, and crucially,
  clicks never activate our app, so focus stays where the user had it.
- `level = .statusBar` — higher than `.floating`, keeps the button above
  virtually every normal window (including other apps' floating panels).
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
  — visible across Space switches and over full-screen apps.
- `hidesOnDeactivate = false` — stays visible when our app isn't active.

### Drag vs. tap

Mouse events are handled at the AppKit layer via a custom `NSView` that
intercepts `hitTest`. `mouseDown` snapshots the cursor position; subsequent
`mouseDragged` events drive the window origin from the true screen-space
delta, which is smoother than SwiftUI gesture deltas. If total travel is
under 4 points on `mouseUp`, it counts as a tap.

### Shared game chrome

Every game exposes a `GameController` (an `@MainActor ObservableObject`) that
publishes `score`, `bestScore`, `isPaused`, `isGameOver`, etc. The top-bar,
pause toggle, ready / paused / game-over panels and the back-to-list button
are all rendered by a single `GameChrome` view that reads from the
controller, so every game is guaranteed to look and behave consistently.

### Pause on minimize

`GameWindowController.windowWillMiniaturize` calls
`activeController?.pauseIfActive()`. Each controller's `pauseIfActive` is
one-way: it only pauses if currently playing, never un-pauses, so the HUD
retains the pause panel when the user restores.

### Last-screen memory

`AppDelegate` persists the last "screen" the user was on (either the list
or a specific game) to `UserDefaults`. Clicking the floating launcher
restores exactly that screen, so closing / quitting and re-opening lands
you back where you left off.

### Keyboard input inside `SpriteView`

SwiftUI's `SpriteView` doesn't reliably forward key events to
`SKScene.keyDown`, so each scene installs an
`NSEvent.addLocalMonitorForEvents` monitor scoped to key-down events while
its view is alive. This gives Space-to-flap / arrow-keys behaviour without
fragile first-responder juggling.
