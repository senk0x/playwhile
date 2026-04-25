# PlayWhile - Floating arcade for macOS (the best tool for coders with ADHD)

<img width="400" height="220" alt="recording_edited (1)" src="https://github.com/user-attachments/assets/146acecb-90ca-4e79-bea9-1772e3bcd3ce" />


I built this out of a very real (and slightly embarrassing) problem.

When I was vibe-coding apps with AI, I kept running into the same thing:
you ask an LLM to generate something… and then you just sit there waiting.

Not long enough to switch tasks.
Not short enough to stay focused.

Scrolling social networks or opening YouTube would instantly kill the flow.
But doing nothing felt even worse.

So I made **PlayWhile** - a tiny floating arcade that sits on top of everything
and lets you play quick games *without leaving what you’re doing*.

Now I use it constantly:

* while AI is generating code
* while waiting for an LLM response
* during long Zoom calls
* while watching lectures on YouTube
* basically any time there’s “dead time” but I don’t want to break focus

Honestly, it’s a must-have if your brain hates idle time.

---

## What it is

A lightweight macOS utility that lives quietly in the background and shows a
small, always-on-top **floating button**.

Click it → a compact arcade opens right above it.

No app switching. No context loss. No distractions.

---

## Games included

* **Floaty Bird** - flap through pipes
* **Snake** - eat, grow, don't die
* **Tetris** - stack and clear lines
* **Minesweeper** - find and flag mines
* **Sudoku** - classic 9×9 puzzle

All games are designed for **quick sessions** — play for 30 seconds, close, continue working.

---

## Why this exists

This is not just “games on Mac”.

It solves a very specific problem:

> **What do you do in micro-waiting moments without breaking your flow?**

PlayWhile gives you:

* something to do for 10–60 seconds
* zero friction to open/close
* no context switching
* no productivity guilt spiral

It’s like fidgeting - but actually fun.

---

## Features

* Always-on-top floating button (works over full-screen apps too)
* Lives across all Spaces
* Drag it anywhere on your screen
* Click → opens game window without stealing focus
* Click again → instantly hides it
* Auto-pause when minimized
* Remembers last played game
* Each game tracks your personal best score
* No Dock icon, no menu bar clutter (background-only app)

---

## Tech stack

* Swift
* SwiftUI
* AppKit
* SpriteKit
* No third-party dependencies

---

## Requirements

* macOS 13 (Ventura) or later
* Swift 5.9+

---

## Build & Run

```bash
make run
```

Other commands:

```bash
make build    # compile only
make bundle   # build .app
make clean    # remove build artifacts
```

Since the app runs as a background utility (`LSUIElement=true`), it won’t show in the Dock.

To quit:

```bash
pkill PlayWhile
```

---

## How to use

1. Launch the app
2. Click the floating button (bottom-left by default)
3. Pick a game
4. Play for a bit
5. Click again → go back to work

That’s it.

---

## Controls

| Game        | Controls                                   |
| ----------- | ------------------------------------------ |
| Floaty Bird | Space / click to flap                      |
| Snake       | Arrow keys or WASD                         |
| Tetris      | Arrow keys or WASD · Space hard drop       |
| Minesweeper | Click to reveal · right-click to flag      |
| Sudoku      | Click cell · 1–9 to fill · Delete to clear |

All action games:

* Press any key / click to start or restart
* `P` or `Esc` to pause

---

## Philosophy

This app is built around one idea:

> **Don’t break focus - just fill the gaps.**

It’s not meant to replace your work.
It’s meant to make the waiting parts less painful.

---

## Future ideas

* More quick games (2048, Pong, etc.)
* Custom game packs
* Minimal stats / streak tracking
* Sound toggle & themes

---

If you’re building with AI, you’ll probably end up using this more than you expect.
