# Feature: distribution
Objective: anyone can download Mac PowerToys as a normal macOS app and use it.
Branch: `main` (repo convention, no remote yet). Delivery: ask-on-risk. Test runner:
`swift test` (swift-testing); packaging is checked structurally (bundle layout,
`plutil -lint`, `codesign --verify`, `lipo -archs`, launch smoke).

## Specs
- S1 User request (2026-10-16, verbatim): "comencemos a organizar para que alguien lo
  pueda descargar y usar".
- S2 App bundle: one command builds `dist/Mac PowerToys.app` — universal binary
  (arm64 + x86_64 via per-arch scratch paths + `lipo`), `Info.plist` with
  `LSUIElement` (menu-bar only, no Dock icon), `LSMinimumSystemVersion` 14.0,
  version from a `VERSION` file, app icon, ad-hoc code signature with hardened runtime.
- S3 Release artifacts: one command produces `dist/MacPowerToys-<version>.zip` and
  `.dmg` (drag-to-Applications layout) plus `SHA256SUMS`.
- S4 In-app: "Launch at Login" toggle (`SMAppService.mainApp`) and the version shown
  in the status menu.
- S5 Docs: README "Install" section (download, move to Applications, first open of an
  un-notarized app, permissions) and "Build a release" section; third-party notice
  for microsoft/PowerToys (MIT) since its modules were ported from its source.
- S6 (blocked — needs an Apple Developer ID; `security find-identity` shows 0
  identities) Developer ID signing + notarization, so Gatekeeper opens it without
  the right-click workaround and permissions survive updates.
- S7 (blocked — needs explicit authorization: no git remote) Public repo, GitHub
  Releases, CI that builds the release artifacts.
- S8 Rename (user, verbatim): "vamos a llamar la app MacToys organiza el repo para
  publicar: código fuente y aplicación compilada para descargar." → app MacToys,
  executable `mactoys`, bundle id `dev.spinzon12.MacToys`, artifacts
  `MacToys-<version>.dmg/.zip`; history folder migrated MacPowerToys → MacToys.
  Source in the repo; the compiled app ships as GitHub Release assets (not in git).
- Assumptions (parent defaults): first version 0.1.0; repo name `SPinzon12/MacToys`
  (pending user confirmation; earlier authorization was for `mac-powertoys`).
- License: MIT, copyright "spinzon12" (decided 2026-10-16, see Log).

## Tasks
- [x] D1 — S2 app bundle script `scripts/build-app.sh` + `VERSION` + `Info.plist`
       template. Route: inline. Check: `plutil -lint`, `lipo -archs`, `codesign
       --verify --deep --strict`, bundle launches.
       DONE 30a7298: universal x86_64+arm64, adhoc+runtime, plist lint ok. Launch
       smoke NOT run by parent (user debug instance running) — pending user.
- [x] D2 — S2 app icon generated from source (`scripts/make-icon.swift` →
       `AppIcon.icns`). Route: inline. Check: `iconutil` round-trip, visual check.
       DONE 330d6f1: custom path glyph (SF Symbols license bars them in app icons),
       iconutil ok, visually checked.
- [x] D3 — S3 `scripts/package-release.sh` (zip + dmg + SHA256SUMS). Route: inline.
       Check: `hdiutil verify`, zip extracts to a launchable app.
       DONE b3be270: hdiutil verify ok; zip and dmg copies pass codesign --verify.
- [x] D4 — S4 Launch at Login + version item. Route: inline. Check: `swift build`,
       `swift test`, manual toggle in the bundled app.
       DONE 96e92d8: AppVersion label TDD (3 tests RED→GREEN), 69/69 green;
       NSMenuItemValidation for disabled state under `swift run`. Manual toggle pending user.
- [x] D5 — S5 docs + THIRD_PARTY_NOTICES. Route: inline. Check: structural readback.
       DONE f75432a: README Install / Build a release, THIRD_PARTY_NOTICES (PowerToys
       MIT text fetched verbatim), notice copied into the bundle.
- [ ] D6 — S6 blocked (Developer ID).
- [ ] D7 — S7/S8 publish: rename done + CI/Release workflows written; pending
       confirmation of repo `SPinzon12/MacToys`, then create + push + first CI run,
       then (separate confirmation) tag v0.1.0 release.

## Log
- L1 (2026-10-16) "arregla también lo de los tests, y comencemos a organizar para que
  alguien lo pueda descargar y usar". Tests part done separately: 3990a62.
- Probe: CLT builds release for both `arm64-apple-macosx14.0` and
  `x86_64-apple-macosx14.0`, but both triples share `.build/out/Products/Release`
  (last one wins) → per-arch `--scratch-path` then `lipo`. `iconutil`, `codesign`,
  `hdiutil`, `ditto` present. 0 code-signing identities.
- 2026-10-16: D1–D5 done inline (units < 100 lines each, sequential). Risk: item 5
  (release/installer scripts). Pending: verifier, native review, user smoke of the
  bundled app, license decision, D6 (Developer ID), D7 (publish).
- 2026-10-16 user, verbatim: "dale, pues es un proyecto personal y si alguien lo quiere
  usar adelante" → MIT (the recommended option). LICENSE + README section, LICENSE
  copied into the bundle.
- 2026-10-16 verifier: S2–S5 PASS, 0 blockers. Applied advisories: Gatekeeper steps
  (Open Anyway first; Control-click no longer works on macOS 15+), no fake releases
  page, unsigned app removed on signing failure (trap ERR, tested with a bogus
  identity), BUNDLE_ID validated, zip without __MACOSX, pending Launch-at-Login
  approval cancellable (mixed state). Release rerun: checksums OK, 69 tests green.
- 2026-10-16 native review (3990a62..aa5b3b9, high/item 5): user chose "Skip this
  time" → declined for this candidate; independent verifier PASS stands.
- 2026-10-16: rename to MacToys (72 tests incl. 3 migration tests, RED→GREEN),
  Package tools 6.0 + conditional CLT testing plugin (both branches checked),
  .atl untracked, CI + Release workflows (YAML valid; not yet run on GitHub).
