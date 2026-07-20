# MyAltTab

A window-level task switcher for macOS, written in Swift. One feature, done well:
hold ⌥, tap Tab, see every window everywhere, release to switch.

![MyAltTab switcher](screenshot.png)

## Usage

| Keys | Action |
|---|---|
| ⌥ Tab (hold ⌥) | Open the switcher / cycle forward |
| ⌥ ⇧ Tab | Cycle backward |
| ← / → | Move selection while open |
| release ⌥ | Switch to the selected window |
| Esc | Cancel |

The switcher shows one tile per window — every app, every desktop (Space), minimized and
hidden windows included — ordered most-recently-used first, with live thumbnails and a
full-size preview of the selection drawn at its real position. Selecting a window on
another desktop switches to that desktop.

The menu bar icon has **Settings…** (⌘,):

- **Include Finder windows** — off by default
- **Start at login**

## Build

```sh
./build.sh
ditto build/MyAltTab.app /Applications/MyAltTab.app
open /Applications/MyAltTab.app
```

Plain `swiftc`, no Xcode project. Building needs only the free Xcode Command Line Tools —
no Apple Developer account.

The script signs with an Apple Development identity when one is present and falls back to
ad-hoc signing otherwise. Ad-hoc builds work fine, but every rebuild looks like a new app
to macOS, so you may have to re-grant Accessibility and Screen Recording after rebuilding
(toggle the entries off and on in System Settings). To avoid that without an Apple
account, create a self-signed code-signing certificate (Keychain Access → Certificate
Assistant → Create a Certificate, type "Code Signing") and build with:

```sh
CODESIGN_IDENTITY="My Code Signing Cert" ./build.sh
```

Requires macOS 14+; built and tested on macOS 26.

## Permissions

- **Accessibility** — the ⌥Tab event tap and window raising
- **Screen Recording** — window thumbnails (ScreenCaptureKit); without it tiles fall back
  to app icons

Both are prompted on first launch. Accessibility is picked up while running; no relaunch
needed.

Cross-desktop switching uses the Mission Control "Move left/right a space" shortcuts
(^← / ^→), so those must stay enabled in System Settings → Keyboard → Shortcuts.
