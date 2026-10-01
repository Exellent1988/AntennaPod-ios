# Feature-Matrix (Android → iOS)

Status: `todo` | `wip` | `done` | `partial` | `n/a` (kein sinnvolles iOS-Äquivalent).  
Gewicht: 5 = P0 … 1 = P4. Details und Begründung: [PLAN.md](PLAN.md).

Stand abgeleitet aus Android-Navigation (`NavigationNames`), Preferences (`ui/preferences`) und Modulgrenzen.

## Navigation / Shell

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Home (konfigurierbare Sektionen) | 4 | done | Primary tab driven by Settings → Home layout: ordered section ids + visibility (Continue, Inbox, Queue, Discover/Top lists, Recently updated, Favorites optional/default-off). Empty optional sections still hide; Discover keeps charts preview when enabled; Edit/drag reorder + Reset; pull-to-refresh; See all → other tabs |
| Queue | 5 | done | JSON persistence; swipe Remove + Archive; Edit → drag reorder (`moveQueue`); `.searchable` filters by episode title and/or feed title (light debounce ~250 ms; empty query = all); **Edit/reorder disabled while filtering** (filtered indices ≠ full queue); empty state when no matches; toolbar **Clear queue** (confirm with **full** queue count; `clearQueue` → `queue = []`, persists via didSet; does not stop playback / mark played / delete downloads; disabled when queue empty — not when filter empty); **Play Next** (`playNext`) inserts after currently playing queue item (or head if none / current not queued); **Add to Queue** stays append (`enqueue`) |
| Inbox | 4 | done | Unplayed across feeds (`!isPlayed` && not archived), newest first; tab + pull-to-refresh; swipe Archive + Mark played + **Play Next** + **Add to queue**; toolbar menu Archive all + **Mark all as played** (confirm with count; `markPlayed` per Inbox id) |
| Episodes (Alle) | 4 | done | Flat list across subscriptions, newest pubDate first; Subscriptions → Library → Episodes; feed title + EpisodeRow actions; swipe Archive/Restore + Mark played; filter chips **All** (default) / **Unplayed** (`!isPlayed` && not archived, within cap) / **Downloaded** (`DownloadService.isDownloaded`); `.searchable` title/feed filter; soft cap newest 500 **then** filter+search; chip selection persisted in `AppSettings.allEpisodesFilter` (+ backup) |
| Downloads-Liste | 5 | done | Local files + persisted catalog; swipe Delete download; `.searchable` filters by episode title and/or feed title (light debounce ~250 ms; empty query = all); empty state when no matches; error log + notify; toolbar **Delete played downloads** (confirm with count + size; `deletePlayedDownloads` via single `delete(_:)`; skips favorites like auto-delete; keeps unplayed / played status / queue; not Clear all; disabled when none eligible) |
| History | 3 | done | Played / in-progress across feeds, newest `lastPlayedAt` first; Subscriptions → Library → History; swipe remove / mark unplayed; `.searchable` filters by episode title and/or feed title (light debounce ~250 ms; empty query = all); empty state when no matches; toolbar **Clear history** (confirm with **full** history count; `clearHistory` drops whole `playbackStates` entries for listed episodes — same as per-row Remove; does not unsubscribe / delete downloads / clear queue / unstar; disabled when history empty — not when filter empty); tap via EpisodeRow |
| Favorites | 3 | done | Starred episode ids in `favorites.json` side map; star toggle on EpisodeRow + full player; Subscriptions → Library → Favorites (newest first); swipe Unfavorite + Archive; `.searchable` filters by episode title and/or feed title (light debounce ~250 ms; empty query = all); empty state when no matches; toolbar **Clear favorites** (confirm with **full** favorites count; `clearFavorites` clears whole `favoriteAtById` side map — same as per-row Unfavorite; does not delete downloads / archive / mark played / clear queue; disabled when favorites empty — not when filter empty); auto-delete skips favorited downloads |
| Subscriptions | 5 | done | List + subscribe sheet; tags filter/group; **sort** (Recently updated default / Alphabetical A–Z); Discover; Library links; local folder feeds show Folder badge; OPML/HTML import-export |
| Add podcast | 5 | done | URL + Apple Podcasts + Podcast Index + fyyd search + **Folder** (local); charts via Discover; discovery/URL → online Preview then Confirm Subscribe |
| Search (Bibliothek) | 4 | done | Local only: Inbox `.searchable` (debounced) filters feeds + episodes; Subscriptions filters feeds; Queue/Downloads/Favorites/History/Archived filter by title/feed; EpisodeRow actions; not iTunes |
| Statistics | 2 | done | Totals from `playback.json`: played count, approx listening time (played→duration / in-progress→position), per-feed top podcasts; Library + Settings; honest approximation footnote |
| Bottom nav / Drawer-Analog | 4 | done | SwiftUI Tabs (6): Home, Inbox, Subscriptions (+ Library → Episodes / Favorites / Archived / History / Statistics / Echo), Queue, Downloads, Settings |
| Miniplayer + Full Player | 5 | done | Mini player; tap → full sheet (artwork or video surface, scrubber, configurable skip, speed, sleep timer, mark/Play Next/queue/download, video→audio-only toggle) |
| Video Player | 1 | done | **Beta lite**: detect video via MIME `video/*` or enclosure ext mp4/m4v/mov/webm (`PodcastEpisode.isVideo`); full player shows `AVPlayerLayer` surface (replaces artwork) when not audio-only; shares `PlaybackService` AVPlayer. **PiP (beta lite)**: `AVPictureInPictureController(playerLayer:)` toolbar button when video surface shown; observes `isPictureInPicturePossible`; optional `canStartPictureInPictureAutomaticallyFromInline`; hidden/disabled for audio-only / non-video. No dedicated landscape chrome; Lockscreen stays audio metadata; no AirPlay redesign |
| Settings | 5 | done | Tab: theme + **Home layout** (section show/hide + reorder) + default speed + rewind/FF intervals + skip intro/outro + volume adaptation + skip silence (pref only) + **Keep screen on** + **Continuous playback** + **Smart mark as played** + playback source + play video as audio only + download storage limit + refresh interval + **new-episode action** + auto-download + Network/Downloads Wi‑Fi policy + auto-delete after play + notifications (new eps / DL errors / sync errors) + gpodder.net / Nextcloud Gpodder sync + **Parental controls** (PIN) + **Backup** (iOS JSON) + Statistics / Echo + App Store rating prompt + Siri/Shortcuts note + Homescreen widget note + About (P0/P1); more prefs later |

