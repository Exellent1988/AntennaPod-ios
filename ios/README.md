# ios/ — AntennaPod for iOS

Fork-only SwiftUI shell. Playback via AVFoundation; networking/downloads via URLSession; persistence in-memory for now (SQLite later). Shared KMP parser is validated in `shared/kmp`; the iOS app currently uses a Foundation `XMLParser` fallback with the same golden fixtures in mind. Wiring the XCFramework into the app is the next integration step.

## Status (Phase 1 skeleton)

- Subscribe by feed URL
- Episode list
- Stream playback (AVPlayer, speed, ±30s)
- Lockscreen / Now Playing (title, podcast, artwork, remote play/pause/skip)
- Sleep timer (clock presets + end of episode, fade-out)
- Offline download to Documents/downloads (background URLSession; survives suspend/relaunch)
- Queue tab (JSON)
- Playback progress save / resume
- Mark played / unplayed (manual + smart-mark 30s)
- Settings tab (theme light/dark/system, default playback speed)

## Layout

```
ios/
├── README.md
├── project.yml              # XcodeGen
└── AntennaPod/
    ├── AntennaPodApp.swift
    ├── App/RootTabView.swift
    ├── Data/…               # store, repository, playback, download, parsers
    └── Features/…           # subscriptions, add feed, player, downloads, queue, settings
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

Subscriptions, queue, and per-episode playback state (`positionSeconds`, `durationSeconds`, `isPlayed`) are stored as JSON under Application Support (`PodcastPersistence`: `feeds.json`, `queue.json`, `playback.json`). Playback resumes from the saved position; episodes are auto-marked played within the last 30 seconds (AntennaPod `smartMarkAsPlayed` default) or when playback ends. Theme and default playback speed live in `UserDefaults` (`AppSettings`) and apply via `preferredColorScheme` / fresh episode starts. Downloads are files under Documents/downloads with a JSON catalog (`downloads.json`) and in-flight background task↔episode map (`pending-downloads.json`). Background transfers use `URLSessionConfiguration.background(withIdentifier:)` plus `AppDelegate.handleEventsForBackgroundURLSession`. GRDB/SQLite aligned with AntennaPod schema comes later.
