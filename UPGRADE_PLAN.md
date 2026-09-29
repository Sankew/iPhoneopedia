# iPhoneopedia upgrade plan

End-to-end plan to rebuild iPhoneopedia on Xcode 27 with a self-updating iPhone catalog.
Work top to bottom; each phase leaves the app building.

## Baseline (verified September 2026)

| Item | Value |
|---|---|
| Xcode | 27, Swift 6.4, iOS 27 SDK, needs macOS Tahoe 26.6+ |
| Deployment targets Xcode 27 accepts | iOS 15.0 – 27.0 |
| **Chosen minimum: iOS 26.0** | iOS 27 runs on exactly the same iPhones as iOS 26 (iPhone 11 / SE 2 and later), so 26.0 costs no hardware and keeps users who haven't updated yet. Everything below needs at most iOS 26. |
| Deprecated in Xcode 27 | `PreviewProvider` → use `#Preview` |
| iPhone models to cover | 55 (original iPhone → iPhone 17e, iPhone 18 Pro / Pro Max, iPhone Duo) |

## Target architecture

```
AppleDB (MIT, git)           ─┐
  names, identifiers, chip,   │
  release dates, colors       │
Apple "Identify your iPhone   ├─► scripts/build-catalog.mjs ─► iPhoneopedia/catalog.json ─┐
  model" page (image URLs)    │   (GitHub Action: daily +     (committed to main)        │
data/overrides.json          ─┘    manual + on data change)                              │
  taglines, prices, specs,                                                               │
  about text, image fixes                                                                ▼
                                             App: bundled catalog.json (instant, offline)
                                                  + fetch raw.githubusercontent.com URL
                                                  (URLCache + ETag, 5-minute CDN cache)
```

- **New iPhone launch → in the app within a day, no App Store release.** AppleDB added iPhone 18 Pro/Pro Max/Duo before they shipped. The daily job picks them up; run the workflow manually for "now".
- **One file, two jobs.** `iPhoneopedia/catalog.json` is both the file the app bundles (Xcode buildable folder picks it up automatically) and the file the app downloads.
- **The app depends only on your GitHub repo at runtime.** AppleDB/Apple/Wikipedia are touched only by the build job; if any of them breaks, the job fails and the last good catalog stays live.

## Phase 0: Import your original source (Mac, S)

1. Copy your local original project over this checkout on branch `claude/iphoneopedia-upgrade-cbzlle`.
2. Commit it unchanged: `Import original 2022–2023 source`. This gives a reviewable diff for every later change.
3. Add `.gitignore` (`xcuserdata/`, `DerivedData/`, `.DS_Store`, `*.xcuserstate`) and `git rm -r --cached` the committed `xcuserdata`.

## Phase 1: Fresh Xcode 27 project shell (Mac, S)

**Shortcut: don't migrate the 2022 `.pbxproj`.** A new project already has every modern default. Upgrading the old one setting by setting takes longer and leaves cruft behind.

1. Xcode 27 → New Project → iOS App, SwiftUI, testing = Swift Testing, storage = None.
   - Product name `iPhoneopedia`, organization identifier e.g. `com.sankew` (the current bundle ID `com..iPhoneopedia` is invalid).
