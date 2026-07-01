# Binger

A macOS menu bar app that automatically fetches the daily [Bing wallpaper](https://www.bing.com/HPImageArchive.aspx) and sets it as your desktop background.

## Features

- Automatically applies today's Bing wallpaper at launch and checks for new wallpapers once per hour.
- Browse up to 30 days of recent wallpapers and apply any of them with one click.
- Lives entirely in the menu bar — no Dock icon.
- Optional launch-at-login support.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later (to build from source)

## Building

Open `binger.xcodeproj` in Xcode and run the `binger` scheme, or build from the command line:

```bash
xcodebuild -project binger.xcodeproj -scheme binger -configuration Release build
```

## Architecture

Binger follows a layered architecture: a thin networking/persistence layer feeds an observable coordinator that drives two SwiftUI surfaces (a menu bar extra and a main window).

```
bingerApp  ──▶  MenuBarExtra  ──▶  MenuBarContent
           └──▶  Window          ──▶  ContentView
                     │
                     ▼
            WallpaperCoordinator   (@Observable, owns app state)
            ├── BingWallpaperService   (network)
            ├── WallpaperManager       (download + NSWorkspace)
            ├── HistoryCache           (JSON persistence)
            └── LoginItemManager       (SMAppService)
```

### Source files

| File | Responsibility |
|---|---|
| `bingerApp.swift` | `@main` entry point. Creates `WallpaperCoordinator` and `LoginItemManager` as SwiftUI `@State` objects and wires them into the `MenuBarExtra` and `Window` scenes. |
| `AppDelegate.swift` | Sets the app's activation policy to `.accessory` (no Dock icon) and prevents termination when the last window closes. |
| `WallpaperCoordinator.swift` | Central `@Observable` state object. Owns the wallpaper history list, the selected-index cursor, loading/applying status, error messages, and the background-check timer loop. |
| `BingWallpaperService.swift` | Fetches metadata from `bing.com/HPImageArchive.aspx`. Paginates in batches of 8, deduplicates by `startDate`, and upgrades image paths from `_1920x1080` to `_UHD`. Depends on the `DataFetching` protocol so it can be unit-tested with a mock. |
| `WallpaperManager.swift` | Downloads a `BingImage` to `~/Library/Application Support/Binger/bing-YYYYMMDD.jpg` and applies it to every connected screen via `NSWorkspace.setDesktopImageURL(_:for:options:)`. |
| `WallpaperLogic.swift` | Pure, side-effect-free functions: merging history arrays (dedup + sort + cap), clamping a selection index after history shrinks, and calculating the next scheduled check time (top of the next hour + a random minute offset). |
| `HistoryCache.swift` | Reads and writes a JSON array of `BingImage` values to `~/Library/Application Support/Binger/history.json`. The storage directory is injectable so tests can use a temp location. |
| `LoginItemManager.swift` | `@Observable` wrapper around `SMAppService.mainApp` that registers or unregisters the app as a login item. |
| `MenuBarContent.swift` | SwiftUI view rendered inside the `MenuBarExtra` popover. Shows the last-applied date, next scheduled check time, and quick-action buttons. |
| `ContentView.swift` | Main window UI. Displays a live image preview, date navigation controls (older/newer/picker/today), title and copyright metadata, a refresh button, a "Set as Wallpaper" button, and the launch-at-login toggle. Loads preview images asynchronously via `URLSession`. |

### Data flow

1. **Start-up** — `WallpaperCoordinator.init()` restores `lastAppliedDate` from `UserDefaults`, loads cached history from `HistoryCache`, then calls `startBackgroundChecks()`.
2. **Background loop** — `checkForNewAndApply()` runs immediately and then after every top-of-hour + random-minute delay. It fetches today's image; if the date is new it is inserted at index 0 and the wallpaper is applied.
3. **Manual refresh** — Calling `refresh()` fetches up to 30 recent images, merges them into the history (via `WallpaperLogic.mergeHistory`), persists up to 90 to the cache, and trims the displayed list back to 30.
4. **Applying a wallpaper** — `WallpaperManager.apply(_:)` downloads the UHD JPEG to Application Support and calls `NSWorkspace` on the main actor to update every screen.
5. **History navigation** — `selectedIndex` is an integer cursor into the `history` array. `WallpaperLogic.clampedSelection` keeps it valid whenever the array changes size.

### Persistence

| Path | Contents |
|---|---|
| `~/Library/Application Support/Binger/history.json` | JSON-encoded `[BingImage]`, capped at 90 entries, newest first |
| `~/Library/Application Support/Binger/bing-YYYYMMDD.jpg` | Downloaded wallpaper files (one per day) |
| `UserDefaults` key `binger.lastAppliedStartDate` | The `startDate` string of the most recently applied wallpaper |

## Testing

The project uses Swift Testing (`import Testing`). Run the tests from Xcode (⌘U) or on the command line:

```bash
xcodebuild test -project binger.xcodeproj -scheme binger -destination 'platform=macOS'
```

Test coverage includes:

- **`BingImageTests`** — `displayDate` formatting, `Identifiable` identity, `Codable` round-trip.
- **`BingServiceStaticTests`** — UHD URL rewriting, archive URL construction, JSON parsing.
- **`BingServiceFetchTests`** — Async fetch behaviour using `MockFetcher` (pagination, deduplication, error propagation, count clamping).
- **`WallpaperLogicTests`** — History merge semantics, selection clamping, scheduled-date calculation.
- **`HistoryCacheTests`** — Save/load round-trip, missing file, corrupt data, nil directory.
- **`WallpaperManagerTests`** — Destination path construction and folder creation.
- **`ErrorMessageTests`** — Localised error descriptions are non-nil.
