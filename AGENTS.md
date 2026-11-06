# AGENTS.md

Guidance for coding agents working in this repository.

## What this project is

A single-file native macOS application (Swift + AppKit) that displays the live status of a locally running oMLX server in a transparent, always-on-top window. It is not a library, has no package manager, and has no third-party dependencies.

## Layout

```
Sources/OMLXMonitor.swift   Entire application: HTTP client, data model, layout, localization, CLI flags
Sources/DrawIcon.swift      Renders the ten required .icns sizes with AppKit; no image assets in git
Info.plist                  Bundle metadata (LSUIElement, CFBundleIconFile=AppIcon)
build.sh                    Compile -> render icon -> assemble bundle -> ad-hoc sign -> self-test
llms.txt                    Machine-readable project summary
docs/*.svg                  Interface previews and icon used by the READMEs
```

## Build and verify

```bash
./build.sh                                   # produces dist/oMLX Status HUD.app and runs the self-test
dist/"oMLX Status HUD.app"/Contents/MacOS/OMLXMonitor --self-test        # parsing, layout, bilingual strings
dist/"oMLX Status HUD.app"/Contents/MacOS/OMLXMonitor --probe            # one real request against the local server
dist/"oMLX Status HUD.app"/Contents/MacOS/OMLXMonitor --gui-diagnostic   # window geometry and menu structure
```

`--self-test` exits 0 only if decoding, display formatting, layout across all 16 width/height/text-size combinations, and both language tables pass. Run it after any change to parsing, strings, or layout.

## Conventions

- Swift 5 language mode, AppKit only. Do not introduce SwiftUI, SPM, CocoaPods, or external packages; the absence of a dependency graph is a deliberate design constraint.
- Keep every user-visible string inside the `L.t("中文", "English")` table. Adding a language means extending `InterfaceLanguage` and the table, not sprinkling conditionals.
- Chinese and English text are always edited together; never update one README without the other.
- Layout arithmetic lives in `contentHeight(modelCount:hasMore:)` and `render()`. If you change row heights, change both or the panel will clip.

## Security constraints

- Never print, log, persist, or display the oMLX API key. It is read from `~/.omlx/settings.json` per request and must stay in memory.
- Never weaken the redirect refusal in `NoRedirects`; it prevents a credential from being forwarded to another origin.
- Never add outbound network calls beyond `127.0.0.1`.
- The app must remain read-only with respect to oMLX: no POST, PUT, PATCH, or DELETE.

## What not to change without discussion

The polling model, the credential handling, and the layout algorithm are intentionally small. Proposals that add configuration files, background daemons, or launch agents should be opened as an issue first.
