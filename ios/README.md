# ios/ — AntennaPod for iOS

Fork-only SwiftUI shell. Playback via AVFoundation; networking/downloads via URLSession; persistence in-memory for now (SQLite later). Shared KMP parser is validated in `shared/kmp`; the iOS app currently uses a Foundation `XMLParser` fallback with the same golden fixtures in mind. Wiring the XCFramework into the app is the next integration step.

## Status (Phase 1 skeleton)

- Subscribe by feed URL
- Apple Podcasts / iTunes Search discovery (Add sheet; debounced; Subscribe via feed URL)
- Podcast Index discovery (Add sheet tab; user-supplied API key+secret in Keychain; Settings → Discovery; debounced; Subscribe via feed URL)
- Top lists / Quick discovery (Apple iTunes RSS charts; Home preview + Subscriptions → Discover; country in Settings; pull-to-refresh; Subscribe via feed URL)
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
- Inbox tab (unplayed, non-archived across subscriptions; pull-to-refresh; swipe Archive + Archive all)
- History (played / in-progress; Subscriptions → Library → History; newest last-played first)
- Favorites / starred episodes (Subscriptions → Library → Favorites; star on EpisodeRow + full player; `favorites.json`; auto-delete skips favorites)
- Archive / restore episodes (side map `archived.json`; hide from Inbox / Home New; feed lists keep with dim/badge; EpisodeRow + Feed/Inbox swipe; Library → Archived; bulk Archive all in Inbox)
- Episodes / All episodes (Subscriptions → Library → Episodes; all feeds, newest pubDate first; soft cap 500; searchable title/feed filter; EpisodeRow actions)
- Share podcast / episode (FeedDetail toolbar share feed URL; EpisodeRow ShareLink / context menu / FeedDetail swipe; full player; prefer page link else enclosure)
- Library search (local subscriptions/episodes; Inbox searchable + Subscriptions filter; not iTunes)
- Playback progress save / resume (`lastPlayedAt` for History)
- Mark played / unplayed (manual + smart-mark 30s)
- Settings tab (theme light/dark/system, default playback speed, rewind/FF intervals, skip intro/outro, playback source, feed refresh interval, auto-download, auto-delete after play, notify on new episodes / download errors, Discovery charts country + Podcast Index API keys, gpodder.net / Nextcloud Gpodder sync)
- Prefer stream vs download (Prefer download / Prefer stream / Automatic; honored on play)
- Continuous playback (auto-next from queue when an episode ends)
- Feed refresh / Keep updated (global interval; auto on launch & foreground when due)
- Auto-download (global on/off + episodes-per-feed cap; after refresh; optional Wi‑Fi only; per-feed Use global / Always / Never)
- Per-feed settings (Feed detail → gear: Auto-download, Keep updated, Notify overrides)
- Tags / Folders for subscriptions (side map `feed-tags.json`; manage on per-feed settings; Subscriptions filter chips + optional group-by-tag; untagged)
- OPML import/export (Settings + Subscriptions; share sheet / file picker; batch subscribe)
- Download storage limit (Settings: usage + max size; auto-evict played first)
- Auto-delete after playing (global toggle; deletes offline file on mark played; keeps episode row)
- Notifications for new episodes (local UserNotifications after refresh; Settings toggle; tap opens Inbox; no push)
- Download log / errors (ring buffer in Application Support; Downloads banner + errors list; Clear errors)
- Notify on download errors (local UserNotifications; Settings toggle default on; tap opens Downloads; Sync-error notify later; no push)
- gpodder.net / Nextcloud Gpodder sync (subscriptions MVP: provider picker; Keychain; pull+push feed URLs; additive merge; episode actions later)

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
    └── Features/…           # home (+ charts preview), inbox, all episodes, history, favorites, archived, library search, subscriptions (+ Discover charts), feed detail + per-feed settings (+ tags), add/discover, top lists, player, downloads (+ error log), queue, settings (+ gpodder/Nextcloud sync + charts country), OPML, notifications (new eps + DL errors)
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

