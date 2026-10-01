# ios/ — AntennaPod for iOS

Fork-only SwiftUI shell. Playback via AVFoundation; networking/downloads via URLSession; persistence in-memory for now (SQLite later). Shared KMP parser is validated in `shared/kmp`; the iOS app currently uses a Foundation `XMLParser` fallback with the same golden fixtures in mind. Wiring the XCFramework into the app is the next integration step.

## Status (Phase 1 skeleton)

- Subscribe by feed URL
- Apple Podcasts / iTunes Search discovery (Add sheet; debounced; Subscribe via feed URL)
- Episode list
- Stream playback (AVPlayer, speed, ±30s)
- Full player sheet (artwork, scrubber, transport; tap mini player to open)
- Chapters (PSC / Podcast Index from feed; list in full player; tap to seek)
- Lockscreen / Now Playing (title, podcast, artwork, remote play/pause/skip)
- Headset / Bluetooth pause (AVAudioSession interruption + headphone unplug; remotes unchanged)
- Sleep timer (clock presets + end of episode, fade-out)
- Offline download to Documents/downloads (background URLSession; survives suspend/relaunch)
- Queue tab (JSON)
- Inbox tab (unplayed across subscriptions; pull-to-refresh refreshes all feeds)
- Library search (local subscriptions/episodes; Inbox searchable + Subscriptions filter; not iTunes)
- Playback progress save / resume
- Mark played / unplayed (manual + smart-mark 30s)
- Settings tab (theme light/dark/system, default playback speed, playback source, feed refresh interval, auto-download)
- Prefer stream vs download (Prefer download / Prefer stream / Automatic; honored on play)
- Continuous playback (auto-next from queue when an episode ends)
- Feed refresh / Keep updated (global interval; auto on launch & foreground when due)
- Auto-download (global on/off + episodes-per-feed cap; after refresh; optional Wi‑Fi only)
- OPML import/export (Settings + Subscriptions; share sheet / file picker; batch subscribe)
- Download storage limit (Settings: usage + max size; auto-evict played first)

Root tabs (5): **Inbox**, Subscriptions, Queue, Downloads, Settings.

## Layout

```
ios/
├── README.md
├── project.yml              # XcodeGen
└── AntennaPod/
    ├── AntennaPodApp.swift
    ├── App/RootTabView.swift
    ├── Data/…               # store, repository, playback, download, parsers
    └── Features/…           # inbox, library search, subscriptions, add/discover, player, downloads, queue, settings, OPML
```

## Local setup (Mac)

```bash
brew install xcodegen
./gradlew -p shared/kmp linkDebugFrameworkIosSimulatorArm64   # optional until linked
cd ios && xcodegen generate
open AntennaPod.xcodeproj
```

See `docs/ios/PLAN.md` and `docs/ios/FEATURE-MATRIX.md`.

## Persistence

Subscriptions, queue, and per-episode playback state (`positionSeconds`, `durationSeconds`, `isPlayed`) are stored as JSON under Application Support (`PodcastPersistence`: `feeds.json`, `queue.json`, `playback.json`). Inbox is derived from that state (unplayed episodes across feeds, newest first). Playback resumes from the saved position; episodes are auto-marked played within the last 30 seconds (AntennaPod `smartMarkAsPlayed` default) or when playback ends. Theme, default playback speed, playback source preference, feed refresh interval, and auto-download prefs live in `UserDefaults` (`AppSettings`) and apply via `preferredColorScheme` / fresh episode starts / `PlaybackService.play` source resolution / launch+foreground due-check / post-refresh enqueue. Downloads are files under Documents/downloads with a JSON catalog (`downloads.json`) and in-flight background task↔episode map (`pending-downloads.json`). Background transfers use `URLSessionConfiguration.background(withIdentifier:)` plus `AppDelegate.handleEventsForBackgroundURLSession`. Download storage limit lives in `UserDefaults` (`AppSettings.downloadStorageLimit`); `DownloadService` measures Documents/downloads usage, enforces the budget after each successful download (and on Settings open / app launch) by deleting **played** episodes first (oldest file mtime), then unplayed (LRU). Settings also offers **Clear downloads** with confirmation. GRDB/SQLite aligned with AntennaPod schema comes later.


## Library search

Local-only search over subscribed feeds and their episodes (title, feed title, feed description) — distinct from Apple Podcasts / iTunes discovery in Add podcast. **Inbox** uses `.searchable` with a short debounce (~250 ms): empty query keeps the unplayed Inbox; non-empty shows Podcasts + Episodes sections. Matching feeds navigate to `FeedDetailView`; episodes reuse `EpisodeRow` (play / download / queue / mark played). **Subscriptions** also filters the feed list via searchable. Empty states when nothing matches.


