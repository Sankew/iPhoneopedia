# Handoff: build, test and finish iPhoneopedia 2.0 in Xcode 27

For the agent or person with a Mac and Xcode 27.
Everything that could be written and verified without Xcode is done, on branch `claude/iphoneopedia-upgrade-cbzlle` ([PR #1](https://github.com/Sankew/iPhoneopedia/pull/1)).
This file says what's verified, what isn't, and exactly what to do next.
Design background is in `UPGRADE_PLAN.md`.

## What's verified, and how

| Area | Status | Evidence |
|---|---|---|
| Catalog pipeline (`scripts/`, `data/`) | **Verified live** | `node --test` (5 tests). Live GitHub Actions run on PR #1: "55 models, 54 with images, Apple page matched 54". The one without an image is iPhone Duo, which isn't on Apple's page until it ships on Oct 23. |
| `Shared/Catalog.swift` + `CatalogTests` | **Compiled and tested** | Real Swift 6.2.3 compiler on Linux with the project's settings: Swift 6, default MainActor isolation, approachable concurrency. 8 tests pass in UTC−7 and UTC+14. |
| Isolation pattern for SDK protocols | **Compiled** | Probe: `nonisolated struct` conformers, `@MainActor func perform()`, `@concurrent` tool call, catch-and-retry on context overflow. |
| SwiftUI / App Intents / WidgetKit / Foundation Models / SwiftData code | **Syntax-checked only** | `swiftc -parse` is clean. Every API name and signature was checked against Apple's documentation data. It has **not been type-checked**: the first Xcode build is the real test. |
| `project.pbxproj` + shared scheme | **Structurally checked** | Parsed by a pbxproj library; every object reference resolves. It has **never been opened in Xcode**. |
| Reviews | Done, findings fixed | ECC `swift-reviewer`, ECC `typescript-reviewer`, `/ponytail-review`. |

## Steps

1. **Open the project.**
   - `git checkout claude/iphoneopedia-upgrade-cbzlle`, then open `iPhoneopedia.xcodeproj` in Xcode 27.
   - If Xcode won't open the project, create it instead: New Project → iOS App "iPhoneopedia" (SwiftUI, Swift Testing, SwiftData). Add a Widget Extension "iPhoneopediaWidget" without Live Activity. Add the folders `Shared/` (member of app **and** widget), `iPhoneopedia/`, `iPhoneopediaWidget/` and `iPhoneopediaTests/` as folders. Apply the build settings below.
2. **Signing.** Set your Team on all three targets. The first build needs no capabilities.
3. **Fill in images and about text.** The bundled catalog was generated offline, so it has none.
   - From the repo root (Node 22+, internet): `node scripts/build-catalog.mjs`
   - Commit `Shared/catalog.json`.
   - After PR #1 merges, the daily Action keeps it current by itself.
4. **Build and run** the `iPhoneopedia` scheme on an iPhone 17 Pro simulator (iOS 27). Fix compile errors; likely spots are listed below.
5. **Run the tests (⌘U).** `CatalogTests` must pass.
6. **Work through the manual checklist below.**
7. **Merge PR #1.**
   - The push to `main` runs the Action, which publishes `Shared/catalog.json` there.
   - Check that `https://raw.githubusercontent.com/Sankew/iPhoneopedia/main/Shared/catalog.json` returns it. Until then, the app's refresh gets a 404 and keeps the bundled catalog, which is intended.

Build settings, all targets: iOS 27.0, `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- Bundle IDs: `com.sankew.iPhoneopedia`, `com.sankew.iPhoneopedia.Widget`, `com.sankew.iPhoneopediaTests`.
- The widget uses `INFOPLIST_FILE = iPhoneopediaWidget/Info.plist`, excluded from the widget's synchronized folder.

## Likely compile-error spots (not type-checked)

- `PhoneEntity.swift`, `AppIntents.swift`, `PhoneWidget.swift`:
  - SDK conformers are `nonisolated struct`. If Xcode asks for more, mark individual members `nonisolated`. Don't drop the default MainActor setting.
  - `PhoneModelEntity` and `PhoneModelQuery` compile into both app and widget. If App Intents metadata complains about duplicates, move them to an `AppIntentsPackage`.
- `MyPhonesView.swift`: `@Model final class OwnedPhone` under default MainActor isolation. If SwiftData complains about isolated conformance, try `nonisolated` on the class.
- `Assistant.swift`:
  - `@Generable nonisolated struct` for the nested `Arguments` and `Guess`.
  - `@concurrent func call`.
  - `Attachment(image)` inside the `@PromptBuilder` closure; the `UIImage` overload is iOS 27.0.
- `AppIntents.swift`: `CIImage(cvPixelBuffer:)` with Visual Intelligence's `CVReadOnlyPixelBuffer`. This is what Apple's sample does.
- `PhoneDetail.swift`:
  - `ToolbarItem(placement: .topBarPinnedTrailing)` (iOS 27)
  - `Circle().fill(…).stroke(.separator)`
  - `LabeledContent(_:value:format:)` with `.currency(code:)`
- `iPhoneopediaApp.swift`: an `if` inside the `TabView { Tab … }` builder. `.tabBarMinimizeBehavior(.onScrollDown)`.

## Manual checklist

- **List**
  - Year sections, newest first.
  - "Your iPhone" appears in the simulator (`SIMULATOR_MODEL_IDENTIFIER`).
  - Pull to refresh.
- **Detail**
  - Opens on the tapped model (verified in the iOS 27 simulator).
  - Swipe changes pages and the title.
  - Zoom transition from the row.
  - "I owned this" toggles, and stays visible when you un-own inside My iPhones.
  - Share.
- **Trends:** three charts render. The price footnote explains contract prices.
- **My iPhones:** owned phones listed; swipe to delete.
- **Search:** "mini", "A17 Pro", "iPhone15,2" and "2016" return results; "iPhone 16" lists the iPhone 16 first.
- **Ask** (on an Apple Intelligence device or simulator):
  - Answers use catalog facts.
  - Ten or more follow-up questions still work, because of the context-overflow retry.
  - Photo identify works on a portrait photo.
- **Widget:** add it; the default shows this iPhone; configuring a model works.
- **Siri, Shortcuts, Spotlight:**
  - "Show iPhone Air in iPhoneopedia" opens the detail.
  - Spotlight "iPhone 4" shows the entity.
- **Visual Intelligence** (device only): point at an iPhone; results come from iPhoneopedia. The query only runs when a label contains "phone". If it never fires, log `input.labels`.
- **Accessibility and layout:** dark mode, largest Dynamic Type, VoiceOver on list and detail, iPad sidebar.

## Deliberately not done

| Item | Why / how |
|---|---|
| Private Cloud Compute for Ask | Code is done: Ask and photo identify use `PrivateCloudComputeLanguageModel` (the server model behind Siri) when available and fall back to on-device. It needs Apple's managed entitlement `com.apple.developer.ml.compute.private-cloud-compute`: request it at developer.apple.com/private-cloud-compute, then add it to an `iPhoneopedia.entitlements` file. PCC doesn't run in the simulator (release note 177684296); test on a device. |
| iPhone Duo layouts (`ArrangementView`, `reservedRegions`) | These APIs are iOS 27.1 **beta** and won't compile on Xcode 27.0. Test the Duo simulator in Xcode 27.1 first; `sidebarAdaptable` may already be enough. |
| iCloud sync for My iPhones | Needs a paid developer account. Add the iCloud capability (CloudKit) and Background Modes → Remote notifications. `OwnedPhone` is already CloudKit-compatible. |
| App icon | The `AppIcon` slot is empty, which gives a build warning. Make a layered icon in Icon Composer 2.0. |
| Taglines and your own about text | Copy them from the 2022 source into `data/overrides.json` (keys `tagline`, `about`). |
| Price and screen-size spot-check | The `launchPriceUSD` and `displayInches` values in `data/overrides.json` were drafted from Apple launch announcements. |
| Widget tap → model, photo in widget | Skipped. Needs a URL scheme or an App Intent button, plus image downscaling. |
| AppIntentsTesting / Evaluations tests | Their APIs are new in iOS 27; write them with the compiler at hand. |
| App schemas (`@AppEntity(schema:)`) | No schema domain fits an encyclopedia (the domains are mail, photos, audio and so on). `IndexedEntity` and Visual Intelligence cover Siri and Spotlight. |

## Tooling

- **Plugins.** `.claude/settings.json` enables ECC and ponytail; accept the marketplace trust prompt once.
- **Xcode MCP.** Lets Claude Code build, test and snapshot previews: `claude mcp add --transport stdio xcode -- xcrun mcpbridge`.
- **ECC GateGuard** asks for a fact statement before each new file and destructive command. Set `ECC_GATEGUARD=off` if that slows the build-fix loop.