2. Replace the old `iPhoneopedia.xcodeproj` with the new one. Keep the `iPhoneopedia/` source folder so `git mv` history survives.
3. Check these build settings (set them if the template didn't):
   - `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
   - Swift Language Version = 6
   - Default Actor Isolation = MainActor, Approachable Concurrency = Yes. This removes most `@MainActor` / `Sendable` noise in a UI app.
   - Buildable (synchronized) folders. New files join the target without touching `.pbxproj`, so there are no merge conflicts.
4. Delete the UI-test target (template only). Add one back when there's a flow worth guarding.
5. Drag your old Swift files in, build, fix errors. Mechanical replacements:

| Old | New |
|---|---|
| `NavigationView` | `NavigationSplitView` (sidebar on iPad, stack on iPhone; the target already includes iPad) |
| `ObservableObject` + `@Published` + `@StateObject` / `@ObservedObject` | `@Observable` + `@State` / plain `let` |
| `PreviewProvider` structs | `#Preview { … }` |
| `.navigationBarTitle` | `.navigationTitle` |
| `.foregroundColor` | `.foregroundStyle` |
| `.onChange(of:perform:)` | `.onChange(of:) { old, new in }` |

Liquid Glass comes for free: nav bars, toolbars, search and sheets adopt it automatically when built with the iOS 26+ SDK. Don't hand-roll glass except as a small accent.

## Phase 2: Catalog pipeline (cloud or Mac, M)

Doesn't depend on your Swift source, so this can be built first and in parallel.

### `data/overrides.json`: the only hand-maintained file
Keyed by model name. Only the fields AppleDB lacks, or that you want to override:
```json
{
  "iPhone 4": {
    "tagline": "This changes everything. Again.",
    "launchPrice": "$199 (16 GB), $299 (32 GB)",
    "specs": [{ "title": "Display", "rows": [["Size", "3.5-inch"], ["Resolution", "960×640, 326 ppi"]] }],
    "about": "…",
    "imageURL": "https://… (only when the scraped image is wrong or missing)"
  }
}
```
**One-time seed:** have Claude Code on your Mac extract the taglines, prices, specs and about text hardcoded in your old source into this file. That text is the manual work you already did; it moves out of Swift once and is never re-typed.

### `scripts/build-catalog.mjs` (Node 22, no dependencies)
1. **Models.** Sparse-clone `littlebyteorg/appledb` (`deviceFiles/iPhone`, `deviceGroupFiles/iPhone`). Group identifiers into marketing models via group/subgroup files; ungrouped devices are their own model.
   - Strip only region suffixes like `(GSM)`, `(Global)`, `(US)`, `(China)`. Keep generation suffixes, otherwise the three iPhone SE generations collapse into one entry.
   - Merge colors across identifiers (AppleDB gives name + hex).
   - Use subgroups, so 6 and 6 Plus become separate entries (your old app combined them). Their specs differ, so separate entries are better.
   - Overrides may set `name`. AppleDB calls the original "iPhone 2G"; Apple's name is "iPhone".
2. **Images.** Fetch `https://support.apple.com/en-us/108044` ("Identify your iPhone model"). It has one official Apple image per model, in the same colour-lineup style as your old thumbnails. Map each model heading to its image `src`, and store Apple's URL directly (hotlink, nothing re-hosted).
   - A just-announced model appears there only after release. Until then use `imageURL` from overrides (Newsroom image).
   - If a model's image can't be scraped, keep its URL from the previous `catalog.json`.
3. **About text.** For models without `about` in overrides, use `https://en.wikipedia.org/api/rest_v1/page/summary/<title>`. Store `extract` and the article URL as `aboutSource`; the app must show "Source: Wikipedia (CC BY-SA 4.0)".
4. **Merge.** overrides > scraped > AppleDB. Write `iPhoneopedia/catalog.json` sorted by release date.
5. **Validate before writing.** Fail the run, publishing nothing, if any of these fails:
   - unique `id`s
   - every model has ≥1 identifier and an `https` `imageURL` that returns 200
   - every spec row has exactly 2 strings
   - model count is not lower than the previous catalog (catches scraper breakage)

Note: apple.com and wikipedia.org are blocked from the Claude cloud container. The scraper has to be run and debugged on your Mac or in Actions; GitHub-hosted runners can reach both.

### `catalog.json` shape (`schemaVersion: 1`)
```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-09-29T00:00:00Z",
  "models": [{
    "id": "iphone-4",
    "name": "iPhone 4",
    "identifiers": ["iPhone3,1", "iPhone3,2", "iPhone3,3"],
    "released": "2010-06-24",
    "discontinued": "2012-09-12",
    "chip": "A4",
    "tagline": "This changes everything. Again.",
    "launchPrice": "$199 (16 GB)",
    "imageURL": "https://…",
    "colors": [{ "name": "Black", "hex": "000000" }, { "name": "White", "hex": "EBEBEB" }],
    "specs": [{ "title": "Display", "rows": [["Size", "3.5-inch"]] }],
    "about": "…",
    "aboutSource": "https://en.wikipedia.org/wiki/IPhone_4"
  }]
}
```
- **`specs` is generic sections of label/value rows, on purpose.** A new spec category (e.g. "Satellite", "Hinge") shows up in every installed app version with no app update.
- Additive fields are safe: `Codable` ignores unknown keys. Bump `schemaVersion` only for breaking changes; the app ignores catalogs newer than it understands.

### `.github/workflows/update-catalog.yml`
- Triggers: `schedule` (daily), `workflow_dispatch` (instant), `push` on `data/**` or `scripts/**`.
- `ubuntu-latest`, `permissions: contents: write`: run the script, and if `catalog.json` changed, commit `catalog: update` to `main`.

## Phase 3: App data layer (Mac, S)

Two small files. No networking library, no persistence code.

**`Catalog.swift`**
- `Catalog`, `PhoneModel` (`Identifiable`, `Hashable`), `SpecSection`, `PhoneColor`, all `Codable`.
- Decoder uses `dateDecodingStrategy` for `yyyy-MM-dd`.
- `PhoneColor.color` builds a `Color` from hex.

**`CatalogStore.swift`** (`@Observable`, about 30 lines)
- `init`: decode the bundled `catalog.json`, so the list shows instantly and offline.
- `refresh()`: `URLSession.shared.data(from: rawURL)`, decode, keep only if `schemaVersion <= 1`, assign. Call it from `.task` on launch and from `.refreshable`.
- Caching: set `URLCache.shared` to about 50 MB memory / 200 MB disk in `App.init`. That one line also caches every product image.
- ETag revalidation (`If-None-Match`) and offline fallback come from URLCache for free. Skip writing the catalog to disk by hand; on a failed refresh, keep the current data.
- Raw URL: `https://raw.githubusercontent.com/Sankew/iPhoneopedia/main/iPhoneopedia/catalog.json`. The repo is public (verified); GitHub serves it with a 5-minute cache and an ETag.

**"This is your iPhone" (free because the data has identifiers)**
- Read `utsname().machine`, falling back to `ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]` in the Simulator.
- Match it against `identifiers` to badge and pin the user's own model. About 10 lines.

## Phase 4: UI rebuild (Mac, M)

**List (`ContentView`)**
- `NavigationSplitView` + `List` with sections by year, newest first.
- Row: `AsyncImage` thumbnail, name, year, chip.
- A "Your iPhone" section pinned on top.
- `.searchable` over name, identifier and chip, with `ContentUnavailableView.search` for no results.
- `.refreshable { await store.refresh() }`.

**Detail (`PhoneDetailView`)**
- Hero `AsyncImage`.
- Header: name, tagline, identifiers, release/discontinued dates, launch price.
- Colour swatches from hex.
- Spec sections rendered generically from `specs`.
- About text plus a source link.

**Swipe between models** (README feature): wrap the detail in `ScrollView(.horizontal)` with `.scrollTargetBehavior(.paging)` and `.scrollPosition(id:)`.

**Zoom:**
- `.matchedTransitionSource(id:in:)` on the row thumbnail and `.navigationTransition(.zoom(sourceID:in:))` on the detail give the native zoom-from-thumbnail animation (2 modifiers).
- Pinch-zoom on the hero image only if your original had it (`MagnifyGesture`).

**Rules**
- System fonts and colours only: Dynamic Type and dark mode then work with zero code.
- `.accessibilityLabel(model.name)` on every image.

## Phase 5: Tests and checks (Mac, S)

- **One Swift Testing file, `CatalogTests.swift`:**
  - the bundled `catalog.json` decodes
  - ids are unique
  - every model has an identifier and an https image
  - `"iPhone3,2"` resolves to "iPhone 4"

  This checks the committed catalog against the real Swift types.
- **Pipeline checks** live in the script (Phase 2, step 5).
- **Skipped for now: CI that builds the app on macOS.** Add it when someone else contributes. Until then Xcode on your Mac is the build check.

## Phase 6: Polish (Mac, S)

- **App icon.** Icon Composer (Xcode 27 ships 2.0) for a layered Liquid Glass `.icon`; replaces the 17-slot `AppIcon.appiconset`.
- **README rewrite.** The current one lists features the repo never contained. Describe the new data flow, then add fresh light/dark screenshots.
- **Delete what the pipeline replaced:**
  - every product image in `Assets.xcassets` (keep AccentColor)
  - all hardcoded model arrays
  - the template test stubs

## Shortcuts summary

| Shortcut | Replaces |
|---|---|
| AppleDB for identifiers, chips, dates, colours | Hand-typing 55 models × ~8 fields, and doing it again every September |
| Scrape Apple's Identify-your-iPhone page for image URLs | Downloading and adding ~55 images to the asset catalog by hand |
| Hotlink Apple image URLs + `URLCache` | Hosting images, an image-cache library (Kingfisher/Nuke) |
| Wikipedia summary API for about text | Writing about text for every new model |
| Same `catalog.json` bundled and remote | A second data file, a sync step |
| URLCache ETag revalidation | Custom cache/persistence code |
| Generic `specs` sections | An app update for every new spec type |
| Fresh Xcode 27 project | Migrating ~20 build settings in a 2022 project |
| Buildable folders | `.pbxproj` merge conflicts |
| Default MainActor isolation | Swift 6 concurrency annotation churn |
| System components + iOS 26 SDK | Hand-built Liquid Glass |
| Seed `overrides.json` from old source with Claude Code | Re-typing your existing taglines, prices, about text |

## Tooling on your Mac

1. Pull this branch. `.claude/settings.json` enables the ECC and ponytail plugins automatically; Claude Code asks you to trust the two marketplaces once.
2. Let Claude Code build, test and render previews through Xcode 27:
   ```
   claude mcp add --transport stdio xcode -- xcrun mcpbridge
   ```
3. Useful pieces for this project:
   - skills: `ecc:swiftui-patterns`, `ecc:swift-concurrency-6-2`, `ecc:liquid-glass-design`, `ecc:ios-icon-gen`
   - agents: `ecc:swift-reviewer` (after each phase), `ecc:swift-build-resolver` (when Xcode errors)
   - `/ponytail-review` before each commit
4. **ECC cost.** It adds about 43.6k tokens to every session, and its GateGuard hook asks for a fact statement before the first shell command. If that gets in the way, set `hook_profile` to `minimal` via `/plugin configure ecc@ecc`, or run with `ECC_GATEGUARD=off`.

## Deliberately skipped (add when wanted)

| Feature | Size | Add when |
|---|---|---|
| Compare two models side by side | S | Once specs are filled in for most models |
| Launch-price / chip timeline chart (Swift Charts) | S | Nice demo of the data, no new data needed |
| Home-screen widget "Latest iPhone" | M | If you want a widget in the portfolio |
| Spotlight / App Intents ("Show iPhone 4 in iPhoneopedia") | M | After the UI is stable |
| Localization | S | Xcode 27 agents can translate a String Catalog in one pass |
| Mirroring images into the repo | S | Only if Apple's image URLs start breaking (the daily link check will tell you) |
| Foundation Models Q&A about a model | M | Novelty; the catalog already answers the factual questions |

## Risks

- **Apple page changes.** The scraper fails loudly, nothing publishes, the last good catalog stays live. Fix the selector or use `imageURL` overrides.
- **AppleDB stalls** (volunteer project, but last commit Sept 28 2026). Add a model by hand in `overrides.json`; the app never talks to AppleDB directly.
- **App Store.** Apple's trademark rules restrict "iPhone" inside an app's name. If you ever submit, expect the name to be challenged ("…for iPhone" phrasing is the usual fix). Irrelevant for a portfolio or sideloaded build.
- **raw.githubusercontent.com** has per-IP rate limits. That's fine for a personal app; move to GitHub Pages if it ever has real traffic.
- **Wikipedia text** is CC BY-SA: keep the source link visible in the detail view.
