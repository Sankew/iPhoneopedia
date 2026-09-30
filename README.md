# iPhoneopedia

Every iPhone from the 2007 original to the iPhone Duo, in a SwiftUI app for iOS 27.
The catalog updates itself, so a new iPhone shows up in the app without an App Store release.

## Features

- **iPhones:** every model by year, with Apple's product photo, chip, colors, specs and a Wikipedia summary. The iPhone you're holding is pinned on top. Swipe sideways to page through models.
- **Trends:** launch prices, screen sizes and models per year, in Swift Charts.
- **My iPhones:** tick the phones you've owned (SwiftData).
- **Ask:** questions about any iPhone, answered from the catalog by Apple Intelligence. It uses Apple's server model (Private Cloud Compute) when the app is allowed to, and the on-device model otherwise. Pick a photo and it guesses the model.
- **Siri and Shortcuts** ("Show iPhone 4 in iPhoneopedia"), **Spotlight**, **Visual Intelligence**, a **widget** and a **search** tab.

Apple's older product photos are JPEGs on white. The app cuts them out on the phone the first time it loads them: Vision's subject lifting for the edges, and a flood fill of the white backdrop so white iPhones don't disappear with it.

## Where the data comes from

```
AppleDB (identifiers, chips, dates, colors) ─┐
Apple "Identify your iPhone model" (photos)  ├─► scripts/build-catalog.mjs ─► Shared/catalog.json
Wikipedia summaries (about text)             │   GitHub Action, daily        bundled in the app +
data/overrides.json (prices, sizes, fixes)  ─┘                               fetched from GitHub at launch
```

A new iPhone appears once [AppleDB](https://github.com/littlebyteorg/appledb) lists it; AppleDB had the iPhone 18 Pro and Duo before they shipped. Its photo follows when Apple adds it to the [Identify your iPhone model](https://support.apple.com/en-us/108044) page, which happens after release.

The only file I maintain by hand is `data/overrides.json`, keyed by model name:

```json
"iPhone 4": {
  "launchPriceUSD": 199,
  "displayInches": 3.5,
  "tagline": "This changes everything. Again."
}
```

Other keys: `name`, `chip`, `about` and `aboutSource` (replace the Wikipedia text), `wiki` (a different Wikipedia title), `imageURL` (a photo before Apple's page has one), and `specs`. Push the change and the Action validates it and publishes it; installed apps pick it up the next time they launch. **Actions → Update catalog → Run workflow** publishes straight away.

The build fails, and the last good catalog stays live, when a source breaks or the result doesn't validate: duplicate ids, a model that disappeared, a non-https photo, an override that matches no model. The Apple page is scraped with a regex, so an Apple redesign is the most likely way it'll break.

`specs` are plain label/value sections, so a new kind of spec reaches every installed version without an app update. The app ignores catalogs with a newer `schemaVersion` than it understands.

## Building

Xcode 27, iOS 27. Set your team on the three targets (app, widget, tests) and run.

- `node --test` tests the pipeline; ⌘U runs the app's tests.
- `node scripts/build-catalog.mjs` rebuilds the catalog locally. It needs Node 22 and a network connection.
- Ask only shows up on iPhones with Apple Intelligence.

## Still to do

- **Private Cloud Compute.** Apple grants it per app as a managed entitlement (`com.apple.developer.ml.compute.private-cloud-compute`, requested at [developer.apple.com/private-cloud-compute](https://developer.apple.com/private-cloud-compute/)). Until then Ask runs on device. PCC doesn't work in the simulator.
- **iPhone Duo layout.** The Duo APIs (`ArrangementView`, `reservedRegions`) need Xcode 27.1. `sidebarAdaptable` might already look fine unfolded.
- **iCloud sync for My iPhones.** Needs a paid developer account; `OwnedPhone` is already CloudKit-compatible.
- **Taglines and my own about text** from the 2022 app, into `overrides.json`.
- **Prices and screen sizes** are from Apple's launch announcements and haven't all been double-checked.
- **The widget** doesn't open the model it shows yet.

## Choices

Apple Intelligence runs on Apple's own models: on device, or Private Cloud Compute. Third-party models through `LanguageModel` would need API keys and a network connection for no gain here. Image Playground is out because a generated iPhone has no place in an encyclopedia. AR "true size" is out because Apple only hosts 3D models for the current lineup.

## Credits

Device data: [AppleDB](https://github.com/littlebyteorg/appledb) (MIT). About text: Wikipedia (CC BY-SA 4.0), linked in the app. Product photos © Apple, loaded from Apple's site.

## Original version (2022)

![App Screenshot](appview1.png)
![App Screenshot](appview2.png)