Subscriptions, queue, per-feed settings (`feed-settings.json`), subscription tags (`feed-tags.json`), starred episode ids (`favorites.json`), archived episode ids (`archived.json`), and per-episode playback state (`positionSeconds`, `durationSeconds`, `isPlayed`, `lastPlayedAtEpochMs`) are stored as JSON under Application Support (`PodcastPersistence`: `feeds.json`, `queue.json`, `feed-settings.json`, `feed-tags.json`, `favorites.json`, `archived.json`, `playback.json`). Inbox is derived from that state (unplayed, non-archived episodes across feeds, newest first). Archived episodes stay on feed lists (dimmed/badge) and in Library → Archived. All Episodes is the same cross-feed catalog without the unplayed filter (newest pubDate first, soft-capped at 500). History lists played or in-progress episodes (newest `lastPlayedAt` first); swipe removes playback state or marks unplayed. Older `playback.json` without `lastPlayedAt` migrates from `updatedAt` when played/in-progress. Playback resumes from the saved position; episodes are auto-marked played within the last 30 seconds (AntennaPod `smartMarkAsPlayed` default) or when playback ends. Theme, default playback speed, rewind/fast-forward intervals, skip intro/outro seconds, playback source preference, feed refresh interval, auto-download, auto-delete-after-playing, and notify-on-new-episodes / notify-on-download-errors prefs live in `UserDefaults` (`AppSettings`) and apply via `preferredColorScheme` / fresh episode starts / mini+full+Now Playing skip / `PlaybackService.play` source resolution / launch+foreground due-check / post-refresh enqueue / mark-played download cleanup. Downloads are files under Documents/downloads with a JSON catalog (`downloads.json`), in-flight background task↔episode map (`pending-downloads.json`), and a recent download-error ring buffer (`download-errors.json`, ~50 entries: episode id/title, feed, message, timestamp). Background transfers use `URLSessionConfiguration.background(withIdentifier:)` plus `AppDelegate.handleEventsForBackgroundURLSession`. Download storage limit lives in `UserDefaults` (`AppSettings.downloadStorageLimit`); `DownloadService` measures Documents/downloads usage, enforces the budget after each successful download (and on Settings open / app launch) by deleting **played** episodes first (oldest file mtime), then unplayed (LRU). Settings also offers **Clear downloads** with confirmation. GRDB/SQLite aligned with AntennaPod schema comes later.



## Home

Primary root tab aggregating existing store data (no new persistence). Sections (hidden when empty):

- **Continue listening** — in-progress episodes (`positionSeconds > 1`, not played), newest `lastPlayedAt` first; rows reuse `EpisodeRow` (resume / download / queue / mark).
- **New / Inbox** — preview of unplayed, non-archived episodes (same as Inbox, capped); chevron / See all switches to the Inbox tab.
- **Queue** — preview of queued episodes when the queue is non-empty; See all → Queue tab.
- **Recently updated** — subscriptions sorted by newest episode `pubDateEpochMs`; tap → `FeedDetailView`; See all → Subscriptions.

- **Discover** — Apple iTunes top podcasts preview (charts country from Settings); See all → full charts list with Subscribe.

Pull-to-refresh calls `refreshAllFeeds()` (Discover preview reloads on appear / country change). Empty library still shows Discover plus a welcome empty state. Section layout is fixed for this beta (not user-configurable like Android Home).

## Library search

Local-only search over subscribed feeds and their episodes (title, feed title, feed description) — distinct from Apple Podcasts / iTunes discovery in Add podcast. **Inbox** uses `.searchable` with a short debounce (~250 ms): empty query keeps the unplayed Inbox; non-empty shows Podcasts + Episodes sections. Matching feeds navigate to `FeedDetailView`; episodes reuse `EpisodeRow` (play / download / queue / mark played). **Subscriptions** also filters the feed list via searchable. Empty states when nothing matches.

## History

**Subscriptions → Library → History** (no extra root tab). Lists episodes that are marked played or have progress (`positionSeconds > 1`), sorted by `lastPlayedAtEpochMs` descending. Rows show feed title and a relative last-played date; tap actions reuse `EpisodeRow` (play / download / queue / mark played / favorite). Swipe trailing **Remove** clears that episode’s playback state (leaves the feed row). Swipe leading **Mark unplayed** when played (episode drops out of History if there is no remaining progress). Root tabs stay at six (Home first).

## Favorites

