# Feature: powertoys-core

## Objective
A personal macOS menu-bar utility ("my PowerToys") with three modules ported from
microsoft/PowerToys: **Advanced Paste**, **Text Extractor**, **Color Picker**.

## Problem
PowerToys is Windows-only. The Mac has no single lightweight app that bundles these
three quick clipboard/screen utilities behind global hotkeys.

## Why
User wants the PowerToys workflows on their Mac. The PowerToys repo is open source, so
we port behavior by reading source (no binary reverse engineering — REA not applicable).

## Reference
Sparse checkout of microsoft/PowerToys at:
`/var/folders/4j/5qy3xnnd7678c6znjx3sjdgm0000gn/T/opencode/powertoys-reference`
- `src/modules/AdvancedPaste` — transform list in `AdvancedPaste/Models/PasteFormats.cs`
- `src/modules/PowerOCR` — Text Extractor
- `src/modules/colorPicker` — Color Picker

## Scope (authorized)
- v1: the three modules, menu-bar app, global hotkeys, defaults only (no settings UI).
- Advanced Paste: deterministic transforms only (plain text, image→OCR text, paste as
  .txt/.png/.html file, XML/CSV→JSON, HTML→Markdown, transcode mp3/mp4). AI transforms
  (KernelQuery, CustomTextTransformation, FixSpelling) are OUT of scope — optional and
  off-by-default upstream too.
- Text Extractor: Region + Word modes first; SingleLine/Table later if wanted.
- Color Picker: zoom-lens overlay → click → copy HEX (+ RGB). Editor/history = later.

## Out of scope
Settings UI, clipboard history, AI providers, installer/signing/notarization, localization.

## Constraints
- Toolchain: Swift 6.4 + CommandLineTools only → **SPM executable** (no .xcodeproj).
- Native frameworks only: AppKit/SwiftUI, Carbon hotkeys, NSPasteboard, Vision,
  ScreenCaptureKit/CGImage, AVFoundation (transcode), CGEvent (synthetic paste).
- macOS will require permissions: **Screen Recording** (capture) and **Accessibility**
  (synthetic ⌘V). Document them in README; leave a `ponytail:` note where relevant.
- Artifacts (code, README, docs) in English.
- No network dependency at runtime for v1 (OCR/color/paste transforms are local).

## Architecture decision
Single SPM executable `mac-powertoys`: accessory (`.accessory`) NSApplication, one status
item, Carbon `RegisterEventHotKey` for globals, one coordinator + one module per feature.

## Tasks
- [x] T1 — Skeleton: Package.swift, menu-bar app + status item, global hotkey
       registration, permission request flow (Screen Recording + Accessibility),
       module wiring stubs, README (build/run/permissions). Route: delegated writer.
       Check: `swift build` passes; app runs, status item visible, hotkeys registered.
       DONE 2026-10-13 commit 183adb3 (310 lines). Build green (spot-checked).
       Review: medium/under_budget (no review due yet, slice pending).
       NOTE: manual smoke (status item + hotkeys + permission alert) pending user run.
- [x] T2 — Color Picker: overlay window with magnifier lens, 1×1 pixel sampling,
       click → copy HEX to NSPasteboard. Route: delegated writer.
       Check: `swift build` + manual hotkey run (needs Screen Recording grant).
       DONE 2026-10-13 commit 5bed71e. Build green (spot-checked). Assess: medium,
       under_budget. Manual smoke pending (Esc needs overlay key status; writer
       noted). Uses deprecated CGDisplayCreateImage — ponytail-marked, SCK upgrade
       path.
- [x] T3 — Text Extractor: region-select overlay over screen capture, Vision
       `VNRecognizeTextRequest` on selection, text → clipboard; word-click mode.
       Route: delegated writer. Check: `swift build` + manual run.
       DONE 2026-10-13 commit 36acb96. Build green (spot-checked). Assess medium/
       under_budget. Main display only; OCR sync on main thread (ponytail-marked).
- [x] T4 — Advanced Paste: ⌃⇧V menu listing transforms valid for current clipboard
       content, transform engine (plain text, OCR, file-drop paste, CSV/XML→JSON,
       HTML→MD), synthesized ⌘V via CGEvent. Pure transform functions get tests (TDD:
       RED→GREEN). Route: delegated writer. Check: `swift test` + `swift build`.
       DONE 2026-10-13 commit eba2f01. 42 tests green (swift-testing; XCTest absent
       on CLT toolchain). Audio ships as .m4a (documented swap). Assess medium/
       under_budget. ⌘V synthesis + menu smoke pending user run.

## Test policy
Skeleton/overlay/hotkey code: no meaningful deterministic RED → structural checks
(`swift build`) + manual smoke. Transform engine functions: unit tests first (RED→GREEN).

## Delivery
Strategy: `ask-on-risk` (default). Forecast ≈1200–1800 authored lines across T1–T4.
No remote yet; work-unit commit per task on `main` (repo currently has no remote —
branch/PR strategy decided only if a remote appears).

## Progress log
- 2026-10-13: exploration done (3 modules mapped, path:line handoff in session).
  Toolchain verified: Swift 6.4 / CommandLineTools / SDK 27.0.
- 2026-10-13: T1 done (183adb3, delegated writer, build verified, RDD assess
  medium/under_budget). Slice 9e077c4..183adb3 = 310 lines. Next: T2.
- 2026-10-13: T2 done (5bed71e, delegated writer, build verified + clean rebuild).
  Assess medium/under_budget (provider owns budget math; 700 diff lines, due=false).
  Slice continues 9e077c4... Next: T3.
- 2026-10-13: T3 done (36acb96, delegated writer, build verified). Assess medium/
  under_budget (1140 diff lines, due=false). Next: T4 (last task).
- NOTE (T4 scope decision, parent): true MP3 has no public encoder on Apple
  platforms → audio transcode ships as .m4a (AAC); documented swap, not a silent lie.
- 2026-10-13: T4 done (eba2f01, delegated writer, swift-test 42 green, RED→GREEN
  observed). Assess medium/under_budget (2703 diff lines, due=false — provider
  owns budget math). ALL v1 TASKS COMPLETE. Remaining: user manual smoke on real
  Mac (permissions, hotkeys, OCR, paste synthesis).
