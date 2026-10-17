# MacToys

[![CI](https://github.com/SPinzon12/MacToys/actions/workflows/ci.yml/badge.svg)](https://github.com/SPinzon12/MacToys/actions/workflows/ci.yml)

A small macOS menu-bar app with quick clipboard and screen utilities behind global
hotkeys — ported from [microsoft/PowerToys](https://github.com/microsoft/PowerToys)
to the Mac:

- **Color Picker** — zoom lens → click → copy HEX.
- **Text Extractor** — drag a region or click a word → OCR → clipboard.
- **Clipboard history + Advanced Paste** — a Spotlight-style panel behind ⌃⇧V:
  search everything you copied, paste it back, or paste it as plain text, OCR,
  a file, JSON or Markdown.
- **Keep Awake** — stop the Mac from sleeping for 15 min, 1 h, 2 h, 4 h or until
  you turn it off, straight from the menu bar.

## Download

Grab the latest **MacToys-<version>.dmg** from
[Releases](https://github.com/SPinzon12/MacToys/releases/latest) — a universal app
for Apple silicon and Intel, macOS 14 or later. Prefer to build it yourself? See
[Build & run](#build--run) and [Build a release](#build-a-release).

## Install

1. Download `MacToys-<version>.dmg` (or the `.zip`) from
   [Releases](https://github.com/SPinzon12/MacToys/releases/latest). Optionally
   check it against the release's `SHA256SUMS`: `shasum -a 256 -c SHA256SUMS`.
2. Open the disk image and drag **MacToys** onto **Applications**.
3. First launch: this build is **not notarized by Apple** yet, so macOS blocks it.
   Double-click it once (macOS refuses), then open **System Settings → Privacy &
   Security**, scroll down and click **Open Anyway** next to "MacToys" (asks
   for your password). On macOS 14 **right-click → Open → Open** also works; from
   macOS 15 on, only Open Anyway does. (Terminal alternative:
   `xattr -dr com.apple.quarantine "/Applications/MacToys.app"`.)
4. A wand icon appears in the menu bar (no Dock icon). Grant the two permissions it
   asks for — see [Required macOS permissions](#required-macos-permissions) — and
   relaunch it.
5. Optional: **Launch at Login** in the menu-bar menu starts it with your Mac.

Requires macOS 14 or later; runs natively on Apple silicon and Intel.

Updating: replace the app in Applications. Because this build is ad-hoc signed,
macOS treats each new version as a new app and asks for the permissions again —
remove the old **MacToys** entries in Privacy & Security and grant them anew.
Coming from the earlier "Mac PowerToys" build: quit it, turn off its Launch at
Login, and delete "Mac PowerToys.app" — otherwise both apps run and watch the
clipboard. Its clipboard history moves over to MacToys automatically on first
launch; remove its old permission entries the same way.

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
click instead copies just the word under the cursor (the full screen is OCR'd
for the hit-test). Esc or right-click cancels (re-pressing the hotkey also
cancels). It needs the same **Screen Recording** permission as the Color Picker.

Performance: the overlay closes as soon as you release the mouse and OCR runs
off the main thread; the result lands with a `Copied …` toast (or `No text
found`). The selection is composited with Core Animation layers, so dragging
costs ~0.1 ms per event instead of repainting the whole retina capture. Vision
OCR usually takes ~40–190 ms, but the **first** `.accurate` request ever made
by a given executable path takes ~26 s while macOS prepares the model (cached
afterwards, also across rebuilds at the same path). The app runs a warm-up pass
at launch to absorb it, and shows `Recognizing text…` if an extraction takes
longer than 400 ms. A slow result never clobbers anything: only the newest
extraction may write, and if you copied something else while it ran, your copy
is kept (`Kept your newer copy`).

**⌃⇧V** opens the clipboard panel — think Spotlight's clipboard view (⌘Space,
then ⌘4). It sits centered in the upper third of the screen under the cursor:

- **Search field** — type to filter; every word must match (case- and
  accent-insensitive) against the text, file names and the source app.
- **History list** (left) — newest first, grouped into Today / Yesterday /
  Earlier, with thumbnails for images and Finder icons for files.
- **Preview** (right) — the full text, image or file list, plus the source app,
  when it was copied, and its size; under it, **Paste as…** lists only the
  transforms valid for the selected item.

| Key        | Action                                              |
| ---------- | --------------------------------------------------- |
| type       | filter                                              |
| ↑ / ↓      | select                                              |
| ⏎          | paste the item as it was copied                     |
| ⌘1 – ⌘9    | paste as the Nth transform in **Paste as…**         |
| esc        | clear the search, then close                        |

Pasting writes the item (or the transform result) to the clipboard and
synthesizes a **⌘V** into the app that had focus before the panel opened; a
pasted item moves back to the top.

**What is recorded.** The pasteboard is polled every 0.5 s. Text, images and
files are kept (files win over text, text wins over a rendered image of it);
copying the same thing again moves it to the top instead of duplicating it.
Copies marked as secret or throwaway by password managers and clipboard tools
(`org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`) are
never recorded, and transform results are not recorded either. The newest 200
items are kept in `~/Library/Application Support/MacToys/` (`history.json`
plus `images/*.png`, owner-only permissions) so history survives a relaunch.
**Clear Clipboard History…** in the status menu deletes all of it.

The transform list:

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
text, menu validity) and the clipboard history rules (capture, secrets,
dedupe, cap, search, persistence) with `swift test`; OCR, transcoding, and paste synthesis
are environment-bound and covered by manual use.

## Keep Awake

**Keep Awake** in the menu-bar menu keeps the Mac from idle-sleeping for 15
minutes, 1, 2 or 4 hours, or indefinitely. A toast confirms it (`Keep Awake on ·
until 15:30`) and another says when it ends. While it is on, the menu-bar icon turns
into a filled cup and the submenu shows the time left and the end time
(`On — 42 min left · until 15:30`); **Add 15 Minutes** pushes a timed run back and
**Turn Off** ends it early. By default the display stays on too; tick **Allow Display to Sleep** to let
the screen turn off while the Mac keeps working (downloads, builds). The setting is
remembered.

It uses the same IOKit power assertions as `caffeinate` (named "MacToys Keep
Awake" in `pmset -g assertions`). macOS releases them when MacToys quits or
crashes, so the Mac can never be left unable to sleep. A timed run is checked
against the clock when the Mac wakes, so it never outlives its end. It does not
keep a closed-lid MacBook awake — that needs administrator changes to the power
settings and is intentionally left out. No hotkey: it is a set-and-forget toggle.

## Design

One small glass idiom across the app: real glass that samples what is behind
the window (Liquid Glass `NSGlassEffectView` on macOS 26+, behind-window
`NSVisualEffectView` before it), hairline borders, a lit rim highlight,
continuous rounded corners, quiet typography, SF Symbols in hierarchical
rendering and a single accent color. Tokens live in
`Sources/MacToys/UI/Theme.swift`. The ⌃⇧V panel is SwiftUI (fade + scale
in, keycap footer, animated selection); the two screen overlays stay AppKit and
paint the same language (rounded accent selection with corner handles and an
outer glow, glass lens card with a crisp pixel grid, swatch, hex and rgb).
Copying from the Color Picker or Text Extractor shows a small glass toast
(`Copied #1E90FF`, `Copied 42 chars`).

The idiom is inspired by a reference macOS menu-bar app; the tokens are
self-authored — that project is GPL and no code was copied from it.

Toolchain note: this CommandLineTools-only environment ships **no
`SwiftUIMacros` plugin**, so SwiftUI macros (`@State`, `@Observable`,
`#Preview`, `@FocusState`) do not compile here. UI state lives in
`ObservableObject` models instead, which are plain Swift and need no plugin.

## Build & run

Requires macOS 14+ and a Swift 6 toolchain with the macOS 26 SDK or newer (Xcode
26+, or just its CommandLineTools — no Xcode project involved).

```sh
swift build
swift run mactoys
```

Quit from the status-item menu (⌘Q). Under `swift run` there is no app bundle:
the menu shows "Development build" and Launch at Login is disabled.

## Build a release

```sh
scripts/build-app.sh        # dist/MacToys.app (universal, ad-hoc signed)
scripts/package-release.sh  # + dist/MacToys-<version>.zip / .dmg / SHA256SUMS
```

The version comes from `VERSION`; the build number defaults to the git commit
count. Overrides: `ARCHS` (default `arm64 x86_64`), `BUNDLE_ID` (default
`dev.spinzon12.MacToys`), `BUILD_NUMBER`, `SIGN_IDENTITY` (default `-`,
ad-hoc). The app icon is rendered from `scripts/make-icon.swift` at build time.

With a **Developer ID Application** certificate, pass it as `SIGN_IDENTITY` and
notarize the result (`xcrun notarytool submit … --wait`, then
`xcrun stapler staple`) so downloads open without the first-launch workaround and
keep their permissions across updates. Notarization needs an Apple Developer
account; this repository does not do it yet.

Publishing: bump `VERSION`, commit, then push a matching tag (`git tag v0.2.0 &&
git push origin v0.2.0`). The **Release** workflow (`.github/workflows/release.yml`)
checks the tag against `VERSION`, runs the tests, packages the app and attaches the
`.dmg`, `.zip` and `SHA256SUMS` to a new GitHub Release. **CI** builds and tests
every push to `main`.

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
   **MacToys**. When running from source (`swift run`), enable your terminal
   app (Terminal/iTerm) instead — a bare executable run from a terminal is
   attributed to the process that launched it.
3. Open **System Settings → Privacy & Security → Accessibility** and enable the
   same entry.
4. Relaunch the app — macOS caches these checks at launch.

## Hotkeys

| Hotkey  | Action                                            |
| ------- | ------------------------------------------------- |
| ⌃⇧C     | Color Picker                                      |
| ⌃⇧O     | Text Extractor                                    |
| ⌃⇧V     | Clipboard history + Advanced Paste                |
| ⌘Q      | Quit (status-item menu)                           |

Chords are registered with Carbon `RegisterEventHotKey`. If a chord is already
taken by another app it is logged at startup and skipped; the menu items keep
working.

## Layout

```
Sources/MacToys/
  main.swift              entry point (accessory NSApplication)
  AppDelegate.swift       status item + menu + wiring
  HotKeys.swift           Carbon global hotkeys
  Permissions.swift       Screen Recording / Accessibility preflight
  Modules/                one module entry per feature
  UI/                     design tokens, clipboard panel, copy toasts
  ColorPicker/            Color Picker overlay (session + lens view)
  TextExtractor/          Text Extractor overlay (session + selection + OCR)
  AdvancedPaste/          coordinator + pure transforms (tested) + ⌘V paste
    History/              clipboard history: capture rules, store, poller
Tests/MacToysTests/       swift-testing suites for transforms + history
Packaging/Info.plist      app bundle Info.plist template
scripts/                  build-app.sh, package-release.sh, make-icon.swift
VERSION                   release version (CFBundleShortVersionString)
.github/workflows/        CI (build + test) and Release (tag → .dmg/.zip)
```

Run the tests with:

```sh
swift test
```

## License

[MIT](LICENSE) — a personal project; use it, change it, share it. Ported modules
keep their upstream notice in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
