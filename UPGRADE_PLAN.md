# iPhoneopedia 2.0: full overhaul plan

> **Status:** implemented on `claude/iphoneopedia-upgrade-cbzlle`. See `HANDOFF.md` for what's verified and the Xcode 27 steps.
> **Deviations from this plan:**
> - iPhone Duo code was deferred because its APIs are iOS 27.1 beta.
> - CloudKit entitlements were left out so the first build needs no signing team.
> - Catalog ids come from the hardware identifier, not the name.
> - The catalog lives in `Shared/`, not `iPhoneopedia/`.

A ground-up rewrite on Xcode 27 / iOS 27. It has a self-updating iPhone catalog and uses every new Apple framework that fits an iPhone encyclopedia.
Personal project, so there are no App Store constraints.
Work top to bottom. Every phase ends with an app that builds and runs.

## Baseline (verified September 2026)

| Item | Value |
|---|---|
| Xcode | 27 (Swift 6.4, iOS 27 SDK, macOS Tahoe 26.6+). **Xcode 27.1** is needed for iPhone Duo APIs |
| **Minimum iOS: 27.0** | iOS 27 runs on exactly the same iPhones as iOS 26 (iPhone 11 / SE 2 and later), so nothing is lost. Every iOS 27 API below works without `#available` branches. Only the iPhone Duo APIs need `if #available(iOS 27.1, *)`. |
| Deprecated in Xcode 27 | `PreviewProvider` → `#Preview` |
| Catalog | 55 models: original iPhone → iPhone 17e, iPhone 18 Pro / Pro Max, iPhone Duo |
| Apple Intelligence features | Only on Apple Intelligence iPhones (15 Pro and later). Hidden elsewhere via `SystemLanguageModel.default.availability` |

## Framework → feature map

Every framework here earns its place with a user-visible feature.

| Framework (new in) | Feature | Phase |
|---|---|---|
| SwiftUI (27): Liquid Glass, `Tab(role: .search)`, `toolbarMinimizeBehavior`, `topBarPinnedTrailing`, `@State` macro, zoom transitions | Whole UI | 4 |
| SwiftUI `AsyncImage` (27: standard HTTP caching by default) | Apple product photos with zero cache code | 4 |
| Swift Charts | Timeline: launch price, screen size, release cadence across 19 years | 4 |
| SwiftData + CloudKit | "My iPhones": the models you've owned, with years, synced across devices | 3–4 |
| App Intents (27: entity schemas, intent schemas, View Annotations) + `IndexedEntity` | Siri and Spotlight know every iPhone ("When did the iPhone 4 come out?", "Open iPhone Air"), and on-screen "compare this with…" | 5 |
| Visual Intelligence (`IntentValueQuery` + `SemanticContentDescriptor`) | Point the camera at a phone, and iPhoneopedia offers matching models in the system Visual Intelligence UI | 5 |
| WidgetKit (27: App Intent–configurable) | "Latest iPhone" and "Your iPhone is N years old" widgets | 5 |
| Foundation Models (27: new on-device model, `Attachment` image input, `Tool`, `@Generable`, `DynamicProfile`) | "Ask iPhoneopedia" answers from catalog data, and "Identify from photo" | 6 |
| Evaluations framework (27) | Regression checks for Ask/Identify answers | 8 |
| SwiftUI / UIKit iPhone Duo APIs (27.1): `ArrangementView`, `GeometryProxy.reservedRegions(kind:)`, `onHingeChange` | List + detail side by side on the unfolded Duo, nothing under the fold | 7 |
| Swift Testing + AppIntentsTesting (27) | Catalog and Siri/Spotlight integration tests without UI automation | 8 |
| Icon Composer 2.0 | Layered Liquid Glass app icon | 9 |

**Considered and skipped:**

| Framework | Why it's out |
|---|---|
| Core AI | For bringing your own models; Foundation Models' built-in model covers every AI feature here |
| Cloud models (Claude/Gemini via `LanguageModel`) | Needs API keys and network; the on-device model is free, private and offline |
| Image Playground | Generated phone images would undermine an encyclopedia |
| Document APIs, reorderable containers, NowPlaying, Music Understanding, Live Activities | Nothing in the app they'd serve |
| TipKit, Translation | One tip isn't worth a framework. Translation: add if you ever localize the about text |
| RealityKit / AR Quick Look "true size" | Apple only hosts 3D models for current phones. Revisit if a source covers most of the catalog |

## Architecture