## Subscriptions

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Subscribe / Unsubscribe (URL) | 5 | done | Subscribe by feed URL (+ discovery / local folder); unsubscribe from feed detail; local-folder releases bookmark |
| OPML Import/Export | 5 | done | Pure Swift XML (fork `ios/`); Settings + Subscriptions; batch subscribe with progress/errors |
| Feed aktualisieren | 5 | done | Fetch + parse on subscribe; pull-to-refresh all; auto refresh by Settings interval |
| Episodenliste / Feed-Seite | 5 | done | Feed detail episodes + EpisodeRow; **sort** toolbar (**Newest first** default / **Oldest first** by `pubDateEpochMs`; global `feedEpisodeSort`); swipe Archive/Play Next/Queue/Share; EpisodeRow context Play Next + Add to queue; per-feed gear; toolbar **Download all** + **Mark all as played** (confirm with unplayed/non-archived count; `markPlayed` per id; feed-scoped; does not archive); pull refresh via Subscriptions; Folder badge for local |
| Archive / restore | 3 | done | Side map `archived.json` (id → archivedAt); archived ≠ played. Hide from Inbox (+ Home New preview). EpisodeRow button/context + Feed/Inbox/Queue/Favorites/All Episodes swipes; Inbox Archive all (+ Mark all as played); Library → Archived (`.searchable` title/feed, light debounce ~250 ms; empty query = all; empty state when no matches; swipe Restore; toolbar **Restore all** confirm with **full** archived count; `restoreAllArchived` clears whole `archivedAtById` — same as per-row Restore; does not mark unplayed / delete downloads / clear queue; disabled when archived empty — not when filter empty). Feed lists keep archived with dim/badge (not removed) |
| Tags / Folders | 3 | done | Side map `feed-tags.json` (feed id → string tags, 0..n); manage on Feed detail → gear (Per-feed settings): add existing/new, remove, rename/delete globally; empty tags disappear. Subscriptions: filter chips All / each tag / Untagged + optional Group by tag sections (multi-tag feeds listed under each). Not Android drawer folders / nested hierarchy |
| Subscriptions sort | 2 | done | **Beta**: toolbar menu on Subscriptions — **Recently updated** (default: newest episode `pubDateEpochMs`, same as Home) or **Alphabetical A–Z** by feed title. Pref `subscriptionsSort` in `AppSettings` (UserDefaults + backup). Applied after search/tag filters; group-by-tag sorts feeds within each section the same way. **Client-side only** — no drag-reorder of subscriptions |
| Feed episode sort | 2 | done | **Beta**: Feed detail toolbar **Sort** — **Newest first** (default) / **Oldest first** by episode `pubDateEpochMs`. Global pref `feedEpisodeSort` in `AppSettings` (UserDefaults + backup); not per-feed. Missing dates sort last. **Does not** change Inbox / All Episodes ordering |
| Per-feed settings | 4 | done | Feed detail → gear sheet: Auto-download / Keep updated / New episodes (Use global·Inbox·Queue) / Notify Use global·Always·Never / Skip intro·outro (Use global·Off·presets) / Playback speed (Use global·0.8…2.0); side map `feed-settings.json` |
| Keep updated | 4 | done | Global via Settings refresh interval; per-feed Keep updated Never skips that feed in refresh-all (single-feed refresh still OK) |
| New-episode action (Inbox/Queue) | 4 | done | **Simple beta**: Settings → New episodes Inbox only (default) / Add to Queue / Add to Queue and download; applies to newly appeared eps after refresh (existing subs). Per-feed Use global / Inbox / Queue. Inbox stays derived unplayed list; Queue gets explicit adds. Download uses auto-DL Wi‑Fi gate. **Not** full Android filter rules → KMP later |
| Local folder feeds | 2 | done | **Beta**: Add podcast → Folder (fileImporter); security-scoped bookmark in local-folder-bookmarks.json; synthetic PodcastFeed (local-folder://) from audio files (mp3/m4a/aac/wav/flac); title=filename; file:// already-local; refresh re-scans; unsubscribe releases bookmark; Folder badge; no RSS/network; excluded from OPML/HTML/gpodder |
| Share podcast/episode | 3 | done | Episode: title + page link (else enclosure) via ShareLink; podcast: title + feed URL from FeedDetail toolbar; EpisodeRow button/context menu + FeedDetail swipe; full player ShareLink |

## Playback

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Stream playback | 5 | done | AVPlayer stream + local; mini + full player; continuous queue; Wi‑Fi stream gate optional |
| Lockscreen / Now Playing | 5 | done | MPNowPlayingInfoCenter + remote play/pause/skip (Settings intervals)/scrub; artwork from feed |
| Variable speed | 5 | done | Mini + full player rate menu; default speed from Settings on fresh start |
| Sleep timer (Basis) | 5 | done | Clock presets 5–60 min + end of episode; fade last 10s; mini + full player menu |
| Fortschritt speichern / fortsetzen | 5 | done | JSON `playback.json` (`position` / `duration` / `isPlayed` / `lastPlayedAt`); resume on play |
| Mark played / unplayed | 5 | done | Manual + **Smart mark as played** Settings picker (`smartMarkAsPlayedSeconds`, presets Off/15/30/60/120, default **30**, persisted + backup). Near-end leave/stop marks played within threshold; **Off (0)** = only natural end or explicit mark (not near-end scrub). Inbox toolbar **Mark all as played** (current Inbox list only); Feed detail toolbar **Mark all as played** (this podcast only; unplayed + not archived) |
| Continuous playback (Queue) | 5 | done | Settings **Continuous playback** (`continuousPlaybackEnabled`, default **on**, persisted + backup). When on: auto-next from queue on episode end (`nextQueueEpisode`); Play Next lands as immediate next when current is queued; when current not queued, head-of-queue is auto-next (same as append). When **off**: episode end still marks played / saves progress but does **not** advance. End-of-episode sleep timer still stops without advancing |
| FF / Rewind deltas | 4 | done | Settings presets 5/10/15/20/30/60; defaults 10s rewind / 30s FF (Android); mini + full + Now Playing remotes |
| Skip intro / Skip outro | 3 | done | Global Settings presets 0/5/10/15/30/60 (0=off); seek intro on fresh start (pos≈0); near end remaining≤outro → mark played + continuous next once/session; per-feed override on feed settings sheet (nil=Use global) |
| Skip silence | 2 | partial | **Honest P3**: Settings toggle (`skipSilenceEnabled`, default off, persisted + backup) only — **no silence skip on stock AVPlayer**. Needs custom `AVAudioEngine` graph; would break shared video surface / Now Playing / rate. Do not fake. Not Android ExoPlayer skip-silence |
| Volume adaptation | 2 | done | **Honest P3 lite**: Settings **Volume adaptation** / Optimize for speech (`volumeAdaptationEnabled`, default off, persisted + backup). On → `AVAudioSession` `.spokenAudio` (`.voiceChat` fallback); off → `.default` (audio / audio-only) or `.moviePlayback` (video surface). **iOS session mode**, not Android LoudnessEnhancer gain curve. Reapplied live via `applyAudioSessionConfiguration` |
| Keep screen on | 2 | done | **Beta**: Settings **Keep screen on** (`keepScreenOnWhilePlaying`, default **off**, persisted + backup). When on + actively playing (`isPlaying` / rate > 0) → `UIApplication.shared.isIdleTimerDisabled = true`; pause/stop/no episode/toggle off → `false`. Idle timer only — does **not** override Low Power Mode beyond that; no brightness hacks; PiP / background audio unchanged |
| Chapters | 4 | done | PSC inline (`psc:chapter`) + Podcast Index URL/JSON; **media-file tags (beta)**: local download / folder feed via AVFoundation QuickTime/MP4 chapter tracks (`loadChapterMetadataGroups`); prefer feed chapters wholesale when present, else media. Full player list, tap seek, current highlight; hidden when none. **ID3 CHAP / Vorbis not read** — AVFoundation does not expose them reliably on iOS (no third-party ID3 parser) |
| Transcripts | 2 | done | Feed `podcast:transcript` URL+type (JSON>VTT>SRT preference); full player button → fetch + scrollable sheet; tap cue seek when timed; session memory/disk cache; **only when feed provides URL — no Whisper/on-device STT** |
| Headset / Bluetooth pause | 4 | done | AVAudioSession interruption (pause / resume if shouldResume) + routeChange oldDeviceUnavailable (unplug); remotes/Now Playing unchanged |
| Prefer stream vs download | 5 | done | Settings: Prefer download / Prefer stream / Automatic (default); `PlaybackService.play` resolves via `DownloadService.localURL`; mini + full player show Local/Stream |
| Video → audio-only | 1 | done | **Beta lite**: Settings + full-player toggle **Play video as audio only** (`AppSettings.playVideoAsAudioOnly`, default off, persisted + backup); hides video surface → artwork. Same AVPlayer item (no track swap). Lockscreen / Now Playing unchanged (audio) |

## Downloads

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Manual download / delete | 5 | done | Documents/downloads + JSON catalog (`downloads.json`); Feed detail toolbar **Download all** (confirm with count; unplayed + not archived + not downloaded; newest first soft cap 50; `DownloadService.downloadAllManual` / manual Wi‑Fi gate); Downloads tab **Delete played downloads** (played only; skips favorites; per-file `delete`) |
| Offline Wiedergabe | 5 | done | Play from local file; catalog restored on launch |
| Speicherverwaltung / Cache-Limit | 5 | done | UserDefaults byte budget (unlimited / 1 / 5 / 10 GB / custom MB); usage in Settings; eviction: played oldest-mtime first then unplayed LRU; after DL + Settings open + launch; Clear downloads |
| Auto-download (global + Regeln) | 4 | done | Global toggle + per-feed cap (1/2/3/5) + per-feed Use global/Always/Never; enqueue after refresh via DownloadService; Wi‑Fi-only via NWPathMonitor; storage eviction unchanged. Full Android-style filter rules → KMP later |
| Per-feed auto-download | 4 | done | Use global / Always / Never on feed settings sheet; Always enqueues even when global off; Never skips; cap + Wi‑Fi-only still global |
| Auto-delete after play | 4 | done | Global Settings toggle (default off); on mark played (manual or playback finished / continuous auto-next) deletes local file via DownloadService; keeps episode row + played status; defers while that local file is still the active player item; **skips favorited / starred** episodes |
| Mobile/Wi‑Fi Policy | 4 | done | Settings → Network / Downloads: `autoDownloadWifiOnly` (default on), `manualDownloadWifiOnly` (default off; refuse + error on cellular), `streamWifiOnly` (default off; PlaybackService refuses stream URLs on cellular, local OK + alert); shared `NWPathMonitor` (`NetworkPathGate`) |
| Background downloads | 5 | done | `URLSessionConfiguration.background`; AppDelegate `handleEventsForBackgroundURLSession`; task↔episode in `pending-downloads.json` |
| Download log / errors | 3 | done | Ring buffer (~50) in Application Support `download-errors.json` (episode id/title, feed, message, timestamp); `lastError` banner on Downloads + Download errors list (toolbar / Settings); Clear errors |

## Discovery

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Add by RSS URL | 5 | done | Add sheet **Feed URL** tab: paste RSS/Atom URL → **Preview feed** → Confirm Subscribe (same online Preview as discovery); already subscribed → Open feed |
| Apple Podcasts / iTunes Search | 4 | done | Native URLSession; Add sheet Search tab; debounced; feedUrl → subscribe |
| Podcast Index | 4 | done | User-supplied API key+secret (Keychain); Settings → Discovery; Add sheet tab; auth sha1; Subscribe via feed URL; honest empty state if keys missing |
| fyyd | 3 | done | Public fyyd.de API (`/0.2/search/podcast?term=`); no API key; Add sheet tab; debounced; Preview → Confirm Subscribe via feed URL; honest empty/error states |
| Top lists / Quick discovery | 4 | done | Apple iTunes RSS charts (`/{country}/rss/toppodcasts/limit=25/json`); country Settings (auto→locale/`de`); Home preview + Subscriptions → Discover; batch lookup → feedUrl; Subscribe via existing pipeline; pull-to-refresh |
| Online feed preview | 4 | done | Preview screen before subscribe (discovery + Feed URL): FeedRepository fetch+parse; title/author/artwork hints; episode count + first 10 titles; Confirm Subscribe / Cancel; already subscribed → Open feed |

## Sync & Import

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| gpodder.net sync | 4 | done | **P1 MVP**: Settings → Sync; provider gpodder.net; Keychain password; device id+name; login/logout/sync now; URLSession API2 auth + device + subscription get/upload; pull missing feeds + push local URLs; **additive merge** (remote removes do not wipe local); episode actions stub/not synced |
| Nextcloud Gpodder sync | 4 | done | **P1 MVP**: same Settings Sync section; provider Nextcloud; base URL (server root or `…/index.php/apps/gpoddersync/`); reuses Keychain + Login/Sync; client composes Nextcloud paths (`subscriptions`, `subscription_change/create`); login probes GET subscriptions (no device API); **additive** subscriptions only — episode actions not synced |
| AntennaPod DB backup import/export | 3 | done | **iOS JSON backup** (not Android DB): Settings → Backup export/import ZIP of Application Support maps (feeds/queue/playback/downloads catalog/favorites/archived/feed-settings/tags/download-errors/local-folder-bookmarks) + app-settings + gpodder prefs; **no Keychain secrets**; optional **Include downloaded episode files** (default off) packs Documents/downloads into ZIP `downloads/` with size/time warning — import merges media (overwrite same names, no folder wipe) then prunes catalog; HTML export separate (Import / Export) |
| HTML export | 2 | done | Settings → Import / Export → **Export subscriptions as HTML**; self-contained list (title, feed URL link, episode count); share sheet `.html`; AntennaPod-style lite; distinct from OPML + JSON backup |
| Wear OS companion | 1 | n/a | Android; iOS → Apple Watch companion (Extras) |

## Settings (P0-Subset zuerst)

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Theme light/dark/auto | 5 | done | UserDefaults; `preferredColorScheme` system/light/dark |
| Default playback speed | 5 | done | UserDefaults; applied on fresh episode start (per-feed override when set); mini-player marks Default |
| Prefer stream vs download | 5 | done | UserDefaults; Prefer download / Prefer stream / Automatic; honored in `PlaybackService.play` |
| Auto-delete after play | 4 | done | UserDefaults; deletes download file after mark played; defers while local file is active player item; skips favorites |
| FF/Rewind seconds | 4 | done | UserDefaults `rewindSeconds` / `fastForwardSeconds`; presets 5–60; wired to players + MPRemoteCommandCenter |
| Skip intro / Skip outro | 3 | done | UserDefaults `skipIntroSeconds` / `skipOutroSeconds`; presets 0/5/10/15/30/60 (0=off); PlaybackService seeks intro on fresh start; outro once/session → finished + queue next; per-feed override via `feed-settings.json` (nil=Use global) |
| Refresh interval | 4 | done | UserDefaults presets: manual / 1h / 4h / 12h / 24h; due-check on launch + foreground → `refreshAllFeeds()`; BGAppRefreshTask stubbed (no `fetch` in Info.plist) |
| Swipe actions | 3 | done | Queue: Remove + Archive (+ Edit drag reorder when not filtering; toolbar **Clear queue** confirm). Downloads: Delete. Inbox: Archive + Mark played + **Play Next** + **Add to queue** (+ toolbar Mark all as played / Archive all). Feed: Archive/Restore + **Play Next** + Queue + Share (+ toolbar **Download all** / **Mark all as played**). History: Remove + Mark unplayed (+ `.searchable` title/feed; toolbar **Clear history** confirm, full list). Favorites: Unfavorite + Archive (+ `.searchable` title/feed; toolbar **Clear favorites** confirm, full list). Archived: Restore (+ `.searchable` title/feed; toolbar **Restore all** confirm, full list). All Episodes: Archive/Restore + Mark played. EpisodeRow: play/download/queue(append)/favorite/share + context **Play Next**; full player Play Next + Queue |
| Parental controls | 2 | done | **MVP**: Settings → Parental controls; 4–6 digit PIN in Keychain; lock Add/Discover; optional lock Network/Downloads toggles; optional hide explicit iTunes charts (`explicit=false`); session unlock until background (`scenePhase`); disable clears PIN |
| Notifications (new episodes) | 4 | done | Local UserNotifications after feed refresh; Settings toggle (default on; honest if denied); per-feed Always/Never override; permission from Settings or first new-eps refresh; tap → Inbox; no push |
| Notifications (DL/Sync errors) | 4 | done | **Local only, no push.** DL: Settings “Notify on download errors” (default on); banner on failure (episode title + short error); tap → Downloads. Sync: Settings “Notify on sync errors” (default on; same UNUserNotificationCenter permission); gpodder/Nextcloud login or sync failure → local banner (short error); tap → Settings Sync |
| About / contribute links | 2 | done | Settings → About: AntennaPod iOS fork blurb; version from Bundle (placeholder fallback); Links → antennapod.org, GitHub AntennaPod, contribute, docs, this fork (`Exellent1988/AntennaPod-ios`) via Safari `Link` |

## Extras

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Statistics | 2 | done | Same as Navigation: derived from playback progress |
| Echo (Year in Review) | 2 | done | **Beta lite**: current calendar year (device calendar); played count via `lastPlayedAt`; approx listening time + top podcasts from `playback.json`; favorites this year from `favorites.json`; Library + Settings; empty state; ShareLink text; same approximation limits as Statistics |
| Homescreen Widget | 1 | done | **Beta lite**: WidgetKit Continue listening (episode title + feed) from App Group `UserDefaults` snapshot written on playback/queue/progress changes; tap → `antennapod://play` (`PlaybackDeepLinkRouter`); empty: “Open AntennaPod to continue”. Snapshot may be stale; no live scrubber; needs App Group entitlement + signing for device. XcodeGen target `AntennaPodWidget`. **Localization:** per-target `AntennaPodWidget/Localizable.xcstrings` (en+de; not shared with main app) |
| CarPlay | 1 | partial | **Honest**: system Now Playing / remotes (`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` play/pause/toggle/skip±/seek + next/prev→skip; `AVAudioSession` `.playback`; `UIBackgroundModes` audio). **No** custom CarPlay scene / `CPTemplate` / CarPlay audio entitlement / `UIBrowsableContent` |
| Siri Shortcuts | 1 | done | **Lite**: App Intents + AppShortcutsProvider (Play/Pause, Skip forward/back) open app; URL schemes `antennapod://play|pause|toggle|skip-forward|skip-back` handled in-app via PlaybackService. Not background-only / no App Group shared store; needs current episode loaded |
| Apple Watch companion | 1 | done | **Beta lite**: XcodeGen `AntennaPodWatch` (watchOS 10+ single-target); Continue listening title/feed from same snapshot as Homescreen Widget (`group.de.danoeh.antennapod.ios` + WC `applicationContext` push — App Group alone is per-device); Play → companion iPhone via Watch Connectivity message / `transferUserInfo` + best-effort `openSystemURL(antennapod://play)` → `PlaybackDeepLinkRouter`; empty state when no snapshot. **Honest limits:** no independent Watch playback, no download management, no full queue; transport when already playing via system Now Playing on Watch. Needs Dev Team + App Group on Mac for device. **Localization:** per-target `AntennaPodWatch/Localizable.xcstrings` (en+de; not shared with main app) |
| Accessibility / VoiceOver | 1 | done | **Beta polish**: EpisodeRow combined accessibilityLabel (title, feed, played/progress, downloaded + favorite/archived) + traits; Play/Download/Queue/Star/Archive/Share button labels (String Catalog where present); mini + full player labels for play/pause, skip, speed, sleep, scrubber (value/hint); main tab Labels via Localizable.xcstrings; Settings toggles unchanged with helpful accessibilityHint where useful |
| Localization DE | 1 | done | **Partial (expanded)**: Main app String Catalog en+de (`AntennaPod/Localizable.xcstrings`); prior tabs/nav/Settings/Discovery/library/notifications/Chapters/Transcript/parental/Statistics/Echo **plus** Homescreen Widget + Apple Watch companion UI via **per-target** catalogs (`AntennaPodWidget/Localizable.xcstrings`, `AntennaPodWatch/Localizable.xcstrings` — duplicated minimal keys; not sharing main catalog to avoid App Group / multi-target fragility). Development language en. **Still English:** OS/`localizedDescription` network errors, some secondary a11y hints, preview sample data |
| Chromecast | 1 | n/a | AirPlay statt Cast |
| Rating prompt | 1 | done | **Optional**: after 10 successful mark-played (manual or finish), once per install `AppStore.requestReview(in:)`; Settings toggle default on + Reset for testing; honest that iOS may suppress sheet / system limits |

## KMP vs. native (Kurz)

| In KMP (Shared) | Native iOS |
|-----------------|------------|
| Domain models, Feed-Parser, OPML (later) | SwiftUI, AVFoundation; OPML native for beta |
| Geschäftsregeln (Filter, Queue, Auto-DL-Kandidaten) | URLSession Downloads, BGTasks |
| Discovery- & Sync-Protokoll-Clients | GRDB/SQLite Persistenz |
| Schema-/Verhaltens-Specs | UNUserNotificationCenter, WidgetKit |
