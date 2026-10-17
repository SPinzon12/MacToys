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
- [ ] U2 — S4 glass menu-bar panel. Route: inline.
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
