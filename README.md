# MacToys

[![CI](https://github.com/SPinzon12/MacToys/actions/workflows/ci.yml/badge.svg)](https://github.com/SPinzon12/MacToys/actions/workflows/ci.yml)

Quick clipboard and screen tools for your Mac, one shortcut away — ported from
[Microsoft PowerToys](https://github.com/microsoft/PowerToys). MacToys lives in the
menu bar, works offline, and keeps everything on your Mac.

| Tool | Shortcut | What it does |
| ---- | -------- | ------------ |
| [Color Picker](#color-picker) | ⌃⇧C | Shows the color under the cursor; click to copy it as HEX, RGB or HSL |
| [Text Extractor](#text-extractor) | ⌃⇧O | Copies the text inside any area of the screen (OCR) |
| [Clipboard history](#clipboard-history--advanced-paste) | ⌃⇧V | Search everything you copied; paste it back or as plain text, JSON, Markdown… |
| [Keep Awake](#keep-awake) | — | Keeps the Mac from sleeping for a while, from the menu bar |

Requires **macOS 14 or later** · Apple silicon and Intel · [MIT license](LICENSE)

## Install

1. Download **MacToys-&lt;version&gt;.dmg** from the
   [latest release](https://github.com/SPinzon12/MacToys/releases/latest).
2. Open it and drag **MacToys** onto **Applications**.
3. Open MacToys. macOS blocks it the first time because it isn't notarized by
   Apple — go to **System Settings → Privacy & Security**, scroll down and click
   **Open Anyway** (macOS asks for your password).
4. Give it the two permissions it asks for, then relaunch it — see
   [Permissions](#permissions).

A toy-blocks icon appears in the menu bar (MacToys has no Dock icon). To start it
with your Mac, click the icon and turn on **Open at Login**.

> **Terminal alternative for step 3:**
> `xattr -dr com.apple.quarantine /Applications/MacToys.app`

## Using MacToys

### Menu-bar panel

Click the toy-blocks icon to open the panel:

- **Status chip** — green **Ready**, or what is missing (click it to fix permissions).
- **Tool cards** — one per tool, with its shortcut; click a card to run it.
- **Keep Awake card** — durations, a switch and a live countdown.
- **Clear History**, **Open at Login** and **Quit**.

Esc or a click elsewhere closes it.

### Color Picker

**⌃⇧C** — a small chip follows the cursor, filled with the color under it and
showing its code.

| Action | Result |
| ------ | ------ |
| Move the mouse | The chip updates live |
| Scroll up / down | Shows a magnifier and zooms in (4× – 16×) / zooms out and hides it |
| Click or ⏎ | Copies the color and opens the result card |
| Esc, right-click or ⌃⇧C | Cancels |

The **result card** shows the color's closest name (`≈ Dodger Blue`) and one row
per format — HEX, RGB, HSL. Click a row to copy it; that format becomes your
default for next time. Your last 10 colors sit underneath (click one to reuse
it). **Pick Again** (⌘P) starts over; Esc closes the card.

### Text Extractor

**⌃⇧O** — the screen dims.

- **Drag** over an area to copy all the text inside it.
- **Click** a single word to copy just that word.
- **Esc** or right-click cancels.

A toast confirms the result (`Copied 42 chars`, `Copied word` or `No text found`).
If you copy something else while the text is still being read, your newer copy is
kept.

> The very first extraction after installing can take about 30 seconds while
> macOS prepares its text-recognition model. MacToys starts that preparation at
> launch, and later extractions take a fraction of a second.

### Clipboard history & Advanced Paste

**⌃⇧V** opens a Spotlight-style panel with everything you copied: search on top,
your history on the left (Today / Yesterday / Earlier), and a preview of the
selected item on the right.

| Key | Action |
| --- | ------ |
| Type | Filter by text, file name or source app |
| ↑ ↓ | Select |
| ⏎ | Paste the item as it was copied |
| ⌘1 – ⌘9 | Paste it transformed (see **Paste as…** below) |
| Esc | Clear the search, then close |

The item is pasted straight into the app you were using. **Paste as…** only lists
the transforms that fit the selected item:

| Transform | From |
| --------- | ---- |
| Plain Text | Text or HTML — formatting removed |
| Image to Text | An image — text recognized with OCR |
| Paste as .txt / .png / .html file | Text, image or HTML — saved to a file and pasted as that file |
| JSON | CSV (with a header row) or XML |
| Markdown | HTML |
| Video → MP4, Audio → M4A | A copied video or audio file |

### Keep Awake

In the panel's **Keep Awake** card, pick **15m**, **1h**, **2h**, **4h** or **∞**
(or flip the switch). While it is on:

- the menu-bar icon becomes a filled cup and the card counts down
  (`42 min left · until 15:30`);
- **+15m** adds time, and the switch turns it off;
- a toast tells you when it starts and when it ends.

The screen stays on too; tick **Allow display to sleep** if you only need the Mac
working (downloads, builds). Quitting MacToys always lets the Mac sleep again.
Keep Awake does not keep a closed-lid MacBook awake.

## Permissions

| Permission | Needed by | Why |
| ---------- | --------- | --- |
| Screen Recording | Color Picker, Text Extractor | To read the pixels and text on screen |
| Accessibility | Clipboard history | To paste (⌘V) into the app you were using |

MacToys opens its **Permissions** window when something is missing (also from the
status chip in the panel). For each permission:

1. Click **Grant…** and accept the macOS dialog.
2. Turn on **MacToys** in the System Settings pane that opens.
3. Click **Relaunch MacToys** — macOS applies Screen Recording only after a
   restart.

The window shows each permission's status live.

## Troubleshooting

| Problem | Fix |
| ------- | --- |
| A permission is **ON** in System Settings but MacToys still can't use it | In the Permissions window, click **Reset Permissions…**, then grant both again. This is common after an update. |
| macOS says MacToys "can't be opened" | **System Settings → Privacy & Security → Open Anyway** (see [Install](#install)). |
| A shortcut does nothing | Another app may already use it; the tool cards in the panel still work. |
| The first Text Extractor run is slow | Expected once after installing — see [Text Extractor](#text-extractor). |
| Running from source, permissions don't stick | Grant them to your terminal app (Terminal, iTerm…), not to MacToys. |

## Updating

Download the new version and replace the app in **Applications**. macOS treats
every new version as a new app, so it asks for the permissions again. If the old
entries get in the way, use **Reset Permissions…** (see above).

Coming from the older **Mac PowerToys** app: quit it, turn off its login item and
delete it. Your clipboard history moves over to MacToys automatically.

## Privacy

- Nothing leaves your Mac: MacToys makes no network requests.
- Clipboard history (the newest 200 items) is stored only in
  `~/Library/Application Support/MacToys/`, readable by your user only.
  **Clear History** in the panel deletes it.
- Copies that password managers mark as secret are never recorded.

## Development

### Build and run

Requires a Swift 6 toolchain with the macOS 26 SDK or newer: Xcode 26+, or just
its Command Line Tools. There is no Xcode project.

```sh
swift build
swift run mactoys     # runs from source: permissions belong to your terminal
swift test
```

### Build a release

```sh
scripts/build-app.sh        # → dist/MacToys.app (universal, ad-hoc signed)
scripts/package-release.sh  # → dist/MacToys-<version>.dmg, .zip and SHA256SUMS
```

| Setting | Default | Notes |
| ------- | ------- | ----- |
| `VERSION` file | — | The release version |
| `BUILD_NUMBER` | git commit count | |
| `ARCHS` | `arm64 x86_64` | |
| `BUNDLE_ID` | `dev.spinzon12.MacToys` | |
| `SIGN_IDENTITY` | `-` (ad-hoc) | |

**Publishing:** bump `VERSION`, commit, then push a matching tag
(`git tag v0.4.0 && git push origin v0.4.0`). The
[Release workflow](.github/workflows/release.yml) runs the tests and publishes
the `.dmg`, `.zip` and `SHA256SUMS` as a GitHub Release. [CI](.github/workflows/ci.yml)
builds and tests every push to `main`.

### Project layout

```
Sources/MacToys/
  AppDelegate.swift      status item, menu-bar panel wiring
  HotKeys.swift          global shortcuts (Carbon)
  Permissions.swift      Screen Recording / Accessibility
  Modules/               one entry point per tool
  ColorPicker/           chip + zoom session, formats, recent colors, color names
  TextExtractor/         overlay, selection, OCR
  AdvancedPaste/         clipboard panel coordinator, transforms, ⌘V
    History/             clipboard history: capture rules, storage, polling
  KeepAwake/             power assertions and timing
  UI/                    design tokens, panels, cards, toasts
Tests/MacToysTests/      swift-testing suites
Packaging/Info.plist     app bundle template
scripts/                 build-app.sh, package-release.sh, make-icon.swift
.github/workflows/       CI and Release
```

### Notes for contributors

- **No SwiftUI macros.** The Command Line Tools toolchain ships no
  `SwiftUIMacros` plugin, so `@State`, `@Observable` and `#Preview` don't compile.
  UI state lives in `ObservableObject` models instead.
- **Design tokens** live in `Sources/MacToys/UI/Theme.swift`: glass surfaces
  (Liquid Glass on macOS 26+), hairline borders, and the purple brand accent.
- **Tests** cover the logic that doesn't need a screen: transforms, clipboard
  history, color formats and names, Keep Awake timing, permissions. Drawing,
  capture and pasting are checked by hand.

## Credits & license

[MIT](LICENSE) — a personal project; use it, change it, share it.

The Color Picker, Text Extractor and Advanced Paste tools port the behavior of
[Microsoft PowerToys](https://github.com/microsoft/PowerToys) (MIT); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The visual style is inspired by
[vorssaint-utils](https://github.com/vorssaint/vorssaint-utils); no code was copied.
