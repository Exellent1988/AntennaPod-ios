# ios/ — AntennaPod for iOS

Fork-only SwiftUI shell. Playback via AVFoundation; networking/downloads via URLSession; persistence in-memory for now (SQLite later). Shared KMP parser is validated in `shared/kmp`; the iOS app currently uses a Foundation `XMLParser` fallback with the same golden fixtures in mind. Wiring the XCFramework into the app is the next integration step.

## Status (Phase 1 skeleton)

- Subscribe by feed URL
- Apple Podcasts / iTunes Search discovery (Add sheet; debounced; Subscribe via feed URL)
- Episode list
- Stream playback (AVPlayer, speed, ±30s)
- Lockscreen / Now Playing (title, podcast, artwork, remote play/pause/skip)
- Sleep timer (clock presets + end of episode, fade-out)
- Offline download to Documents/downloads (background URLSession; survives suspend/relaunch)
- Queue tab (JSON)
- Inbox tab (unplayed across subscriptions; pull-to-refresh refreshes all feeds)
- Library search (local subscriptions/episodes; Inbox searchable + Subscriptions filter; not iTunes)
- Playback progress save / resume
- Mark played / unplayed (manual + smart-mark 30s)
- Settings tab (theme light/dark/system, default playback speed)
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

Subscriptions, queue, and per-episode playback state (`positionSeconds`, `durationSeconds`, `isPlayed`) are stored as JSON under Application Support (`PodcastPersistence`: `feeds.json`, `queue.json`, `playback.json`). Inbox is derived from that state (unplayed episodes across feeds, newest first). Playback resumes from the saved position; episodes are auto-marked played within the last 30 seconds (AntennaPod `smartMarkAsPlayed` default) or when playback ends. Theme and default playback speed live in `UserDefaults` (`AppSettings`) and apply via `preferredColorScheme` / fresh episode starts. Downloads are files under Documents/downloads with a JSON catalog (`downloads.json`) and in-flight background task↔episode map (`pending-downloads.json`). Background transfers use `URLSessionConfiguration.background(withIdentifier:)` plus `AppDelegate.handleEventsForBackgroundURLSession`. Download storage limit lives in `UserDefaults` (`AppSettings.downloadStorageLimit`); `DownloadService` measures Documents/downloads usage, enforces the budget after each successful download (and on Settings open / app launch) by deleting **played** episodes first (oldest file mtime), then unplayed (LRU). Settings also offers **Clear downloads** with confirmation. GRDB/SQLite aligned with AntennaPod schema comes later.


## Library search

Local-only search over subscribed feeds and their episodes (title, feed title, feed description) — distinct from Apple Podcasts / iTunes discovery in Add podcast. **Inbox** uses `.searchable` with a short debounce (~250 ms): empty query keeps the unplayed Inbox; non-empty shows Podcasts + Episodes sections. Matching feeds navigate to `FeedDetailView`; episodes reuse `EpisodeRow` (play / download / queue / mark played). **Subscriptions** also filters the feed list via searchable. Empty states when nothing matches.

## Discovery

Apple Podcasts search uses the public iTunes Search API (`media=podcast`, no API key) via `URLSession` (`ItunesSearchService`). Results that include a `feedUrl` are listed with artwork, title, and artist; **Subscribe** runs the existing `PodcastStore.subscribe(feedUrl:)` / `FeedRepository` fetch+parse path (same as Add by URL). Search is lightly debounced (~400 ms). Empty results and network/decode errors are surfaced in the Add sheet. Entry: **Subscriptions → +** (Search / Feed URL segmented control).

## OPML

Export writes AntennaPod-compatible OPML 2.0 (`outline` with `text`/`title`/`xmlUrl`/`htmlUrl`) via a share sheet. Import uses the system file picker (`.opml` / `.xml`), parses with Foundation `XMLParser`, and subscribes each feed URL through the existing `FeedRepository` pipeline (skips duplicates; shows progress and per-feed errors). Entry points: **Settings → Import / Export** and **Subscriptions** toolbar.
