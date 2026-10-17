# Feature: ui-refresh
Objective: MacToys looks and feels like a polished Mac app: new toy-blocks logo, a
glass menu-bar panel instead of the plain menu, first-run onboarding, Settings.
Branch: `main` (repo convention). Delivery: ask-on-risk. Runner: `swift test`; visual
work checked with real-window screenshots (no UI test runner on this toolchain).

## Specs
- S1 User request (2026-10-17, verbatim): "estoy teniendo problemas con los permisos
  no me funciona. pensemos en mejorar ahora la UI Y UX y cambiar el logo".
- S2 Permissions: request (not just check) so MacToys is listed in System Settings;
  live Permissions window with Grant / Relaunch / Reset (scoped tccutil).
  DONE c08dbdf (see Tasks).
- S3 Logo — user chose "Bloques de juguete (Recommended)": "Tres cubitos redondeados
  apilados en distintos tonos del degradé: lee 'Toys' al instante, es simple y escala
  bien a 16 px en la barra." App icon + matching monochrome menu-bar glyph. Preview
  shown to the user before it replaces the current icon (promised).
- S4 Menu-bar panel: glass panel replacing the NSMenu — header (logo, version),
  module cards with keycap shortcuts, Keep Awake card (durations + live countdown),
  footer (permission status, Settings, Quit).
- S5 First-run onboarding: modules, shortcuts, permissions step.
- S6 Settings window: hotkeys, history size, Launch at Login, Keep Awake default.
- Order agreed in conversation: logo and panel first, then onboarding and Settings.

## Tasks
- [x] U0 — S2 permissions fix. Route: inline. DONE c08dbdf + relaunch-waits-for-PID
       follow-up; 86 tests (4 new); window screenshot checked; independent verifier
       PASS, 0 blockers (item 2).
- [x] U1 — S3 toy-blocks icon + menu-bar glyph. Preview shown; user: "Aprobado,
       usalo". Route: inline. DONE: make-icon.swift Blocks drawing, BrandGlyph
       template image; icon extracted from the built bundle and checked.
- [x] U2 — S4 glass menu-bar panel. Route: inline. DONE ce64fa3 (shared
       GlassSurface) + 026d241 (MenuPanel, AppDelegate without NSMenu); 89 tests
       (3 new label helpers); both states screenshot-checked (footer wrap fixed).
       Pending: independent verifier (item 6), user smoke of click/Esc/outside-close.
- [ ] U3 — S5 onboarding. Route: inline.
- [ ] U4 — S6 Settings window. Route: inline.

## Log
- L1 (2026-10-17) "estoy teniendo problemas con los permisos no me funciona. pensemos
  en mejorar ahora la UI Y UX y cambiar el logo".
- Diagnosis: old flow only checked AXIsProcessTrusted/CGPreflightScreenCaptureAccess
  (never lists the app in System Settings); ad-hoc rebuilds change the cdhash so old
  grants stop matching. Probe run from the agent's terminal had both grants, so
  `swift run` works; the .app path is the broken one.
- 2026-10-17: permissions verifier PASS (advisory applied: relaunch waits for the
  old PID). Logo approved and applied.
- 2026-10-17: panel done; paused for user feedback before U3 onboarding / U4
  Settings (big visual change — feedback first).
- 2026-10-17 user (verbatim): "aveces veo un pantalla roja en los permisos" →
  cause: system accent is red (AppleAccentColor 0) and the UI used it; fixed with a
  brand accent (logo indigo-violet) + orange for attention (5a4bd21).
- Panel verifier: FAIL 1 blocker — Text Extractor captured the fading panel. Fixed:
  close(animated: false) + CATransaction.flush (measured: region diff 0.315 → 0.000),
  close on resign-key, Esc scoped to the panel, VoiceOver label, login pending state
  (6e158d8).
- 2026-10-17 user (verbatim): "y mejores el ui del color picker esta muy basico no me
  gusto. lo de mas super y tambien cuando haga click en clipboard me apreca el
  historial. y por algun motivo hay bordes negros por fuera y me gusto el color. y no
  ue hiciste pero el color morado bacano tal vez usar el color qeu tenga el sistema"
  → black square corners: glass clipped to radius (3f8e01a); Clipboard card opened
  the history unfocused (reproduced key:false) → non-activating key panel (e8ca3ba);
  Color Picker redesign: round loupe + color ring + HEX/RGB/HSL (833eb4b, 6 tests).
  Accent decision — user chose "Morado MacToys (Recommended)": always the logo
  purple (Theme.accentNS), not the system accent. Already in place (5a4bd21).
- Color Picker verifier: PASS, 0 blockers (cursor hide/unhide balanced on every
  exit; sampling unchanged; HSL matches colorsys). Applied: card clamped to the
  cursor's display (multi-display gap), stale comments, unused helper removed.
  94 tests. Next: U3 onboarding, U4 Settings.
- 2026-10-17 user (verbatim): "EL COLOR PICKER QUEDO MUY RARO REVISEMOS UI Y UX
  guiemos de cosas actuales. se ve horrible y mala experiencia" → reviewed current
  practice (macOS NSColorSampler loupe, ColorSlurp/Sip result card + history,
  PowerToys). User chose "Lupa nativa + tarjeta (Recommended)". Done c1fb266: system
  loupe (no Screen Recording needed), auto-copy in default format, glass result card
  (≈ CSS name, HEX/RGB/HSL rows, 10 recent colors, Pick Again ⌘P). Old custom lens
  removed. 101 tests (7 new). Sampler exercised for real (shown, Esc → nil); card
  screenshot-checked.
