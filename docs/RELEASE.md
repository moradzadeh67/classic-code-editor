# Classic Code Editor — Release and Distribution

## Status

Active. The macOS app is distributed as a **DMG on GitHub Releases**; there is no store listing and no
web/mobile distribution (see Platform Support in the README).

## Current distribution

| Platform | Distribution | Signing |
|---|---|---|
| macOS | `Classic.Code.Editor-<version>.dmg` on the [Releases page](https://github.com/moradzadeh67/classic-code-editor/releases/latest) | **Unsigned and not notarized** — Gatekeeper requires "Open Anyway" on first launch |
| Windows / Linux | Not released (planned) | — |

Latest: **v1.3.0** (`Classic.Code.Editor-1.3.0+5.dmg`, universal build).
Previous: v1.2.0+4, v1.1.0+3.

## How the DMG is built

The release gate lives in `scripts/release_gate/` and runs the whole chain in order:

```bash
scripts/release_gate/01_analyze.sh      # flutter analyze (must be clean)
scripts/release_gate/02_test.sh         # flutter test (offline; 230 tests, 1 opt-in skipped)
scripts/release_gate/03_build_macos.sh  # flutter build macos --release
scripts/release_gate/04_launch_smoke.sh # launches the built app as a smoke test
scripts/release_gate/05_make_dmg.sh     # packages the .app into a DMG via hdiutil
```

`05_make_dmg.sh` reads `version:` from `pubspec.yaml` and names the artifact
`Classic.Code.Editor-<version>.dmg`, so the **pubspec version, the git tag and the DMG name must agree**
(e.g. `1.3.0+5` → tag `v1.3.0` → `Classic.Code.Editor-1.3.0+5.dmg`).

## Checklist before every release

1. `flutter analyze` clean, `flutter test` green (or run `01`/`02`).
2. Bump `version:` in `pubspec.yaml` (`+build` increases every release).
3. Run the whole gate: `03` → `04` → `05`.
4. `gh release create vX.Y.Z "build/distributions/Classic Code Editor-<version>.dmg" --target main \
   --notes-file docs/RELEASE_NOTES_<version>.md` — the DMG lands in `build/distributions/`, **not** in
   `build/macos/Build/Products/Release/` (that folder only holds the `.app`).
5. Optionally attach a `.sha256` of the DMG (`shasum -a 256 "build/distributions/…dmg"`).
6. `README.md` and `CHANGELOG.md` updated for the new version, and `docs/RELEASE_NOTES_<version>.md`
   written (paste it as the GitHub release body).

## Outstanding

- **Notarization**: requires a paid Apple Developer account ($99/yr). Until then every user must use
  "Open Anyway" once. Signing/notarization would remove that step and is the single biggest
  distribution improvement left.
- **Windows / Linux**: planned (v1.x), nothing started.
- No CI builds the DMG automatically yet: `ci.yml` only runs `flutter analyze` + `flutter test` on
  `macos-latest`; the DMG is still built locally by the release gate.
