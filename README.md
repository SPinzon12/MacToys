# mac-powertoys

A personal macOS menu-bar utility ("my PowerToys"): three quick clipboard/screen
utilities from [microsoft/PowerToys](https://github.com/microsoft/PowerToys) ported
to the Mac behind global hotkeys.

- **Color Picker** — zoom lens → click → copy HEX.
- **Text Extractor** — drag a region or click a word → OCR → clipboard.
- **Advanced Paste** — deterministic clipboard transforms (plain text, OCR, files,
  CSV/XML→JSON, HTML→Markdown) behind ⌃⇧V.

## Status

| Module         | Hotkey | T1 (skeleton)       | T2 (Color Picker) | T3 (Text Extractor) | T4 (Advanced Paste) |
| -------------- | ------ | ------------------- | ----------------- | ------------------- | ------------------- |
| Color Picker   | ⌃⇧C    | ✅ wired (stub)     | ✅ lens → HEX copy  | —                   | —                   |
| Text Extractor | ⌃⇧O    | ✅ wired (stub)     | —                 | ✅ region + word OCR | —                   |
| Advanced Paste | ⌃⇧V    | ✅ wired (stub)     | —                 | —                   | ✅ transforms + tests |

- ✅ = done · ⬜ = planned · — = not applicable

All four tasks are done.

T1 delivers the skeleton: menu-bar status item, global hotkey registration,
permission preflight, and module stubs. T2 delivers the Color Picker: **⌃⇧C**
opens a magnified lens that follows the cursor; left-click copies the pixel
under the cursor as `#RRGGBB` to the clipboard, Esc or right-click cancels
(re-pressing the hotkey also cancels). It needs the **Screen Recording**
permission — without it, one alert explains where to grant it.

T3 delivers the Text Extractor: **⌃⇧O** captures the main display once and
shows it dimmed behind an overlay. Drag a rectangle to OCR that region into
the clipboard (small crops are upscaled ×1.5 first, like PowerOCR); a plain
click instead copies just the word under the cursor — the full screen is OCR'd
once and cached, so later clicks are instant. Esc or right-click cancels
(re-pressing the hotkey also cancels). It needs the same **Screen Recording**
permission as the Color Picker.

T4 delivers Advanced Paste: **⌃⇧V** reads the clipboard and pops a glass panel at
the cursor listing only the transforms valid for the current content, grouped
into Text / Files / Media with a clipboard preview chip. Choosing one
transforms the clipboard, writes the result back, and synthesizes a **⌘V** into
the app that had focus before the panel opened. The transform list:

- **Plain Text** — from text or HTML (tags stripped, entities decoded).
- **Image to Text (OCR)** — Vision OCR of a clipboard image.
- **Paste as .txt / .png / .html file** — writes a unique temp file and puts
  its file URL on the clipboard (Finder-style paste).
- **XML/CSV → JSON** — leading `<` means XML (Foundation `XMLParser`), else
  CSV with a header row; pretty-printed JSON lands on the clipboard.
- **HTML → Markdown** — minimal subset (h1–h6, p, br, strong, em, links,
  lists, code, pre, blockquote); everything else is stripped to text.
- **Video → MP4** / **Audio → M4A** — `AVAssetExportSession` transcode of a
  copied media file. Upstream PowerToys offers MP3, but Apple ships no public
  MP3 encoder, so audio lands as AAC/`.m4a` instead — the honest swap.

The synthetic ⌘V needs the **Accessibility** permission — without it the
transform still runs and the result still lands on the clipboard, but
auto-paste is skipped and one alert explains where to grant the permission.

Unit tests cover the pure transforms (CSV/XML → JSON, HTML → Markdown, plain
text, menu validity) with `swift test`; OCR, transcoding, and paste synthesis
are environment-bound and covered by manual use.

## Design

One small glass idiom across the app: translucent `ultraThinMaterial` surfaces,
hairline borders, a lit rim highlight, continuous rounded corners, quiet
typography and a single accent color. Tokens live in
`Sources/MacPowerToys/UI/Theme.swift`; the ⌃⇧V Advanced Paste panel is SwiftUI
(hover, grouping, keyboard navigation, clipboard preview chip) while the two
screen overlays stay AppKit and paint the same language (rounded accent
selection + size chip, glass lens card with grid and swatch, bottom-center hint
pills).

The idiom is inspired by a reference macOS menu-bar app; the tokens are
self-authored — that project is GPL and no code was copied from it.

Toolchain note: this CommandLineTools-only environment ships **no
`SwiftUIMacros` plugin**, so SwiftUI macros (`@State`, `@Observable`,
`#Preview`, `@FocusState`) do not compile here. UI state lives in
`ObservableObject` models instead, which are plain Swift and need no plugin.

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
  Modules/                one module entry per feature
  UI/                     design tokens + SwiftUI Advanced Paste panel
  ColorPicker/            Color Picker overlay (session + lens view)
  TextExtractor/          Text Extractor overlay (session + selection + OCR)
  AdvancedPaste/          transform menu + pure transforms (tested) + ⌘V paste
Tests/MacPowerToysTests/  swift-testing suites for the transform engine
```

Run the tests with:

```sh
swift test
```
