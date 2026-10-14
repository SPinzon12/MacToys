# mac-powertoys

A personal macOS menu-bar utility ("my PowerToys"): three quick clipboard/screen
utilities from [microsoft/PowerToys](https://github.com/microsoft/PowerToys) ported
to the Mac behind global hotkeys.

- **Color Picker** — zoom lens → click → copy HEX (and RGB).
- **Text Extractor** — select a screen region → OCR → clipboard.
- **Advanced Paste** — deterministic clipboard transforms (plain text, OCR, files,
  CSV/XML→JSON, HTML→Markdown) behind ⌃⇧V.

## Status

| Module         | Hotkey | T1 (skeleton)       | T2 (Color Picker) | T3 (Text Extractor) | T4 (Advanced Paste) |
| -------------- | ------ | ------------------- | ----------------- | ------------------- | ------------------- |
| Color Picker   | ⌃⇧C    | ✅ wired (stub)     | ⬜ overlay + HEX   | —                   | —                   |
| Text Extractor | ⌃⇧O    | ✅ wired (stub)     | —                 | ⬜ region OCR        | —                   |
| Advanced Paste | ⌃⇧V    | ✅ wired (stub)     | —                 | —                   | ⬜ transforms + tests |

- ✅ = done · ⬜ = planned · — = not applicable

T1 delivers the skeleton: menu-bar status item, global hotkey registration,
permission preflight, and module stubs. Run the app now and each hotkey logs
`...: not implemented yet (Tn)`.

## Build & run

Requires macOS 14+ and the Swift toolchain (Swift 6.4 / CommandLineTools — no Xcode
project involved).

```sh
swift build
swift run mac-powertoys
```

Quit from the status-item menu (⌘Q).

## Required macOS permissions

Two permissions are required for the full feature set:

| Permission        | Needed by                     | System Settings pane |
| ----------------- | ----------------------------- | -------------------- |
| Screen Recording  | Color Picker, Text Extractor  | Privacy & Security → Screen Recording |
| Accessibility     | Advanced Paste (synthetic ⌘V) | Privacy & Security → Accessibility |

Steps:

1. Launch the app once — it shows a single alert listing any missing permission
   and can open the right pane for you.
2. Or open **System Settings → Privacy & Security → Screen Recording** and enable
   your terminal app (Terminal/iTerm) or `mac-powertoys` — a bare executable run
   from a terminal is attributed to the process that launched it.
3. Open **System Settings → Privacy & Security → Accessibility** and enable the
   same entry.
4. Relaunch the app — macOS caches these checks at launch.

## Hotkeys

| Hotkey  | Action                                            |
| ------- | ------------------------------------------------- |
| ⌃⇧C     | Color Picker                                      |
| ⌃⇧O     | Text Extractor                                    |
| ⌃⇧V     | Advanced Paste                                    |
| ⌘Q      | Quit (status-item menu)                           |

Chords are registered with Carbon `RegisterEventHotKey`. If a chord is already
taken by another app it is logged at startup and skipped; the menu items keep
working.

## Layout

```
Sources/MacPowerToys/
  main.swift              entry point (accessory NSApplication)
  AppDelegate.swift       status item + menu + wiring
  HotKeys.swift           Carbon global hotkeys
  Permissions.swift       Screen Recording / Accessibility preflight
  Modules/                one stub per feature
```