```
AppleDB (MIT, git)           ─┐
  names, identifiers, chip,   │
  release dates, colors       │
Apple "Identify your iPhone   ├─► scripts/build-catalog.mjs ─► iPhoneopedia/catalog.json ─┐
  model" page (image URLs)    │   (GitHub Action: daily +     (committed to main)        │
Wikipedia summary API        ─┤    manual + on data change)                              │
data/overrides.json          ─┘                                                          ▼
  taglines, prices, specs,              App + widget: bundled catalog.json (instant, offline)
  numeric fields for charts                  + fetch raw.githubusercontent.com URL
                                             (URLCache + ETag, 5-minute CDN cache)
```

- **A new iPhone reaches the app within a day of AppleDB adding it, with no App Store release.** AppleDB added iPhone 18 Pro/Pro Max/Duo before they shipped. Run the workflow by hand for "now".
- **One file, three consumers.** `iPhoneopedia/catalog.json` is bundled into the app and the widget (buildable-folder target membership) and fetched remotely by both.
- **At runtime the app depends only on your GitHub repo.** AppleDB, Apple and Wikipedia are touched only by the build job; if one breaks, the job fails and the last good catalog stays live.

## Code layout (target: ~12 files)

```
iPhoneopedia/
  iPhoneopediaApp.swift     App, TabView, model container
  Catalog.swift             Codable types, CatalogStore, current-device lookup
  OwnedPhone.swift          SwiftData @Model
  PhoneList.swift           list + search
  PhoneDetail.swift         detail, paging, specs, colors
  TimelineView.swift        Swift Charts
  MyPhonesView.swift        owned phones timeline
  AskView.swift             Foundation Models chat + photo identify
  Intents.swift             AppEntity, queries, intents, Visual Intelligence query
  catalog.json
iPhoneopediaWidget/
  Widgets.swift
iPhoneopediaTests/
  CatalogTests.swift, IntentsTests.swift
```

## Phase 0: Harvest the old app's content (Mac, S)

The rewrite replaces all the old code. Only the content you wrote by hand is worth keeping: taglines, prices, specs, about text.

1. **Seed the overrides file.** Point Claude Code on your Mac at the old project folder and have it extract that content into `data/overrides.json` (format in Phase 2).
2. **Optional:** commit the old source first as `Import original 2022–2023 source` if you want it in git history. Nothing depends on it.
3. Add `.gitignore` (`xcuserdata/`, `DerivedData/`, `.DS_Store`, `*.xcuserstate`) and `git rm -r --cached` the committed `xcuserdata`.

## Phase 1: New Xcode 27 project (Mac, S)

1. **Create the project.** New Project → iOS App, SwiftUI, Swift Testing, storage = SwiftData, host in CloudKit.
   - Product `iPhoneopedia`, org identifier e.g. `com.sankew`. The old bundle ID `com..iPhoneopedia` is invalid.
2. **Add a Widget Extension target** (`iPhoneopediaWidget`) without configuration intent; you'll add an App Intent config in Phase 5. Give `catalog.json` membership in both targets.
   - No App Group is needed: the widget reads its own bundled copy and fetches the remote copy itself.
