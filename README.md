# DisplaySwitcher

A native macOS menu bar app for saving and switching display layouts (arrangement + resolution) with one click. Presets are bound to specific physical displays, the menu adapts to whichever displays are currently connected, and your last-used layout is restored automatically when you plug displays back in.

**中文文档：[README_zh.md](README_zh.md)**

## Features

- **Menu bar app** — click the icon to see all presets available for the currently connected displays; the active one is checkmarked
- **One-click switching** — arrangement (side-by-side / stacked / multi-display) and per-display resolution/refresh rate are applied together
- **Save current layout** — name and save the current arrangement of *all* connected displays, resolutions included
- **Per-display presets** — each preset records the hardware IDs of the displays it was saved with; presets whose displays aren't connected are hidden from the menu
- **Multi-display support** — any number of displays; a preset appears only when all of its displays are online
- **Auto-restore on plug-in** — when the set of connected displays changes, the last-used preset for that combination is applied automatically (resolution-only changes are ignored)
- **Launch at login** — toggle in the menu
- **No permissions required** — the app needs no Accessibility / Screen Recording / Automation permissions
- Also usable as a **CLI** (`layout.sh`)

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`swiftc`, `python3`) — install with `xcode-select --install`
- [displayplacer](https://github.com/jakehilborn/displayplacer) (MIT) — downloaded automatically by the installer

## Install

```bash
git clone https://github.com/canyuexihe/display-switcher.git
cd display-switcher
./install.sh
open /Applications/DisplaySwitcher.app
```

`install.sh` deploys runtime files to `~/.display-switcher`, downloads the displayplacer binary (with a gh-proxy.com mirror fallback for networks where GitHub releases are unreachable), compiles the app, and copies it to `/Applications`.

> Why `~/.display-switcher` and not `~/Documents`? macOS privacy protection (TCC) blocks background processes from accessing `~/Documents`, which breaks script execution. The home-directory location avoids this.

## Usage

### Menu bar

Click the display icon in the menu bar:

| Item | Action |
|---|---|
| Preset names | Click to switch; ✓ marks the currently active layout |
| 保存当前布局… (Save current layout…) | Name and save the current arrangement + resolutions of all connected displays |
| 登录时启动 (Launch at login) | Toggle auto-start |
| 退出 (Quit) | Quit the app |

Presets requiring displays that are not connected are hidden. If no preset matches the current display combination, the menu says so — save a new one for this combination.

### Auto-restore

The app watches for display connect/disconnect events. When the connected combination changes, it applies the preset you last used for that exact combination (after a 2-second debounce). Changing resolution manually does not trigger it.

### CLI

```bash
~/.display-switcher/layout.sh save <name>    # save current layout (all connected displays)
~/.display-switcher/layout.sh apply <name>   # apply a preset (fails with a notification if a required display is offline)
~/.display-switcher/layout.sh list           # list presets
```

## How it works

- [displayplacer](https://github.com/jakehilborn/displayplacer) reads and writes display configuration via CoreGraphics
- Presets are JSON files in `~/.display-switcher/layouts/`, one per layout, recording each display's persistent ID, serial, name, and full configuration string
- `~/.display-switcher/state.json` maps each display combination (sorted hardware IDs) to its last-used preset
- The menu bar app is a single Swift file (`menubar/DisplaySwitcher.swift`) using AppKit + `NSStatusItem`, compiled with `swiftc` — no Xcode project, no dependencies
- Rebuild after editing: `~/.display-switcher/menubar/build.sh`, then copy the `.app` to `/Applications` again and re-toggle "Launch at login"

## Uninstall

1. Quit the app from its menu (turn off "Launch at login" first)
2. Delete `/Applications/DisplaySwitcher.app` and `~/.display-switcher`

## License

MIT — see [LICENSE](LICENSE). Bundles no third-party binaries; the installer downloads [displayplacer](https://github.com/jakehilborn/displayplacer) (MIT License, © Jake Hilborn).