## Full player

Tap the mini player title or progress bar to open a full-screen sheet: feed artwork, episode title, podcast name, scrubber synced to `PlaybackService`, play/pause, ±30s, speed menu, sleep timer (same presets as mini), plus mark played / queue / download. Chevron dismisses back to the mini player. Prior tabs (Inbox, search, discovery, etc.) unchanged.

## Chapters

Feed-item chapters are parsed by the Swift `XMLParser` path (`NativeRssAtomParser`): Podlove Simple Chapters (`psc:chapter` / `sc:chapter` with `start`/`title`/`href`/`image`) on RSS items and Atom entries, plus Podcast Index `<podcast:chapters url="…">`. Remote Podcast Index JSON is fetched lazily when the full player opens if only a URL is present. Model: `PodcastChapter` (`title`, `startTimeSeconds`, optional `href`/`imageUrl`). Full player shows a chapter list (hidden when empty); tap seeks; the active chapter is highlighted from `PlaybackService.positionSeconds`. ID3/M4A/Vorbis media tags are not parsed yet.

## Headset / Bluetooth pause

`PlaybackService` observes `AVAudioSession` interruption notifications (pause on began; resume on ended when `shouldResume`) and route changes (pause when the old output is unavailable — headphones unplugged). Bluetooth headset play/pause buttons stay on `MPRemoteCommandCenter` / Now Playing; interruption handling only pauses or resumes `AVPlayer` and refreshes Now Playing info.


## Feed refresh / Keep updated

Settings → **Feeds / Keep updated** offers refresh presets: Manual only, Every 1 / 4 / 12 / 24 hours (persisted in `AppSettings`). When not manual, opening the app (launch `.task` or returning to foreground via `scenePhase`) calls `PodcastStore.refreshAllFeeds()` if the interval elapsed since `lastFeedRefreshAt` (also stamped after Inbox pull-to-refresh). This is **global** for all subscriptions; per-feed keep-updated is not in this slice. **BGAppRefreshTask is stubbed**: `Info.plist` only has `UIBackgroundModes` → `audio` (no `fetch`, no `BGTaskSchedulerPermittedIdentifiers`), so `FeedRefreshCoordinator` does not register a background task — enable later by adding those keys.


## Auto-download

Settings → **Auto-download**: global on/off (default off), **Episodes per feed** cap (1 / 2 / 3 / 5, default 2), and **Wi‑Fi only** (default on; `NWPathMonitor` allows Wi‑Fi/Ethernet, skips cellular). After every feed refresh (`refreshAllFeeds`, single-podcast refresh, Inbox pull-to-refresh, Keep updated), `AutoDownloadCoordinator` picks the newest unplayed episodes that are not already downloaded or in-flight and enqueues them through `DownloadService.download`. Storage-limit eviction after successful downloads is unchanged. **Per-feed** auto-download toggles are not in this slice.



## Prefer stream vs download

Settings → **Playback → Playback source**: **Prefer download** (local file via `DownloadService.localURL` when present), **Prefer stream** (always the episode network URL even if downloaded), or **Automatic** (default: local if the file exists, else stream). `PlaybackService.play` and continuous queue auto-next honor this; EpisodeRow / Downloads play buttons no longer force a local URL. Mini player and full player show a small **Local** / **Stream** indicator for the active item.

## Discovery

Apple Podcasts search uses the public iTunes Search API (`media=podcast`, no API key) via `URLSession` (`ItunesSearchService`). Results that include a `feedUrl` are listed with artwork, title, and artist; **Subscribe** runs the existing `PodcastStore.subscribe(feedUrl:)` / `FeedRepository` fetch+parse path (same as Add by URL). Search is lightly debounced (~400 ms). Empty results and network/decode errors are surfaced in the Add sheet. Entry: **Subscriptions → +** (Search / Feed URL segmented control).

## OPML

Export writes AntennaPod-compatible OPML 2.0 (`outline` with `text`/`title`/`xmlUrl`/`htmlUrl`) via a share sheet. Import uses the system file picker (`.opml` / `.xml`), parses with Foundation `XMLParser`, and subscribes each feed URL through the existing `FeedRepository` pipeline (skips duplicates; shows progress and per-feed errors). Entry points: **Settings → Import / Export** and **Subscriptions** toolbar.