3. **Check the build settings** (set them if the template didn't):
   - iOS Deployment Target 27.0
   - Swift Language Version 6
   - Default Actor Isolation = MainActor, Approachable Concurrency = Yes
   - buildable folders
4. **Capabilities:** iCloud (CloudKit) and Background Modes → Remote notifications, for SwiftData sync. CloudKit needs a paid developer account; on a free account, set the container to `.none` and "My iPhones" stays on the device.
5. **Clean up.** Delete the old `.xcodeproj`, the UI-test target and the template tests.

## Phase 2: Catalog pipeline (cloud or Mac, M)

Independent of the Swift code, so build it first.

### `data/overrides.json`: the only hand-maintained file
Keyed by model name; only what AppleDB lacks or gets wrong:
```json
{
  "iPhone 2G": { "name": "iPhone" },
  "iPhone 4": {
    "tagline": "This changes everything. Again.",
    "launchPriceUSD": 199,
    "displayInches": 3.5,
    "specs": [{ "title": "Display", "rows": [["Size", "3.5-inch"], ["Resolution", "960×640, 326 ppi"]] }],
    "about": "…",
    "imageURL": "https://… (only when the scraped image is wrong or missing)"
  }
}
```
- **`launchPriceUSD` and `displayInches` are typed numbers** because the Timeline charts need them.
- **Once-off gap-fill:** have Claude draft the missing numbers for all 55 models and spot-check them. After that it's one new row per launch.

### `scripts/build-catalog.mjs` (Node 22, no dependencies)
1. **Models.** Sparse-clone `littlebyteorg/appledb` (`deviceFiles/iPhone`, `deviceGroupFiles/iPhone`) and group identifiers into models using subgroups, so 6 and 6 Plus are separate entries; ungrouped devices are their own model.
   - Strip only region suffixes like `(GSM)`, `(Global)`, `(US)`, `(China)`. Keep generation suffixes, or the three iPhone SEs collapse into one.
   - Merge colors (name + hex) across identifiers.
2. **Images.** Fetch `https://support.apple.com/en-us/108044` ("Identify your iPhone model"). Map each model heading to its image `src` and store Apple's URL (hotlinked, nothing re-hosted).
   - New models appear there only after release, so use `imageURL` from overrides (Newsroom image) until then.
   - If an image can't be scraped, keep the previous catalog's URL.
3. **About text.** For models without `about`, use the Wikipedia summary API (`/api/rest_v1/page/summary/<title>`). Store `extract` plus `aboutSource`; the app shows "Source: Wikipedia (CC BY-SA 4.0)".
4. **Merge and write.** overrides > scraped > AppleDB. Write `iPhoneopedia/catalog.json` sorted by release date.
5. **Validate.** On any failure, publish nothing:
   - unique `id`s
   - ≥1 identifier per model
   - an `https` `imageURL` that returns 200
   - spec rows are 2 strings
   - model count not lower than the previous catalog

apple.com and wikipedia.org are blocked from the Claude cloud container. Run and debug the scraper on your Mac or in Actions.

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
    "launchPriceUSD": 199,
    "displayInches": 3.5,
    "imageURL": "https://…",
    "colors": [{ "name": "Black", "hex": "000000" }, { "name": "White", "hex": "EBEBEB" }],
    "specs": [{ "title": "Display", "rows": [["Size", "3.5-inch"]] }],
    "about": "…",
    "aboutSource": "https://en.wikipedia.org/wiki/IPhone_4"
  }]
}
```
- **`specs` is generic label/value sections,** so a new spec category (e.g. "Hinge") appears in every installed version with no app update.
- `Codable` ignores unknown keys, so additive fields are safe. Bump `schemaVersion` only for breaking changes; the app ignores catalogs newer than it understands.

### `.github/workflows/update-catalog.yml`
- Triggers: `schedule` (daily), `workflow_dispatch` (instant), `push` on `data/**` or `scripts/**`.
- On `ubuntu-latest` with `permissions: contents: write`: run the script, and if `catalog.json` changed, commit `catalog: update` to `main`.

## Phase 3: Data layer (Mac, S)

**`Catalog.swift`**
- `Catalog`, `PhoneModel` (`Identifiable`, `Hashable`), `SpecSection`, `PhoneColor`, all `Codable`, with a `yyyy-MM-dd` date strategy.
- `PhoneColor.color` builds a `Color` from hex.

**`CatalogStore`** (`@Observable`, ~30 lines)
- `init`: decode the bundled file, so the list appears instantly and works offline.
- `refresh()`: `URLSession.shared.data(from:)`, decode, accept only if `schemaVersion <= 1`. Call it from `.task` and `.refreshable`.
- URLCache handles ETag revalidation and the offline fallback. No persistence code.
- URL: `https://raw.githubusercontent.com/Sankew/iPhoneopedia/main/iPhoneopedia/catalog.json`. The repo is public; GitHub serves it with a 5-minute cache and an ETag (verified).

**Current device**
- `utsname().machine`, falling back to `ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]`, matched against `identifiers`.

**`OwnedPhone.swift`**
- `@Model final class OwnedPhone { var modelID: String = ""; var from: Int?; var to: Int? }`.
- CloudKit rules: every property needs a default or must be optional, and there are no unique constraints.

## Phase 4: Core UI (Mac, M)

**Shell:** `TabView` with `.tabViewStyle(.sidebarAdaptable)`, which gives a tab bar on iPhone and a sidebar on iPad or the unfolded Duo.

| Tab | Content |
|---|---|
| iPhones | `List` sectioned by year, newest first; "Your iPhone" pinned on top; row = `AsyncImage` thumbnail, name, year, chip; `.refreshable` |
| Timeline | Swift Charts: launch price (`LineMark` + `PointMark`), screen size (`BarMark`), models per year |
| My iPhones | `@Query` owned phones as a personal timeline; add from any detail page |
| Ask | Phase 6; tab hidden when the model is unavailable |
| Search (`Tab(role: .search)`) | Liquid Glass search tab over name, identifier and chip; `ContentUnavailableView.search` when empty |

**Detail**
- Hero `AsyncImage`.
- Header: name, tagline, identifiers, dates, launch price.
- Color swatches.
- Spec sections rendered generically.
- About text plus a source link.
- "I owned this" toggle.
- Share link pinned with `topBarPinnedTrailing`.
- `toolbarMinimizeBehavior` so the nav bar collapses on scroll.

**Motion**
- Swipe between models: `ScrollView(.horizontal)` with `.scrollTargetBehavior(.paging)` and `.scrollPosition(id:)`.
- Zoom from thumbnail: `.matchedTransitionSource(id:in:)` plus `.navigationTransition(.zoom(sourceID:in:))`.

**Rules**
- System fonts and colors only (Dynamic Type and dark mode for free).
- `.accessibilityLabel` on every image.
- No custom glass: iOS 27 applies Liquid Glass to system components.

At the end of this phase, **v2.0 core is done.** Ship it to your phone before starting Phase 5.

## Phase 5: System integration (Mac, M)

**`Intents.swift`**
- `PhoneModelEntity: AppEntity, IndexedEntity`, built from `PhoneModel`: name, year, chip, image as the display representation.
- `EntityQuery` backed by `CatalogStore`.
- Adopt the iOS 27 **entity schema**, so the models land in Spotlight's semantic index and Siri can answer from them with attribution. Take the exact schema macro from Xcode 27's built-in "What's New" skill or the App Intents docs.
- `OpenPhoneIntent` (opens detail) and App Shortcuts phrases ("Show \(model) in iPhoneopedia").
- **View Annotations** on the detail view, so "Siri, when was this released?" and "compare this with the iPhone 17" resolve to the entity on screen.

**Visual Intelligence**
- An `IntentValueQuery` whose `values(for: SemanticContentDescriptor)` does two things: it matches `labels` against model names, and on Apple Intelligence devices it passes the `pixelBuffer` to the Phase 6 identifier to narrow down the result.
- Returns `[PhoneModelEntity]`.

**Widgets**
- "Latest iPhone": newest catalog entry.
- "Your iPhone": current or owned model and its age, configurable through an App Intent (iOS 27 widget customization).
- Timeline refreshes daily; each refresh reads the bundled catalog and fetches the remote one.

## Phase 6: Apple Intelligence (Mac, M)

**Ask iPhoneopedia**
- `LanguageModelSession` with instructions: "Answer only from tool results; say so if the catalog doesn't know."
- `CatalogTool: Tool` with `@Generable struct Arguments { let query: String }`. It returns matching catalog rows as text, so answers ("Which iPhones had a headphone jack?", "Compare 13 mini and 16e") come from your data, not the model's memory.

**Identify from photo**
- `PhotosPicker` → `session.respond { "Which iPhone model is this? …"; Attachment(image) }`.
- Use `@Generable struct Guess { let candidates: [String] }` constrained to catalog names. Show the top three as links.
- Treat it as a best guess: exact model from a photo is hard (camera-bump layout narrows it to an era). Label it that way in the UI.

**Profiles and availability**
- Optional: a `DynamicProfile` per mode (ask vs identify) instead of two sessions, only if they end up sharing a conversation.
- Gate everything on `SystemLanguageModel.default.availability`; unavailable means the tab is hidden, not an error.

## Phase 7: iPhone Duo (Xcode 27.1, S)

1. Run in the iPhone Duo simulator first. `sidebarAdaptable` + `NavigationSplitView` may already look right unfolded.
2. Only if content sits under the fold, behind `if #available(iOS 27.1, *)`, choose one:
   - `ArrangementView { list } secondary: { detail }` with `.arrangementViewStyle(.split…)`
   - or avoid `GeometryProxy.reservedRegions(kind: .division)` in the detail layout.
3. Skip `onHingeChange`: Apple recommends it only for effects driven by hinge movement, not for layout.

## Phase 8: Tests (Mac, S)

**`CatalogTests.swift` (Swift Testing)**
- the bundled catalog decodes
- ids are unique
- every model has an identifier and an https image
- `"iPhone3,2"` resolves to "iPhone 4"
- numeric fields are present for every model the charts use

**`IntentsTests.swift` (AppIntentsTesting)**
- `OpenPhoneIntent` resolves "iPhone Air"
- the entity query returns the Duo
- Visual Intelligence query with label "iPhone" returns results

**Evaluations framework:** 10–20 Ask/Identify cases with expected answers. Run them after prompt changes.

The pipeline validates itself (Phase 2, step 5). **Skipped: a macOS CI build.** Xcode 27 on your Mac is the build check until someone else contributes.

## Phase 9: Polish (Mac, S)

- **Icon.** Icon Composer 2.0 layered icon (the "sharper rendering" mode for the 2027 OSes).
- **README.** Rewrite it: the current one lists features the repo never contained. Cover features, data flow and how to add a model, plus fresh screenshots (light/dark, iPhone + Duo).
- **Delete** every product image and hardcoded model array from the old app.

## Build order and effort

| Order | Phase | Size | Output |
|---|---|---|---|
| 1 | 2 Pipeline | M | `catalog.json` updating itself |
| 2 | 0 + 1 Harvest + project | S | Empty app, overrides seeded |
| 3 | 3 + 4 Data + UI | M | **v2.0 core**: usable daily |
| 4 | 5 System integration | M | Siri, Spotlight, Visual Intelligence, widgets |
| 5 | 6 Apple Intelligence | M | Ask + Identify |
| 6 | 7 + 8 + 9 | S each | Duo, tests, icon, README |

## Shortcuts summary

| Shortcut | Replaces |
|---|---|
| AppleDB for identifiers, chips, dates, colors | Hand-typing 55 models × ~8 fields, every September again |
| Scraped Apple image URLs + iOS 27 `AsyncImage` HTTP caching | Downloading ~55 images; image-cache libraries; URLCache tuning |
| Wikipedia summary API | Writing about text for every new model |
| One `catalog.json` for app, widget and remote | Duplicate data files, App Group plumbing |
| URLCache ETag revalidation | Custom persistence code |
| Generic `specs` sections | App updates for new spec types |
| iOS 27 minimum (same hardware as 26) | `#available` branches around every new API |
| New Xcode 27 project | Migrating a 2022 project's settings |
| Default MainActor isolation + buildable folders | Concurrency annotation churn, `.pbxproj` conflicts |
| `sidebarAdaptable` TabView | Separate iPhone / iPad / Duo layouts |
| `CatalogTool` grounding | A RAG pipeline; hallucinated specs |
| SwiftData template with CloudKit ticked | Sync code |

## Tooling on your Mac

1. **Plugins.** Pull this branch; `.claude/settings.json` enables ECC and ponytail, and you confirm trust for their marketplaces once.
2. **Xcode MCP.** Let Claude Code build, test, run the simulator and snapshot previews:
   ```
   claude mcp add --transport stdio xcode -- xcrun mcpbridge
   ```
3. **Xcode 27's own agent skills.** "SwiftUI Specialist" and "What's New in SwiftUI" give exact iOS 27 signatures; use them when an API name here needs confirming.
4. **ECC and ponytail.**
   - `ecc:swiftui-patterns`, `ecc:swift-concurrency-6-2`, `ecc:liquid-glass-design`, `ecc:foundation-models-on-device`, `ecc:ios-icon-gen`
   - agents `ecc:swift-reviewer` (after each phase) and `ecc:swift-build-resolver`
   - `/ponytail-review` before commits
5. **ECC overhead.** About 43.6k tokens per session, plus GateGuard prompts before the first shell command and before creating each file. Set `hook_profile` to `minimal` via `/plugin configure ecc@ecc`, or use `ECC_GATEGUARD=off`, if it slows you down.

## Risks

- **Apple page structure changes.** The scraper fails loudly and the last good catalog stays live. Fix the selector or use `imageURL` overrides.
- **AppleDB stalls** (volunteer-run; last commit Sept 28 2026). Add models by hand in `overrides.json`; the app never calls AppleDB.
- **Identify-from-photo accuracy** is the least certain feature. Ship it labelled "best guess", keep Evaluations cases, cut it if it's wrong too often.
- **iOS 27 entity schema and Duo APIs are weeks old.** Confirm exact signatures in Xcode 27.1 docs before building Phases 5 and 7.
- **CloudKit and a free Apple account.** Without the paid program there's no CloudKit, and sideloaded builds expire after 7 days.
- **raw.githubusercontent.com** rate limits are fine for personal use; switch to GitHub Pages if that changes.
- **Wikipedia text** is CC BY-SA: keep the source link visible.