**Subscriptions → Library → Favorites** (no extra root tab; no Home preview in this slice). Starred episode IDs live in Application Support `favorites.json` (episode id → `favoritedAtEpochMs`), independent of `playback.json` so clearing History does not unstar. Toggle from **EpisodeRow** (star icon) or the **full player** secondary actions. List is newest-favorited first across feeds; swipe **Unfavorite**. When **Delete episode after playing** is on, auto-delete **skips** favorited episodes (keeps the offline file). Unsubscribing a feed clears that feed’s favorite entries.

## Archive / restore

**Subscriptions → Library → Archived** (no extra root tab). Archived episode IDs live in Application Support `archived.json` (episode id → `archivedAtEpochMs`), independent of played status (`playback.json`). Archive **hides** episodes from **Inbox** and the Home **New / Inbox** preview without marking them played. **Feed** episode lists still show archived items (dimmed + archivebox badge). Toggle from **EpisodeRow** (button + context menu), **Feed detail** leading swipe, **Inbox** trailing swipe, or Inbox toolbar **Archive all**. Library → Archived lists newest-archived first; swipe **Restore**. Unsubscribing a feed clears that feed’s archive entries.

## Episodes (All)

**Subscriptions → Library → Episodes** (no extra root tab). Flat list of episodes from every subscription, newest `pubDateEpochMs` first, showing feed title; rows reuse `EpisodeRow` (play / download / queue / mark / favorite / archive / share). Optional `.searchable` filters by episode title or podcast name (in-memory over the capped list). **Soft limit: newest 500** episodes — not lazy-paged yet; documented so huge libraries stay honest. Distinct from **Inbox** (unplayed only). Root tabs stay at six (Home first).

## Share

Share an **episode** (title + URL) or a **podcast** (title + feed URL) via the system share sheet (`ShareLink` / `UIActivityViewController`). Episode URL prefers the item page/`link`, then the enclosure/`downloadUrl`. **Feed detail** toolbar shares the feed URL; episode rows expose Share as a button and in the context menu (Feed detail also offers a trailing swipe Share). The **full player** secondary actions include Share when a URL is available. No cloud / social deep links beyond the system sheet.

## Full player

Tap the mini player title or progress bar to open a full-screen sheet: feed artwork, episode title, podcast name, scrubber synced to `PlaybackService`, play/pause, rewind/fast-forward (Settings intervals), speed menu, sleep timer (same presets as mini), plus mark played / favorite / queue / download / share. Chevron dismisses back to the mini player. Prior tabs (Inbox, search, discovery, etc.) unchanged.

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

Persisted as a side map keyed by stable `PodcastFeed.id` in Application Support `feed-settings.json` (survives feed refresh; cleared on unsubscribe). Reset to global defaults removes the map entry. Speed / skip-intro·outro per feed are not in this slice (global skip intro/outro lives in Settings → Playback).

The same sheet also manages **Tags / Folders** (see below).

## Tags / Folders

Organize subscriptions with simple string **tags** (Android-style folders, flat — no nested hierarchy in this beta).

- **Persistence:** Application Support `feed-tags.json` — map of feed id → `[String]` (0..n tags per feed). Survives feed refresh; cleared on unsubscribe.
- **Manage:** Feed detail → **gear** (Per-feed settings) → Tags / Folders: add an existing tag or type a new name, swipe/context **Remove**; context **Rename…** (global) or **Delete tag everywhere**. Feed detail shows assigned tags when any exist (**Manage tags…** opens the same sheet).
- **Subscriptions list:** when any tags exist, filter chips (**All** / each tag / **Untagged**) plus optional **Group by tag** (All only): sections per tag then Untagged; a podcast with several tags appears under each. With grouping off, tag names show as a subtitle on rows.
- **Lifecycle:** tags exist only while assigned; removing the last use drops the name from the vocabulary (no empty-tag Settings manager in this MVP).

## Skip intervals (Rewind / Fast-forward)

Settings → **Playback → Rewind** / **Fast-forward**: presets **5 / 10 / 15 / 20 / 30 / 60** seconds (`AppSettings.rewindSeconds` / `fastForwardSeconds`, UserDefaults). Defaults match AntennaPod Android (`prefRewindSecs` = 10, `prefFastForwardSecs` = 30). Mini player, full player, and Lockscreen / Now Playing remote skip commands all use these values (SF Symbol icons update when a numbered glyph exists; 20s falls back to plain `gobackward` / `goforward`). Changing the pickers refreshes `MPRemoteCommandCenter` preferred intervals immediately.

