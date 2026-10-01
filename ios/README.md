# ios/ — AntennaPod for iOS

Fork-only SwiftUI shell. Playback via AVFoundation; networking/downloads via URLSession; persistence in-memory for now (SQLite later). Shared KMP parser is validated in `shared/kmp`; the iOS app currently uses a Foundation `XMLParser` fallback with the same golden fixtures in mind. Wiring the XCFramework into the app is the next integration step.

## Status (Phase 1 skeleton)

- Subscribe by feed URL
- Apple Podcasts / iTunes Search discovery (Add sheet; debounced; Subscribe via feed URL)
- Episode list
- Stream playback (AVPlayer, speed, configurable skip intervals)
- Full player sheet (artwork, scrubber, transport; tap mini player to open)
- Chapters (PSC / Podcast Index from feed; list in full player; tap to seek)
- Lockscreen / Now Playing (title, podcast, artwork, remote play/pause/skip using Settings intervals)
- Headset / Bluetooth pause (AVAudioSession interruption + headphone unplug; remotes unchanged)
- Sleep timer (clock presets + end of episode, fade-out)
- Offline download to Documents/downloads (background URLSession; survives suspend/relaunch)
- Queue tab (JSON)
- Home tab (Continue listening, Inbox / Queue previews, recently updated feeds; pull-to-refresh)
- Inbox tab (unplayed across subscriptions; pull-to-refresh refreshes all feeds)
- History (played / in-progress; Subscriptions → Library → History; newest last-played first)
- Library search (local subscriptions/episodes; Inbox searchable + Subscriptions filter; not iTunes)
- Playback progress save / resume (`lastPlayedAt` for History)
- Mark played / unplayed (manual + smart-mark 30s)
- Settings tab (theme light/dark/system, default playback speed, rewind/FF intervals, playback source, feed refresh interval, auto-download, auto-delete after play, notify on new episodes)
- Prefer stream vs download (Prefer download / Prefer stream / Automatic; honored on play)
- Continuous playback (auto-next from queue when an episode ends)
- Feed refresh / Keep updated (global interval; auto on launch & foreground when due)
- Auto-download (global on/off + episodes-per-feed cap; after refresh; optional Wi‑Fi only; per-feed Use global / Always / Never)
- Per-feed settings (Feed detail → gear: Auto-download, Keep updated, Notify overrides)
- OPML import/export (Settings + Subscriptions; share sheet / file picker; batch subscribe)
- Download storage limit (Settings: usage + max size; auto-evict played first)
- Auto-delete after playing (global toggle; deletes offline file on mark played; keeps episode row)
- Notifications for new episodes (local UserNotifications after refresh; Settings toggle; tap opens Inbox; no push)

Root tabs (6): **Home**, Inbox, Subscriptions, Queue, Downloads, Settings.

## Layout