## Skip intro / Skip outro

Settings → **Playback → Skip intro** / **Skip outro**: presets **0 / 5 / 10 / 15 / 30 / 60** seconds (`AppSettings.skipIntroSeconds` / `skipOutroSeconds`, UserDefaults; **0 = Off**). On a **fresh start** (resume position ≈ 0), playback seeks forward by skip-intro once per episode play session. When duration is known and **remaining ≤ skip-outro**, `PlaybackService` treats the episode as finished once (mark played + continuous queue next, same path as natural end) — guarded so it does not loop. Resume from mid-episode does not re-apply skip intro. **Global only** in this beta; per-feed override is later (same as speed).

## Prefer stream vs download

Settings → **Playback → Playback source**: **Prefer download** (local file via `DownloadService.localURL` when present), **Prefer stream** (always the episode network URL even if downloaded), or **Automatic** (default: local if the file exists, else stream). `PlaybackService.play` and continuous queue auto-next honor this; EpisodeRow / Downloads play buttons no longer force a local URL. Mini player and full player show a small **Local** / **Stream** indicator for the active item.

## Auto-delete after playing

Settings → **Downloads / Storage → Delete episode after playing** (default off, `AppSettings.autoDeleteAfterPlaying`). When an episode is marked played — manual toggle or playback finished / continuous auto-next (`PlaybackService` → `PodcastStore.markPlayed`) — if a local download exists, `DownloadService.delete` removes the offline file and catalog entry. The feed episode row and `isPlayed` status stay. Deletion is deferred while that episode is still the active player item **and** playing from a local file (`shouldBlockAutoDelete`); `PlaybackService` flushes the pending delete on end / stop / switch. **Favorited / starred episodes are skipped** (offline file kept). Starring while a delete is pending cancels it. Storage-limit eviction is unchanged.


## Notifications (new episodes)

Settings → **Notifications → Notify on new episodes** (default on). Uses `UserNotifications` **locally** only — no APNs / push server. Permission is requested when you enable the toggle, or on the first feed refresh that finds new episodes while the toggle is on and status is still undetermined. Settings shows Allowed / Denied / Not determined; if denied, the preference can stay on but no banners fire until iOS Settings allows Notifications (Open iOS Settings button). Per-feed **Notify on new episodes** (Use global / Always / Never) overrides the global toggle for that podcast. After Inbox pull-to-refresh, Keep updated, or a single podcast refresh, newly appeared episode IDs (existing subscriptions only — not first subscribe) post a local notification: **title** = feed title, **body** = episode title, or **“N new episodes”** when several arrive for that feed. Tap opens the **Inbox** tab (best-effort; feed-detail deep link not wired). `PodcastFeed.id` is preserved across refresh so notification ids stay stable.

## Download log / errors + notify on failures

Failed downloads are appended to a ring buffer (~50) in Application Support `download-errors.json` (episode id, title, feed title, message, timestamp). `DownloadService.lastError` still drives a red **Last download failed** banner on the **Downloads** tab (episode + feed when known). **Downloads → Errors** toolbar and **Settings → Notifications → Download errors** open the same simple list; **Clear** wipes the log and banner (offline files kept).

Settings → **Notifications → Notify on download errors** (default on) reuses the same `UNUserNotificationCenter` permission path as new-episode alerts. On failure (no media URL, HTTP error, move failure, or task error — not user cancel), if the toggle is on and permission allows, a **local** notification posts: **title** = episode title, **body** = short error. Tap opens the **Downloads** tab. **No push / APNs.** Sync-error notifications are **not** implemented yet (matrix: DL done, Sync later).

## Discovery

Add podcast sheet (**Subscriptions → +**) has three segments: **Apple Podcasts**, **Podcast Index**, and **Feed URL**.