```
ios/
├── README.md
├── project.yml              # XcodeGen
└── AntennaPod/
    ├── AntennaPodApp.swift
    ├── App/RootTabView.swift
    ├── Data/…               # store, repository, playback, download, parsers
    └── Features/…           # home, inbox, history, library search, subscriptions, feed detail + per-feed settings, add/discover, player, downloads, queue, settings, OPML, notifications
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

Subscriptions, queue, per-feed settings (`feed-settings.json`), and per-episode playback state (`positionSeconds`, `durationSeconds`, `isPlayed`, `lastPlayedAtEpochMs`) are stored as JSON under Application Support (`PodcastPersistence`: `feeds.json`, `queue.json`, `feed-settings.json`, `playback.json`). Inbox is derived from that state (unplayed episodes across feeds, newest first). History lists played or in-progress episodes (newest `lastPlayedAt` first); swipe removes playback state or marks unplayed. Older `playback.json` without `lastPlayedAt` migrates from `updatedAt` when played/in-progress. Playback resumes from the saved position; episodes are auto-marked played within the last 30 seconds (AntennaPod `smartMarkAsPlayed` default) or when playback ends. Theme, default playback speed, rewind/fast-forward intervals, playback source preference, feed refresh interval, auto-download, auto-delete-after-playing, and notify-on-new-episodes prefs live in `UserDefaults` (`AppSettings`) and apply via `preferredColorScheme` / fresh episode starts / mini+full+Now Playing skip / `PlaybackService.play` source resolution / launch+foreground due-check / post-refresh enqueue / mark-played download cleanup. Downloads are files under Documents/downloads with a JSON catalog (`downloads.json`) and in-flight background task↔episode map (`pending-downloads.json`). Background transfers use `URLSessionConfiguration.background(withIdentifier:)` plus `AppDelegate.handleEventsForBackgroundURLSession`. Download storage limit lives in `UserDefaults` (`AppSettings.downloadStorageLimit`); `DownloadService` measures Documents/downloads usage, enforces the budget after each successful download (and on Settings open / app launch) by deleting **played** episodes first (oldest file mtime), then unplayed (LRU). Settings also offers **Clear downloads** with confirmation. GRDB/SQLite aligned with AntennaPod schema comes later.



## Home

Primary root tab aggregating existing store data (no new persistence). Sections (hidden when empty):

- **Continue listening** — in-progress episodes (`positionSeconds > 1`, not played), newest `lastPlayedAt` first; rows reuse `EpisodeRow` (resume / download / queue / mark).
- **New / Inbox** — preview of unplayed episodes (same as Inbox, capped); chevron / See all switches to the Inbox tab.
- **Queue** — preview of queued episodes when the queue is non-empty; See all → Queue tab.
- **Recently updated** — subscriptions sorted by newest episode `pubDateEpochMs`; tap → `FeedDetailView`; See all → Subscriptions.

Pull-to-refresh calls `refreshAllFeeds()`. Empty library shows a welcome empty state. Section layout is fixed for this beta (not user-configurable like Android Home).

## Library search

Local-only search over subscribed feeds and their episodes (title, feed title, feed description) — distinct from Apple Podcasts / iTunes discovery in Add podcast. **Inbox** uses `.searchable` with a short debounce (~250 ms): empty query keeps the unplayed Inbox; non-empty shows Podcasts + Episodes sections. Matching feeds navigate to `FeedDetailView`; episodes reuse `EpisodeRow` (play / download / queue / mark played). **Subscriptions** also filters the feed list via searchable. Empty states when nothing matches.

## History

**Subscriptions → Library → History** (no extra root tab). Lists episodes that are marked played or have progress (`positionSeconds > 1`), sorted by `lastPlayedAtEpochMs` descending. Rows show feed title and a relative last-played date; tap actions reuse `EpisodeRow` (play / download / queue / mark played). Swipe trailing **Remove** clears that episode’s playback state (leaves the feed row). Swipe leading **Mark unplayed** when played (episode drops out of History if there is no remaining progress). Root tabs stay at six (Home first).

## Full player

Tap the mini player title or progress bar to open a full-screen sheet: feed artwork, episode title, podcast name, scrubber synced to `PlaybackService`, play/pause, rewind/fast-forward (Settings intervals), speed menu, sleep timer (same presets as mini), plus mark played / queue / download. Chevron dismisses back to the mini player. Prior tabs (Inbox, search, discovery, etc.) unchanged.

## Chapters

Feed-item chapters are parsed by the Swift `XMLParser` path (`NativeRssAtomParser`): Podlove Simple Chapters (`psc:chapter` / `sc:chapter` with `start`/`title`/`href`/`image`) on RSS items and Atom entries, plus Podcast Index `<podcast:chapters url="…">`. Remote Podcast Index JSON is fetched lazily when the full player opens if only a URL is present. Model: `PodcastChapter` (`title`, `startTimeSeconds`, optional `href`/`imageUrl`). Full player shows a chapter list (hidden when empty); tap seeks; the active chapter is highlighted from `PlaybackService.positionSeconds`. ID3/M4A/Vorbis media tags are not parsed yet.

## Headset / Bluetooth pause

`PlaybackService` observes `AVAudioSession` interruption notifications (pause on began; resume on ended when `shouldResume`) and route changes (pause when the old output is unavailable — headphones unplugged). Bluetooth headset play/pause buttons stay on `MPRemoteCommandCenter` / Now Playing; interruption handling only pauses or resumes `AVPlayer` and refreshes Now Playing info.


## Feed refresh / Keep updated

Settings → **Feeds / Keep updated** offers refresh presets: Manual only, Every 1 / 4 / 12 / 24 hours (persisted in `AppSettings`). When not manual, opening the app (launch `.task` or returning to foreground via `scenePhase`) calls `PodcastStore.refreshAllFeeds()` if the interval elapsed since `lastFeedRefreshAt` (also stamped after Inbox pull-to-refresh). Global interval still drives when auto refresh runs; per-feed **Keep updated → Never** skips that feed in `refreshAllFeeds` (single-feed refresh from Subscriptions still works). Use global / Always both participate today. **BGAppRefreshTask is stubbed**: `Info.plist` only has `UIBackgroundModes` → `audio` (no `fetch`, no `BGTaskSchedulerPermittedIdentifiers`), so `FeedRefreshCoordinator` does not register a background task — enable later by adding those keys.


## Auto-download

Settings → **Auto-download**: global on/off (default off), **Episodes per feed** cap (1 / 2 / 3 / 5, default 2), and **Wi‑Fi only** (default on; `NWPathMonitor` allows Wi‑Fi/Ethernet, skips cellular). After every feed refresh (`refreshAllFeeds`, single-podcast refresh, Inbox pull-to-refresh, Keep updated), `AutoDownloadCoordinator` picks the newest unplayed episodes that are not already downloaded or in-flight and enqueues them through `DownloadService.download`. Storage-limit eviction after successful downloads is unchanged. **Per-feed** Auto-download (Use global / Always / Never) is on each podcast’s settings sheet (Feed detail → gear); Always enqueues even when global is off; Never skips that feed; episode cap and Wi‑Fi-only remain global.





## Per-feed settings

Feed detail → **gear** opens a sheet with tri-state overrides (Use global / Always / Never):

- **Auto-download** — Always/Never beat the global Settings toggle; episode cap and Wi‑Fi-only stay global.
- **Keep updated** — Never excludes the podcast from refresh-all; Use global / Always both refresh with the others.
- **Notify on new episodes** — Always/Never beat the global notification toggle (system permission still required).

Persisted as a side map keyed by stable `PodcastFeed.id` in Application Support `feed-settings.json` (survives feed refresh; cleared on unsubscribe). Reset to global defaults removes the map entry. Speed / skip-intro per feed are not in this slice.

## Skip intervals (Rewind / Fast-forward)

Settings → **Playback → Rewind** / **Fast-forward**: presets **5 / 10 / 15 / 20 / 30 / 60** seconds (`AppSettings.rewindSeconds` / `fastForwardSeconds`, UserDefaults). Defaults match AntennaPod Android (`prefRewindSecs` = 10, `prefFastForwardSecs` = 30). Mini player, full player, and Lockscreen / Now Playing remote skip commands all use these values (SF Symbol icons update when a numbered glyph exists; 20s falls back to plain `gobackward` / `goforward`). Changing the pickers refreshes `MPRemoteCommandCenter` preferred intervals immediately.

## Prefer stream vs download

Settings → **Playback → Playback source**: **Prefer download** (local file via `DownloadService.localURL` when present), **Prefer stream** (always the episode network URL even if downloaded), or **Automatic** (default: local if the file exists, else stream). `PlaybackService.play` and continuous queue auto-next honor this; EpisodeRow / Downloads play buttons no longer force a local URL. Mini player and full player show a small **Local** / **Stream** indicator for the active item.

## Auto-delete after playing

Settings → **Downloads / Storage → Delete episode after playing** (default off, `AppSettings.autoDeleteAfterPlaying`). When an episode is marked played — manual toggle or playback finished / continuous auto-next (`PlaybackService` → `PodcastStore.markPlayed`) — if a local download exists, `DownloadService.delete` removes the offline file and catalog entry. The feed episode row and `isPlayed` status stay. Deletion is deferred while that episode is still the active player item **and** playing from a local file (`shouldBlockAutoDelete`); `PlaybackService` flushes the pending delete on end / stop / switch. Favorites/starred are not implemented yet (no skip). Storage-limit eviction is unchanged.


## Notifications (new episodes)

Settings → **Notifications → Notify on new episodes** (default on). Uses `UserNotifications` **locally** only — no APNs / push server. Permission is requested when you enable the toggle, or on the first feed refresh that finds new episodes while the toggle is on and status is still undetermined. Settings shows Allowed / Denied / Not determined; if denied, the preference can stay on but no banners fire until iOS Settings allows Notifications (Open iOS Settings button). Per-feed **Notify on new episodes** (Use global / Always / Never) overrides the global toggle for that podcast. After Inbox pull-to-refresh, Keep updated, or a single podcast refresh, newly appeared episode IDs (existing subscriptions only — not first subscribe) post a local notification: **title** = feed title, **body** = episode title, or **“N new episodes”** when several arrive for that feed. Tap opens the **Inbox** tab (best-effort; feed-detail deep link not wired). `PodcastFeed.id` is preserved across refresh so notification ids stay stable.

## Discovery

Apple Podcasts search uses the public iTunes Search API (`media=podcast`, no API key) via `URLSession` (`ItunesSearchService`). Results that include a `feedUrl` are listed with artwork, title, and artist; **Subscribe** runs the existing `PodcastStore.subscribe(feedUrl:)` / `FeedRepository` fetch+parse path (same as Add by URL). Search is lightly debounced (~400 ms). Empty results and network/decode errors are surfaced in the Add sheet. Entry: **Subscriptions → +** (Search / Feed URL segmented control).

## OPML

Export writes AntennaPod-compatible OPML 2.0 (`outline` with `text`/`title`/`xmlUrl`/`htmlUrl`) via a share sheet. Import uses the system file picker (`.opml` / `.xml`), parses with Foundation `XMLParser`, and subscribes each feed URL through the existing `FeedRepository` pipeline (skips duplicates; shows progress and per-feed errors). Entry points: **Settings → Import / Export** and **Subscriptions** toolbar.