**Top lists / Charts** (**Home → Discover** preview, **Subscriptions → Library → Discover**, or See all charts): public Apple iTunes RSS `https://itunes.apple.com/{country}/rss/toppodcasts/limit=25/explicit=true/json` (no API key). Country defaults to the device region (fallback **de**); override under **Settings → Discovery → Charts country**. Entries are parsed for title / artist / artwork; collection ids are resolved to RSS `feedUrl` via a batch `itunes.apple.com/lookup` call. Pull-to-refresh reloads the list; network/country errors are shown honestly. **Subscribe** uses `PodcastStore.subscribe(feedUrl:)` (same pipeline as search / URL).

**Apple Podcasts** uses the public iTunes Search API (`media=podcast`, no API key) via `URLSession` (`ItunesSearchService`). Results that include a `feedUrl` are listed with artwork, title, and artist; **Subscribe** runs the existing `PodcastStore.subscribe(feedUrl:)` / `FeedRepository` fetch+parse path (same as Add by URL). Search is lightly debounced (~400 ms). Empty results and network/decode errors are surfaced in the Add sheet.

**Podcast Index** (`PodcastIndexSearchService`) calls `https://api.podcastindex.org/api/1.0/search/byterm` with auth headers `X-Auth-Date`, `X-Auth-Key`, and `Authorization` = SHA-1(`apiKey` + `apiSecret` + unix time) per the Podcast Index docs. **API key and secret are user-supplied** (free registration at podcastindex.org) and stored only in the **Keychain** (`PodcastIndexKeychain`) — nothing is hardcoded or shipped with the app. Paste them under **Settings → Discovery / Podcast Index**. If keys are missing, the Add sheet shows an honest empty state explaining how to get keys. Results show title, author, and artwork; **Subscribe** reuses the same feed URL pipeline. Debounce matches Apple (~400 ms).


## Sync / gpodder.net / Nextcloud

Settings → **Sync** (beta MVP — **subscriptions only**):

- **Provider** picker: **gpodder.net** (default) vs **Nextcloud** (Gpodder Sync app).
- **Host / base URL**
  - gpodder.net: defaults to `https://gpodder.net` (editable).
  - Nextcloud: custom base — server root (`https://cloud.example.com`) or full API root (`https://cloud.example.com/index.php/apps/gpoddersync/`). If the path does not already contain `gpoddersync`, the client appends `index.php/apps/gpoddersync/` (same root AntennaPod Android + [nextcloud-gpodder](https://github.com/thrillfall/nextcloud-gpodder) use).
- **Username** / **password**: password in the **Keychain**; username + provider + host + device metadata in `UserDefaults`. Nextcloud: prefer an **app password**.
- **Device name** + stable **device id** (gpodder.net API2; Nextcloud has no device API — fields kept for UI/state only; update is a no-op).
- **Login** / **Logout** / **Sync now**; last sync time, status, error.

Client (`GpodderClient`, `URLSession`, HTTP Basic), reused for both providers:

**gpodder.net** ([API reference](https://gpoddernet.readthedocs.io/en/latest/api/reference/)):

- `POST /api/2/auth/{username}/login.json`
- `POST /api/2/devices/{username}/{deviceid}.json`
- `GET /api/2/subscriptions/{username}/{deviceid}.json?since=`
- `POST /api/2/subscriptions/{username}/{deviceid}.json` with `{ "add", "remove" }`

**Nextcloud** (API root `…/index.php/apps/gpoddersync/`):

- Login probes `GET …/subscriptions?since=0` (no dedicated auth/device endpoints).
- `GET …/subscriptions?since=`
- `POST …/subscription_change/create` with `{ "add", "remove" }`

**Sync behavior (both):** pull remote adds → `subscribeQuietly` for missing feeds; push local URLs not on the server. **Additive merge:** remote `remove` does **not** unsubscribe local podcasts. Episode actions are **not** synced yet (honest MVP; same limits for Nextcloud as gpodder.net).

## OPML

Export writes AntennaPod-compatible OPML 2.0 (`outline` with `text`/`title`/`xmlUrl`/`htmlUrl`) via a share sheet. Import uses the system file picker (`.opml` / `.xml`), parses with Foundation `XMLParser`, and subscribes each feed URL through the existing `FeedRepository` pipeline (skips duplicates; shows progress and per-feed errors). Entry points: **Settings → Import / Export** and **Subscriptions** toolbar.
