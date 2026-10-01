# ios/ — AntennaPod for iOS

Fork-only SwiftUI shell. Playback via AVFoundation; networking/downloads via URLSession; persistence in-memory for now (SQLite later). Shared KMP parser is validated in `shared/kmp`; the iOS app currently uses a Foundation `XMLParser` fallback with the same golden fixtures in mind. Wiring the XCFramework into the app is the next integration step.

## Status (Phase 1 skeleton)

- Subscribe by feed URL
- Apple Podcasts / iTunes Search discovery (Add sheet; debounced; Subscribe via feed URL)
- Podcast Index discovery (Add sheet tab; user-supplied API key+secret in Keychain; Settings → Discovery; debounced; Subscribe via feed URL)
- fyyd discovery (Add sheet tab; public fyyd.de search API, no key; debounced; Preview → Subscribe via feed URL)
- Top lists / Quick discovery (Apple iTunes RSS charts; Home preview + Subscriptions → Discover; country in Settings; pull-to-refresh; Subscribe via feed URL)
- Online feed preview (before subscribe: discovery rows + Feed URL → Preview via FeedRepository; episode count + first titles; Confirm Subscribe / Cancel; already subscribed → Open feed)
- Episode list
- Stream playback (AVPlayer, speed, configurable skip intervals)
- Full player sheet (artwork or video surface, scrubber, transport; tap mini player to open)
- Video player (beta lite; MIME video/* or mp4/m4v/mov/webm → AVPlayerLayer in full player; PiP beta lite)
- Video → audio only (Settings + full-player toggle; default off; Lockscreen stays audio)
- Volume adaptation (Settings; default off; iOS AVAudioSession spokenAudio / speech optimize — not Android loudness gain)
- Skip silence (Settings toggle only; not applied on stock AVPlayer — needs custom audio graph)
- Keep screen on while playing (Settings; default off; `isIdleTimerDisabled` only — no Low Power Mode override / brightness; PiP/background audio unchanged)
- Chapters (PSC / Podcast Index from feed + media-file QuickTime/MP4 tags on local files; list in full player; tap to seek)
- Transcripts (beta; feed `podcast:transcript` URL only — fetch VTT/SRT/JSON, scrollable sheet, tap cue seek; no Whisper/STT)
- Lockscreen / Now Playing (title, podcast, artwork, remote play/pause/skip/seek using Settings intervals)
- CarPlay (honest partial: system Now Playing / remotes + background audio; **no** custom CPTemplate / CarPlay entitlement)
- Headset / Bluetooth pause (AVAudioSession interruption + headphone unplug; remotes unchanged)
- Sleep timer (clock presets + end of episode, fade-out)
- Offline download to Documents/downloads (background URLSession; survives suspend/relaunch; Feed detail **Download all** for unplayed/not-archived/not-downloaded, newest 50 soft cap)
- Queue tab (JSON; swipe Remove + Archive; Edit drag reorder; `.searchable` title/feed filter with debounce; reorder disabled while filtering; toolbar Clear queue with confirm)
- Home tab (configurable sections: Continue, Inbox, Queue, Discover, Recently updated, Favorites optional; Settings → Home layout; pull-to-refresh)
- German localization (beta; String Catalog `Localizable.xcstrings` en+de; tabs/nav, Settings headers + footnotes/help captions, parental detail, Statistics + Echo, Discovery chrome, library empty states, download errors, Sync labels, notification titles, Chapters/Transcript — **partial**, not full i18n)
- Accessibility / VoiceOver (beta polish; EpisodeRow combined labels + action button labels; mini/full player transport; tab Labels; Settings toggle hints — not a full audit)
- Inbox tab (unplayed, non-archived across subscriptions; pull-to-refresh; swipe Archive + Mark played + Play Next + Add to queue; toolbar menu Archive all + Mark all as played with confirm)
- History (played / in-progress; Subscriptions → Library → History; newest last-played first; toolbar Clear history with confirm)
- Statistics (beta; Subscriptions → Library → Statistics + Settings; totals + top podcasts from `playback.json`; approx time)
- Echo / Year in Review (beta lite; Library + Settings; current calendar year from playback/favorites; ShareLink text)
- About / contribute links (Settings → About; fork blurb; Bundle version; antennapod.org / GitHub / contribute / docs / this fork)
- Rating prompt (optional; after 10 mark-played, once per install `AppStore.requestReview`; Settings toggle default on + Reset; iOS may suppress)
- Siri Shortcuts lite (App Intents Play/Pause / Skip forward/back + `antennapod://` URL schemes; opens app; needs current episode)
- Homescreen widget (beta lite; WidgetKit Continue listening from App Group snapshot; tap → `antennapod://play`; empty placeholder; may be stale / no scrubber)
- Apple Watch companion (beta lite; watchOS Continue listening from same snapshot via WC push; Play → iPhone `antennapod://play`; empty state; no independent playback / downloads / queue)
- Swipe actions (Queue Remove+Archive + drag reorder + Clear queue confirm; Downloads Delete; Inbox Archive+Mark played+Play Next+Add to queue; Feed/History(+ Clear history confirm)/Favorites(+ Clear favorites confirm)/Archived/All Episodes useful swipes)
- Favorites / starred episodes (Subscriptions → Library → Favorites; optional Home preview via Home layout; star on EpisodeRow + full player; `favorites.json`; swipe Unfavorite + Archive; toolbar Clear favorites with confirm; auto-delete skips favorites)
- Archive / restore episodes (side map `archived.json`; hide from Inbox / Home New; feed lists keep with dim/badge; EpisodeRow + Feed/Inbox/Queue/Favorites/All Episodes swipe; Library → Archived; bulk Archive all + Mark all as played in Inbox)
- Episodes / All episodes (Subscriptions → Library → Episodes; all feeds, newest pubDate first; soft cap 500 then All/Unplayed/Downloaded chips + searchable title/feed; EpisodeRow actions; swipe Archive + Mark played; filter persisted in AppSettings)
- Share podcast / episode (FeedDetail toolbar share feed URL; EpisodeRow ShareLink / context menu / FeedDetail swipe; full player; prefer page link else enclosure)
- Library search (local subscriptions/episodes; Inbox searchable + Subscriptions filter; not iTunes)
- Playback progress save / resume (`lastPlayedAt` for History)
- Mark played / unplayed (manual + smart-mark 30s; Inbox + Feed detail Mark all as played with confirm)
- Settings tab (theme light/dark/system, **Home layout** (show/hide + reorder), default playback speed, rewind/FF intervals, skip intro/outro, volume adaptation, skip silence preference, Keep screen on, Continuous playback, playback source, play video as audio only, feed refresh interval, **new-episode action** (Inbox / Queue / Queue+download), auto-download, Network / Downloads Wi‑Fi policy, auto-delete after play, notify on new episodes / download errors / sync errors, Discovery charts country + Podcast Index API keys, gpodder.net / Nextcloud Gpodder sync, **Parental controls** (PIN / Keychain), **Backup** (iOS JSON), Import / Export (OPML + HTML), Statistics / Echo links, App Store rating prompt, Siri/Shortcuts note, Homescreen widget note, Apple Watch note, CarPlay note, About)
- Prefer stream vs download (Prefer download / Prefer stream / Automatic; honored on play)
- Continuous playback (Settings toggle, default on; auto-next from Queue when an episode ends; off = stop without advance)
- Feed refresh / Keep updated (global interval; auto on launch & foreground when due)
- New-episode action (Inbox only / Add to Queue / Add to Queue and download; per-feed Use global / Inbox / Queue; after refresh newcomers only)
- Auto-download (global on/off + episodes-per-feed cap; after refresh; Wi‑Fi only under Network / Downloads; per-feed Use global / Always / Never)
- Mobile / Wi‑Fi policy (auto / manual download / stream Wi‑Fi-only toggles; shared NWPathMonitor)
- Per-feed settings (Feed detail → gear: Auto-download, Keep updated, New episodes, Notify, Skip intro/outro, Playback speed overrides)
- Tags / Folders for subscriptions (side map `feed-tags.json`; manage on per-feed settings; Subscriptions filter chips + optional group-by-tag; untagged)
- Subscriptions list sort (toolbar: Recently updated default / Alphabetical A–Z; `subscriptionsSort` pref + backup; client-side only, no drag-reorder)
- Feed episode list sort (Feed detail toolbar: Newest first default / Oldest first by `pubDateEpochMs`; global `feedEpisodeSort` + backup; Inbox/All Episodes unchanged)
- Local folder feeds (beta; Add podcast → Folder via fileImporter; security-scoped bookmark; synthetic feed from mp3/m4a/aac/wav/flac; refresh re-scans; no RSS/network; Folder badge; unsubscribe releases bookmark)
- OPML import/export (Settings + Subscriptions; share sheet / file picker; batch subscribe)
- HTML subscription export (Settings + Subscriptions Import / Export; share sheet `.html`)
- Local data backup import/export (Settings → Backup; iOS JSON ZIP of Application Support maps + Settings + gpodder prefs; optional Include downloaded episode files → ZIP `downloads/`; no Keychain secrets; not Android DB)
- HTML export (Settings → Import / Export → Export subscriptions as HTML; self-contained list with title, feed URL links, episode count; share sheet; distinct from OPML + JSON backup)
- Download storage limit (Settings: usage + max size; auto-evict played first)
- Auto-delete after playing (global toggle; deletes offline file on mark played; keeps episode row)
- Notifications for new episodes (local UserNotifications after refresh; Settings toggle; tap opens Inbox; no push)
- Downloads tab search (`.searchable`; filter by episode title and/or feed title; light debounce; empty query = all; empty state when no matches)
- Queue tab search (`.searchable`; filter by episode title and/or feed title; light debounce; empty query = all; empty state when no matches; **Edit/drag reorder disabled while filtering** — filtered indices would not map to full queue; Clear queue still clears full queue)
- Download log / errors (ring buffer in Application Support; Downloads banner + errors list; Clear errors)
- Notify on download / sync errors (local UserNotifications; Settings toggles default on; DL tap → Downloads; Sync tap → Settings Sync; no push)
- Parental controls (beta; Settings → Parental controls; 4–6 digit PIN in Keychain; lock Add/Discover; optional Network/Downloads lock + hide explicit charts; session unlock until background)
- gpodder.net / Nextcloud Gpodder sync (subscriptions MVP: provider picker; Keychain; pull+push feed URLs; additive merge; episode actions later)

Root tabs (6): **Home**, Inbox, Subscriptions, Queue, Downloads, Settings.

## Layout

```
ios/
├── README.md
├── project.yml              # XcodeGen (app + AntennaPodWidget + AntennaPodWatch)
├── Shared/                  # App Group Continue-listening snapshot (app + widget + watch keys)
├── AntennaPodWidget/        # WidgetKit extension (Continue listening)
├── AntennaPodWatch/         # watchOS companion (Continue listening + Play on iPhone)
└── AntennaPod/
    ├── AntennaPodApp.swift
    ├── AntennaPod.entitlements   # App Group
    ├── App/RootTabView.swift
    ├── Data/…               # store, repository, playback, download, parsers, WatchCompanionBridge
    └── Features/…           # home (+ charts preview), inbox, all episodes, history, statistics, echo, favorites, archived, library search, subscriptions (+ Discover charts), feed detail + per-feed settings (+ tags), add/discover (+ feed preview + local folder), top lists, player (+ transcripts sheet), downloads (+ searchable + error log), queue (+ searchable; reorder off while filtering), settings (+ Home layout + gpodder/Nextcloud sync + charts country + Parental controls + Backup + Statistics + Echo + App Store rating + Siri note + Homescreen widget note + Apple Watch note + CarPlay note + About), queue swipes/reorder, OPML, HTML export, data backup, notifications (new eps + DL errors)
```

## Local setup (Mac)

```bash
brew install xcodegen
./gradlew -p shared/kmp linkDebugFrameworkIosSimulatorArm64   # optional until linked
cd ios && xcodegen generate
open AntennaPod.xcodeproj
```

**Homescreen widget:** XcodeGen creates `AntennaPod` + embedded `AntennaPodWidget`. Select a Development Team, ensure App Group `group.de.danoeh.antennapod.ios` is enabled for **both** targets (entitlements files are already listed), build/run on a device or simulator, then add **Continue listening** from the iOS home-screen widget gallery. Without a signing team / App Group capability on the Apple developer portal, the extension may fail to install — shared snapshot code still builds into the app.

**Apple Watch companion:** XcodeGen also creates embedded `AntennaPodWatch` (watchOS 10+ single-target app, bundle `de.danoeh.antennapod.ios.watchkitapp`). Select the **same Development Team** on the Watch target, enable App Group `group.de.danoeh.antennapod.ios` for the Watch app on the Apple developer portal / Xcode Signing, then build/run the iOS app onto a phone paired with a Watch (or Watch simulator). The Watch UI shows Continue listening from the phone-pushed snapshot; **Play on iPhone** remotes playback via Watch Connectivity (and best-effort `antennapod://play`). Without signing / App Group, the Watch target may not install — Shared snapshot types + `project.yml` stub remain for Mac builds.

See `docs/ios/PLAN.md`, `docs/ios/FEATURE-MATRIX.md`, and `docs/ios/BETA-TESTING.md` (manual beta checklist).

## Persistence

Subscriptions, queue, per-feed settings (`feed-settings.json`), subscription tags (`feed-tags.json`), starred episode ids (`favorites.json`), archived episode ids (`archived.json`), and per-episode playback state (`positionSeconds`, `durationSeconds`, `isPlayed`, `lastPlayedAtEpochMs`) are stored as JSON under Application Support (`PodcastPersistence`: `feeds.json`, `queue.json`, `feed-settings.json`, `feed-tags.json`, `favorites.json`, `archived.json`, `playback.json`). Inbox is derived from that state (unplayed, non-archived episodes across feeds, newest first). Archived episodes stay on feed lists (dimmed/badge) and in Library → Archived. All Episodes is the same cross-feed catalog without the unplayed filter (newest pubDate first, soft-capped at 500). History lists played or in-progress episodes (newest `lastPlayedAt` first); swipe removes playback state or marks unplayed; toolbar Clear history bulk-removes the same playback entries (confirm). Older `playback.json` without `lastPlayedAt` migrates from `updatedAt` when played/in-progress. Playback resumes from the saved position; episodes are auto-marked played within the last 30 seconds (AntennaPod `smartMarkAsPlayed` default) or when playback ends. Theme, default playback speed, rewind/fast-forward intervals, skip intro/outro seconds, volume adaptation, skip silence preference, Keep screen on, Continuous playback, playback source preference, feed refresh interval, new-episode action, auto-download, Network / Downloads Wi‑Fi policy (`autoDownloadWifiOnly` / `manualDownloadWifiOnly` / `streamWifiOnly`), auto-delete-after-playing, notify-on-new-episodes / notify-on-download-errors, subscriptions list sort (`subscriptionsSort`), feed episode list sort (`feedEpisodeSort`), and All Episodes filter (`allEpisodesFilter`) prefs live in `UserDefaults` (`AppSettings`) and apply via `preferredColorScheme` / fresh episode starts / mini+full+Now Playing skip / `PlaybackService.play` source resolution / launch+foreground due-check / post-refresh enqueue / mark-played download cleanup. Downloads are files under Documents/downloads with a JSON catalog (`downloads.json`), in-flight background task↔episode map (`pending-downloads.json`), and a recent download-error ring buffer (`download-errors.json`, ~50 entries: episode id/title, feed, message, timestamp). Background transfers use `URLSessionConfiguration.background(withIdentifier:)` plus `AppDelegate.handleEventsForBackgroundURLSession`. Download storage limit lives in `UserDefaults` (`AppSettings.downloadStorageLimit`); `DownloadService` measures Documents/downloads usage, enforces the budget after each successful download (and on Settings open / app launch) by deleting **played** episodes first (oldest file mtime), then unplayed (LRU). Settings also offers **Clear downloads** with confirmation. GRDB/SQLite aligned with AntennaPod schema comes later.

**Data backup (beta):** Settings → **Backup** exports a ZIP of those Application Support JSON files plus `app-settings.json` and `gpodder-prefs.json` (STORE ZIP via `MinimalZip`). **Not** AntennaPod Android DB. Toggle **Include downloaded episode files** (default **off** — keeps ZIP small) optionally packs Documents/downloads into ZIP folder `downloads/` (size/time confirmation when files exist). **Keychain secrets omitted** (gpodder password, Podcast Index API key/secret, Parental controls PIN). Import warns before replace, writes JSON + merges media files (overwrite same names; does not wipe unrelated local downloads), reloads `PodcastStore` / `DownloadService` / Settings / gpodder prefs. `pending-downloads.json` is cleared on import. **HTML export** is separate under Import / Export (not in the ZIP).




## Parental controls

Beta MVP under Settings → **Parental controls**:

- **Enable** prompts for a 4–6 digit PIN (confirm); stored in Keychain only (not UserDefaults / not backup ZIP).
- **Options:** Lock Add / Discover (PIN before Add sheet or Discover charts); optional lock Network / Downloads Wi‑Fi toggles; optional hide explicit top charts (`explicit=false` on iTunes RSS while enabled).
- **Session unlock:** correct PIN unlocks until the app backgrounds (`scenePhase` inactive/background), then gated UI asks again.
- **Disable:** requires PIN, then clears Keychain and turns options off.

Not a full device parental lock / Screen Time substitute.

## Home

Primary root tab aggregating existing store data (no new persistence). **Settings → Home layout** configures section **order** and **visibility** (persisted in `AppSettings` / UserDefaults; included in iOS JSON backup).

Available sections:

- **Discover** — Apple iTunes top podcasts preview (charts country from Settings); See all → full charts list with Preview → Confirm Subscribe. When enabled, always shows the charts preview (not empty-hidden).
- **Continue listening** — in-progress episodes (`positionSeconds > 1`, not played), newest `lastPlayedAt` first; rows reuse `EpisodeRow` (resume / download / queue / mark). Hidden when empty.
- **New / Inbox** — preview of unplayed, non-archived episodes (same as Inbox, capped); chevron / See all switches to the Inbox tab. Hidden when empty.
- **Queue** — preview of queued episodes when the queue is non-empty; See all → Queue tab. Hidden when empty.
- **Recently updated** — subscriptions sorted by newest episode `pubDateEpochMs`; tap → `FeedDetailView`; See all → Subscriptions. Hidden when empty.
- **Favorites** (optional) — starred episodes preview; See all → Library Favorites. **Off by default**; enable under Home layout. Hidden when empty.

Default order: Discover → Continue → Inbox → Queue → Recently updated → Favorites (hidden). Home layout supports toggles, Edit/drag reorder, and Reset to defaults. Pull-to-refresh calls `refreshAllFeeds()` (Discover preview reloads on appear / country change). Empty library shows a welcome empty state (and Discover when that section is enabled).


## Localization (German, beta / partial)

Development language remains **English** (`developmentRegion: en`). `ios/project.yml` `knownRegions` includes `en`, `de`, and `Base`. User-visible copy lives in **`ios/AntennaPod/Localizable.xcstrings`** (String Catalog; en source + de).

SwiftUI `Text` / `Label` / `Button` / `navigationTitle` / `Section` / `Toggle` string literals resolve via `LocalizedStringKey`. Plain `String` surfaces that need a lookup use `String(localized:)` (e.g. Settings/Backup/Parental help captions, `HomeSectionId.label`, Add-mode / discovery ternaries, notification titles, charts help format string, Parental PIN Save/Unlock defaults).

**Covered (partial):**

- Tab bar + main navigation titles: Home, Inbox, Subscriptions, Queue, Downloads, Settings (+ About, Favorites, History, Archived, Episodes, Discover, Download errors, Home layout, Add podcast, Transcript)
- Settings section headers: Appearance, Home, Playback, Library, Privacy, About, Backup, Sync, Feeds / Keep updated, Auto-download, Network / Downloads, Notifications, Downloads / Storage, Discovery, App Store, Siri / Shortcuts, Homescreen widget, Apple Watch, CarPlay, Import / Export
- Discovery chrome: Add segmented modes (Apple / Index / fyyd / URL / Folder), search placeholders, empty/API-key states, Results / Feed URL / charts loading + help, OPML import/export labels, Preview/Open row actions
- Primary actions: Play, Pause, Resume, Download, Download all, Subscribe / Confirm Subscribe, Cancel, Save, Delete, Remove, Archive, Mark played / unplayed, Mark all as played, Sort / Alphabetical A–Z / Newest first / Oldest first, common empty-state titles + main-tab and library empty descriptions (History / Favorites / Archived / Episodes / Tags filters)
- Home section labels (layout toggles + Home headers): Continue listening, New / Inbox, Queue, Discover, Recently updated, Favorites
- Backup / Sync: section labels, primary Backup buttons, Sync form field labels (Host / Username / Password / Device / Login / Sync now), notification toggles
- Download errors: banner title, Errors list title/empty, clear confirmation
- Full player: Chapters / Transcript sheet titles + loading / unavailable copy
- Local notifications: Download failed, Sync failed, “N new episodes”
- Settings footnotes / help captions: Playback (speed, skip, video-as-audio, volume adaptation, skip silence, keep screen on, continuous playback, playback source), Feeds / Keep updated, Auto-download, Network / Downloads, Notifications, Downloads / Storage, Discovery, Sync provider blurbs, Backup help + media captions, Home layout footer, App Store rating / Siri / Widget / Watch / CarPlay notes
- Parental controls detail: enable/options help, PIN sheet copy, lock status, common PIN errors
- Statistics + Echo (Year in Review): navigation titles (already), empty states, totals/year section headers, row labels (played / in progress / listening time / favorites), top-podcasts footers, approximation footnotes, duration units (`%lldh %lldm` / Min. / s), feed subtitles, Echo ShareLink text

**Still English (honest):** Widget / Watch UI (separate targets — no shared String Catalog; leave English to avoid App Group build breakage), OS/`localizedDescription` network errors, and many secondary accessibility hints. Regenerating XcodeGen on a Mac picks up the catalog + regions; device/simulator language German shows translated keys when present.

## Accessibility (VoiceOver, beta polish)

VoiceOver-oriented polish on the existing beta UI (not a full accessibility audit / Dynamic Type pass):

- **EpisodeRow** — combined `accessibilityLabel` (title, feed, played / percent progress, downloaded, favorite, archived) with `.isStaticText`; icon-only Play / Download / Queue / Mark played / Favorite / Archive / Share buttons get explicit localized labels (+ `.startsMediaSession` on Play).
- **Mini + full player** — play/pause, rewind/forward (interval seconds), speed menu, sleep timer, and scrubber / progress (value + hint). Secondary full-player actions labeled like EpisodeRow.
- **Main tabs** — VoiceOver names from `Label` titles in `RootTabView` (String Catalog en+de).
- **Settings toggles** — bindings unchanged; short `accessibilityHint` on playback / network / notification / storage / rating toggles where the on-screen caption is long.

Honest limits: not every screen/control audited; no custom rotor / reduce-motion work in this pass.

## Queue

**Queue** tab lists enqueued episodes (JSON under Application Support). Swipe trailing **Remove**, leading **Archive**. **Edit** enables drag reorder via `PodcastStore.moveQueue(from:to:)` (persists with `queue.json`). **Search** (`.searchable`, ~250 ms debounce) filters by episode title and/or feed title; empty query shows the full queue; empty state when nothing matches. **Honest:** while a filter is active, **Edit is disabled and drag reorder is off** — `onMove` indices would refer to the filtered list, not the persisted queue order. **Clear queue** still confirms and clears the **full** queue (count in the dialog is always `store.queue.count`); the action stays enabled whenever the queue is non-empty, even if the current filter shows no rows. With Settings **Continuous playback** on (default), finishing an episode advances with `nextQueueEpisode`; when off, playback stops without queue advance (progress / mark played still apply).

**Add to Queue** (`PodcastStore.enqueue`) appends if absent. **Play Next** (`PodcastStore.playNext(_:currentlyPlayingId:)`) moves/inserts immediately after the currently playing queue item, or at the **head** when nothing is playing / the current episode is not in the queue — so auto-next after finish still hits that head item (honest: same as today’s append semantics when current is not queued). Entry points: EpisodeRow context menu, Feed detail swipe, Inbox swipe, full player (alongside Queue).

## Library search

Local-only search over subscribed feeds and their episodes (title, feed title, feed description) — distinct from Apple Podcasts / iTunes discovery in Add podcast. **Inbox** uses `.searchable` with a short debounce (~250 ms): empty query keeps the unplayed Inbox; non-empty shows Podcasts + Episodes sections. Matching feeds navigate to `FeedDetailView`; episodes reuse `EpisodeRow` (play / download / queue / mark played). **Subscriptions** also filters the feed list via searchable. **Downloads** and **Queue** filter by episode title or feed title (same light debounce; empty query shows all). Queue disables Edit/reorder while filtering. Empty states when nothing matches.

## History

**Subscriptions → Library → History** (no extra root tab). Lists episodes that are marked played or have progress (`positionSeconds > 1`), sorted by `lastPlayedAtEpochMs` descending. Rows show feed title and a relative last-played date; tap actions reuse `EpisodeRow` (play / download / queue / mark played / favorite). Swipe trailing **Remove** clears that episode’s playback state (leaves the feed row). Swipe leading **Mark unplayed** when played (episode drops out of History if there is no remaining progress). Toolbar menu **Clear history** confirms with the current count, then `clearHistory()` drops the whole `playbackStates` entry for every listed episode — same honesty as per-row Remove (progress + `isPlayed` + `lastPlayedAt` gone; feed rows, downloads, queue, and favorites stay). Disabled when empty. Root tabs stay at six (Home first).

## Statistics

**Subscriptions → Library → Statistics** (also **Settings → Library → Statistics**). Derived from existing `playback.json` — no separate cumulative `listenedSeconds` counter in this beta.

- **Played episodes** — count of episodes with `isPlayed`.
- **In progress** — episodes with progress (`positionSeconds > 1`) that are not marked played (shown when non-zero).
- **Approx. listening time** — sum of estimates: **played** use saved `durationSeconds` (position is cleared on mark-played); **in-progress** use `positionSeconds`. Footnote on screen: does **not** count rewinds, speed, or re-listens.
- **Top podcasts** — per-feed rollup sorted by approximate time, then play count.

Empty state when there is no played / in-progress playback data.

## Echo (Year in Review)

**Subscriptions → Library → Echo** (also **Settings → Library → Echo**). Beta lite year summary for the **current calendar year** (device `Calendar.current` — Europe/Berlin when the device is set that way).

- **Played episodes** — `isPlayed` with `lastPlayedAt` (else `updatedAt`) in this year.
- **Approx. listening time** — same estimate as Statistics (played → saved duration).
- **Top podcasts** — per-feed rollup for that year (up to 10).
- **Favorites** — count starred this year from `favorites.json` (plus total if different).
- **Share** — toolbar `ShareLink` with a plain-text summary when there is data.

Honest empty state when little/no year data. Footnote: approximate — same limits as Statistics (no rewinds / speed / re-listens; derived from `playback.json`).

## About

**Settings → About**. Identifies this build as **AntennaPod iOS** (unofficial SwiftUI fork) with a short local-first blurb. **Version** prefers `CFBundleShortVersionString` / `CFBundleVersion` from the bundle; if unset, shows `0.1.0-beta (placeholder)`. **Links** open in Safari via SwiftUI `Link`: [antennapod.org](https://antennapod.org), [GitHub AntennaPod](https://github.com/AntennaPod/AntennaPod), [Contribute](https://antennapod.org/contribute/), [Documentation](https://antennapod.org/documentation/), and this fork (`https://github.com/Exellent1988/AntennaPod-ios`).

## Rating prompt (optional)

**Settings → App Store**. After **10** successful mark-played events (manual toggle or playback finished / continuous auto-next, only when newly played), the app may call `AppStore.requestReview(in:)` **once per install** from a foreground `UIWindowScene`. Toggle **Ask for App Store rating** defaults **on**; **Reset rating prompt state** clears the count + attempted flag for testing. Honest: **iOS may not show the sheet** (system quotas / frequency limits); we still mark the prompt as attempted so we never spam.

## Siri Shortcuts (lite)

**App Intents** + `AppShortcutsProvider`: Play/Pause, Skip forward, Skip back (plus Play / Pause intents). Phrases registered for Siri / Shortcuts app discoverability. Intents use `openAppWhenRun` and the same path as URL schemes.

**URL schemes** (`Info.plist` `CFBundleURLTypes`): `antennapod://play`, `antennapod://pause`, `antennapod://toggle`, `antennapod://skip-forward`, `antennapod://skip-back` — handled in `AntennaPodApp.onOpenURL` → `PlaybackDeepLinkRouter` → `PlaybackService` (skip uses Settings rewind / fast-forward intervals).

**Limits:** opens the app; controls playback only when a current episode is already loaded. Not a background-only / App Group shared-store control surface — full in-process Shortcuts without UI would need more plumbing.

## Homescreen widget (beta lite)

**WidgetKit** extension (`AntennaPodWidget`) shows **Continue listening**: episode title + feed name from an **App Group** (`group.de.danoeh.antennapod.ios`) `UserDefaults` snapshot.

- **Writer:** main app (`PodcastStore.publishWidgetSnapshot` / `WidgetSnapshotPublisher`) updates the snapshot when playback starts/stops, queue changes, or progress / mark-played changes. Prefers the **current player episode**, else the top Home Continue-listening item.
- **Tap:** `antennapod://play` → `PlaybackDeepLinkRouter` (same as Siri lite).
- **Empty:** “Open AntennaPod to continue”.
- **Honest limits:** snapshot **may be stale** (not live Now Playing); **no scrubber / transport** on the widget; requires App Group entitlement + codesigning for the extension to install; add the widget manually from the home screen.

Shared Codable helpers live in `ios/Shared/WidgetContinueSnapshot.swift` (compiled into app, widget, and Watch targets).

## Apple Watch companion (beta lite)

**watchOS** app target (`AntennaPodWatch`, XcodeGen, watchOS 10+, `WKCompanionAppBundleIdentifier` → `de.danoeh.antennapod.ios`) shows **Continue listening**: episode title + feed name.

- **Snapshot source:** same Codable payload / key as the Homescreen Widget (`group.de.danoeh.antennapod.ios` / `widget.continueListening.snapshot.v1`). Because App Group containers are **per-device**, the iPhone pushes snapshot bytes to the Watch via **Watch Connectivity** `updateApplicationContext` (`WatchCompanionBridge` on save / activate). Watch also tries App Group `UserDefaults` as a local fallback (usually empty).
- **Play / Open on iPhone:** Watch Connectivity `sendMessage` / `transferUserInfo` with action `play` → iPhone `PlaybackDeepLinkRouter` (`antennapod://play`). Best-effort fallback: `WKApplication.openSystemURL(antennapod://play)` (custom schemes are less reliable than WC).
- **Empty:** “Open AntennaPod on iPhone to continue”.
- **Honest limits:** **no** independent Watch audio playback, **no** download management, **no** full queue UI. When the phone is already playing, use **system Now Playing** controls on the Watch. Snapshot may be stale until WC delivers. Requires Dev Team + App Group capability for device install.

## Swipe actions

Consistent list swipes (EpisodeRow icon buttons remain for play / download / queue / mark / favorite / archive / share):

| Screen | Leading | Trailing | Extra |
|--------|---------|----------|-------|
| Queue | Archive | Remove from queue | Edit → drag reorder (`moveQueue`) when not filtering; `.searchable` title/feed; toolbar Clear queue (confirm, full queue) |
| Downloads | — | Delete download | — |
| Inbox | Mark played | Play Next + Add to queue + Archive | Toolbar menu: Mark all as played (confirm) + Archive all |
| Feed detail | Archive / Restore | Play Next + Queue + Share | Toolbar Download all + Mark all as played (confirm) + EpisodeRow context: Play Next + Add to queue |
| History | Mark unplayed (if played) | Remove playback state | Toolbar Clear history (confirm) |
| Favorites | Archive | Unfavorite | Toolbar Clear favorites (confirm) |
| Archived | — | Restore | — |
| All Episodes | Mark played / unplayed | Archive / Restore | — |

## Favorites

**Subscriptions → Library → Favorites** (no extra root tab; optional Home preview via **Settings → Home layout**, off by default). Starred episode IDs live in Application Support `favorites.json` (episode id → `favoritedAtEpochMs`), independent of `playback.json` so clearing History does not unstar. Toggle from **EpisodeRow** (star icon) or the **full player** secondary actions. List is newest-favorited first across feeds; swipe **Unfavorite**. Toolbar menu **Clear favorites** confirms with the current count, then `clearFavorites()` clears the whole `favoriteAtById` side map — same honesty as per-row Unfavorite (downloads, archive, played state, and queue stay; no auto-delete on unfavorite). Disabled when empty. When **Delete episode after playing** is on, auto-delete **skips** favorited episodes (keeps the offline file). Unsubscribing a feed clears that feed’s favorite entries.

## Archive / restore

**Subscriptions → Library → Archived** (no extra root tab). Archived episode IDs live in Application Support `archived.json` (episode id → `archivedAtEpochMs`), independent of played status (`playback.json`). Archive **hides** episodes from **Inbox** and the Home **New / Inbox** preview without marking them played. **Feed** episode lists still show archived items (dimmed + archivebox badge). Toggle from **EpisodeRow** (button + context menu), **Feed detail** leading swipe, **Inbox** trailing swipe, or Inbox toolbar menu **Archive all** / **Mark all as played**. Library → Archived lists newest-archived first; swipe **Restore**. Unsubscribing a feed clears that feed’s archive entries.

## Episodes (All)

**Subscriptions → Library → Episodes** (no extra root tab). Flat list of episodes from every subscription, newest `pubDateEpochMs` first, showing feed title; rows reuse `EpisodeRow` (play / download / queue / mark / favorite / archive / share).

**Soft limit: newest 500** episodes (`PodcastStore.allEpisodes`) — not lazy-paged yet. **Filter chips** (Subscriptions-style capsules): **All** (default) / **Unplayed** / **Downloaded**. Cap is applied first; chips and `.searchable` (title or podcast name) run on that capped set so filters never surface older episodes beyond the soft limit. **Unplayed** = `!isPlayed` && not archived (Inbox spirit, still within All Episodes). **Downloaded** = local file via `DownloadService.isDownloaded`. Selected chip persists in `AppSettings.allEpisodesFilter` (UserDefaults + iOS JSON backup). Empty state when the filter/search matches nothing. Distinct from **Inbox** (unplayed-only, uncapped by this soft limit). Root tabs stay at six (Home first).

## Share

Share an **episode** (title + URL) or a **podcast** (title + feed URL) via the system share sheet (`ShareLink` / `UIActivityViewController`). Episode URL prefers the item page/`link`, then the enclosure/`downloadUrl`. **Feed detail** toolbar shares the feed URL; episode rows expose Share as a button and in the context menu (Feed detail also offers a trailing swipe Share). The **full player** secondary actions include Share when a URL is available. No cloud / social deep links beyond the system sheet.

## Full player

Tap the mini player title or progress bar to open a full-screen sheet: feed artwork **or video surface**, episode title, podcast name, scrubber synced to `PlaybackService`, play/pause, rewind/fast-forward (Settings intervals), speed menu, sleep timer (same presets as mini), plus mark played / favorite / queue / download / share. Chevron dismisses back to the mini player. Prior tabs (Inbox, search, discovery, etc.) unchanged.

## Video player (beta lite)

**Detection:** `PodcastEpisode.isVideo` is true when enclosure MIME is `video/*` or the media URL path ends in `mp4` / `m4v` / `mov` / `webm` (query string ignored).

**Full player:** When video and **Play video as audio only** is off, the artwork slot is replaced by an `AVPlayerLayer` (`EpisodeVideoSurface`) bound to the same `PlaybackService` `AVPlayer` — transport / scrub stay shared. Aspect-fit on a black rounded frame (16:9-ish height).

**Picture in Picture (beta lite):** Full-player toolbar button (**Picture in Picture**) when the video surface is shown. Uses `AVPictureInPictureController(playerLayer:)` on that layer (AVKit), observes `isPictureInPicturePossible`, and enables `canStartPictureInPictureAutomaticallyFromInline` for home/app-switch while the inline surface is visible. Session lives on `PlaybackService` so PiP can outlive the sheet; the layer host is retained while PiP is active (one `AVPlayer` ↔ one layer). Hidden when **Play video as audio only** is on or the episode is not video; disabled when PiP is not possible. `UIBackgroundModes` stays **audio** only (no extra PiP background mode). `AVAudioSession` `.playback` already required.

**Audio only:** Toggle in **Settings → Playback** and on the full player (video episodes only). Default **off**. Hides the video surface and shows artwork; does **not** re-encode or swap to an audio-only track (same media item). Persisted in `AppSettings` / UserDefaults and included in iOS JSON backup. PiP does not apply in audio-only mode.

**Lockscreen / Now Playing:** Remains audio metadata + feed artwork (no video on lock screen). System PiP window is separate from Lockscreen Now Playing.

**Honest limits:** No dedicated landscape video chrome; no AirPlay redesign; automatic PiP only via `canStartPictureInPictureAutomaticallyFromInline` (not a custom home-button handler); exotic codecs depend on AVFoundation; local-folder feeds stay audio-extension-only; PiP availability is system-dependent (`isPictureInPicturePossible`).

## Volume adaptation (P3 lite)

Settings → **Playback → Volume adaptation** (Optimize for speech). Default **off**. Persisted in `AppSettings` / UserDefaults and included in iOS JSON backup.

When **on**, `PlaybackService` configures `AVAudioSession` category `.playback` with mode **`.spokenAudio`** (falls back to **`.voiceChat`** if that mode is rejected). When **off**, mode is **`.moviePlayback`** for video episodes with the surface shown, otherwise **`.default`**. Changes reapply live via `applyAudioSessionConfiguration()` (also when **Play video as audio only** flips).

**Honest:** This is an **iOS audio session mode** (system speech routing / processing hints). It is **not** AntennaPod Android's `LoudnessEnhancer` volume-boost gain curve.

## Skip silence (partial / not on AVPlayer)

Settings → **Playback → Skip silence**. Default **off**. Preference is persisted (+ backup) for UI parity / a future graph, but **`PlaybackService` does not skip silence**. Stock `AVPlayer` has no ExoPlayer-style silence skip; a real implementation needs a custom `AVAudioEngine` + player-node path that would break the shared video `AVPlayerLayer`, Lockscreen / Now Playing, and rate handling. This beta does **not** fake seeks or speed-ups. Matrix: **partial**.

## Keep screen on (beta)

Settings → **Playback → Keep screen on**. Default **off** (battery-friendly). Persisted in `AppSettings` / UserDefaults and included in iOS JSON backup.

When **on** and playback is actively playing (`PlaybackService.isPlaying` or player rate > 0), sets `UIApplication.shared.isIdleTimerDisabled = true`. When paused, stopped, no episode, or the toggle is off, restores `isIdleTimerDisabled = false`. Updates from play/pause/stop/end paths and Settings changes (`RootTabView` / `applyIdleTimerPolicy()`).

**Honest limits:** Idle timer only — does **not** override Low Power Mode system behavior beyond that; no brightness hacks; Picture in Picture and background audio are unchanged.

## Continuous playback

Settings → **Playback → Continuous playback**. Default **on**. Persisted in `AppSettings` / UserDefaults (`continuousPlaybackEnabled`) and included in iOS JSON backup.

When **on**, `PlaybackService.handlePlaybackEnded` snapshots `PodcastStore.nextQueueEpisode(after:)` before mark-played removes the finished item, then starts that next Queue episode (same Play Next / head-of-queue semantics as before). When **off**, episode end still saves progress and marks played (smart-mark / natural end) but does **not** auto-advance — same stop teardown as when the Queue has no next item. **End-of-episode sleep timer** still stops without advancing regardless of this toggle.

## Chapters

**Feed sources:** Parsed by the Swift `XMLParser` path (`NativeRssAtomParser`): Podlove Simple Chapters (`psc:chapter` / `sc:chapter` with `start`/`title`/`href`/`image`) on RSS items and Atom entries, plus Podcast Index `<podcast:chapters url="…">`. Remote Podcast Index JSON is fetched lazily when the full player opens if only a URL is present.

**Media-file tags (beta, local only):** When the episode is playing from a **local** file (downloaded or local-folder feed) and the feed provided **no** chapters, `MediaFileChapterReader` asks AVFoundation for QuickTime/MP4 chapter tracks (`AVAsset.loadChapterMetadataGroups(bestMatchingPreferredLanguages:)`). Titles come from common metadata title items. **Merge preference:** feed chapters win wholesale when non-empty; otherwise media chapters (`ChapterMerger.preferFeed`). No union-by-start-time / Android same-length field merge in this beta.

**Honest ID3 limits:** **ID3v2 CHAP** (typical MP3) and **Vorbis** chapter comments are **not** read — AVFoundation does not expose them as chapter groups on iOS, and this fork does not ship a custom ID3/Vorbis parser. Nero `chpl` only if AVFoundation surfaces it. Matrix documents the same.

Model: `PodcastChapter` (`title`, `startTimeSeconds`, optional `href`/`imageUrl`). Full player shows a chapter list (hidden when empty); tap seeks; the active chapter is highlighted from `PlaybackService.positionSeconds`.

## Transcripts (beta)

**Only when the feed provides a URL** — no Whisper / on-device speech-to-text.

- **Parse:** `NativeRssAtomParser` reads Podcast Index `<podcast:transcript url|href type="…">`. When several tags exist, prefer **JSON > VTT > SRT** (same priority as Android `TranscriptType`). Stores `transcriptUrl` + `transcriptType` on `PodcastEpisode`.
- **Full player:** **Transcript** button appears when `hasTranscriptURL`. Opens a sheet that fetches the remote file (`TranscriptService`), best-effort parses JSON / WebVTT / SRT into timed cues (plain-text fallback if cues cannot be parsed). Tap a cue to **seek**; current cue highlight follows playback. Footer notes feed-URL-only honesty.
- **Cache:** in-memory map (small cap) plus light Caches/`transcripts/` JSON files for the session — not a durable offline library.

## Headset / Bluetooth pause

`PlaybackService` observes `AVAudioSession` interruption notifications (pause on began; resume on ended when `shouldResume`) and route changes (pause when the old output is unavailable — headphones unplugged). Bluetooth headset play/pause buttons stay on `MPRemoteCommandCenter` / Now Playing; interruption handling only pauses or resumes `AVPlayer` and refreshes Now Playing info.

## CarPlay (honest partial)

Audio apps often appear on CarPlay through **system Now Playing** once they publish `MPNowPlayingInfoCenter` metadata and handle `MPRemoteCommandCenter` (already used for Lockscreen). This fork hardens that path; it does **not** ship a custom CarPlay UI.

| Already in place | Notes |
|------------------|--------|
| `UIBackgroundModes` → `audio` | Set in `Info.plist` (background playback + Now Playing eligibility) |
| `AVAudioSession` category `.playback` | Activated on play / resume; mode may be `.spokenAudio` / `.default` / `.moviePlayback` per Settings |
| Remotes | play / pause / toggle, skip± (Settings intervals), seek scrub; next/previous track mapped to skip± for steering wheels |
| Now Playing info | title, artist/album (feed), artwork, duration, elapsed, rate; media type audio |

**Not included (on purpose):** `CPTemplate` / `CPTemplateApplicationScene`, CarPlay audio entitlement (`com.apple.developer.carplay-audio`), or `UIBrowsableContent` / browsable-content APIs — those need Apple entitlement or are the wrong path for a podcast Now Playing surface. Matrix status: **partial**.

## Feed refresh / Keep updated

Settings → **Feeds / Keep updated** offers refresh presets: Manual only, Every 1 / 4 / 12 / 24 hours (persisted in `AppSettings`). When not manual, opening the app (launch `.task` or returning to foreground via `scenePhase`) calls `PodcastStore.refreshAllFeeds()` if the interval elapsed since `lastFeedRefreshAt` (also stamped after Inbox pull-to-refresh). Global interval still drives when auto refresh runs; per-feed **Keep updated → Never** skips that feed in `refreshAllFeeds` (single-feed refresh from Subscriptions still works). Use global / Always both participate today. **BGAppRefreshTask is stubbed**: `Info.plist` only has `UIBackgroundModes` → `audio` (no `fetch`, no `BGTaskSchedulerPermittedIdentifiers`), so `FeedRefreshCoordinator` does not register a background task — enable later by adding those keys.


## New-episode action (Inbox / Queue)

Settings → **Feeds / Keep updated → New episodes**: **Inbox only** (default), **Add to Queue**, or **Add to Queue and download**. After a refresh finds **newly appeared** episode IDs on an **existing** subscription (not first subscribe), `NewEpisodeActionCoordinator` applies the action:

- **Inbox only** — no side effects; episodes still show in Inbox while unplayed (and not archived).
- **Add to Queue** — `PodcastStore.enqueue` (idempotent); Inbox unchanged as a derived list.
- **Add to Queue and download** — enqueue plus `DownloadService.download` (`.automatic`), gated by **Auto-download Wi‑Fi only** (`NetworkPathGate`). Separate global Auto-download (newest-unplayed cap) still runs afterward.

**Per-feed** (Feed detail → gear): **Use global** / **Inbox only** / **Add to Queue**. Queue+download is global-only; a per-feed Queue override never forces download. **Honest beta:** simple global/per-feed choice — not Android’s full new-episode filter rules (KMP later).


## Auto-download

**Download all (Feed detail):** toolbar menu **Download all** with confirmation showing the eligible count. Eligible = unplayed, not archived, not already downloaded / in-flight, remote media URL (skips local-folder files). Soft cap **newest 50**. Enqueues via `DownloadService.downloadAllManual` (`.manual` path); honors **Manual download Wi‑Fi only** once up front — on block shows the same `lastError` / error-log feedback as a single manual download (banner on Feed detail). Does not download played/archived and does not wipe existing downloads.

**Mark all as played (Feed detail):** same toolbar menu, **Mark all as played** with confirmation showing the count of unplayed, non-archived episodes on **this podcast only**. On confirm calls `PodcastStore.markAllPlayed(inFeedId:)` → `markPlayed` per id (auto-delete-after-playing + queue removal still apply). Does **not** archive and does **not** touch other feeds. Disabled when count is 0.

**Episode sort (Feed detail):** toolbar **Sort** menu — **Newest first** (default) or **Oldest first** by `pubDateEpochMs`. Global preference `AppSettings.feedEpisodeSort` (UserDefaults + JSON backup); **not** per-feed (simpler than Android’s per-podcast sort). Missing dates sort last. Applies only to the Feed detail episode list — **Inbox** and **All Episodes** keep their fixed newest-first ordering.

Settings → **Auto-download**: global on/off (default off) and **Episodes per feed** cap (1 / 2 / 3 / 5, default 2). **Wi‑Fi only** for auto-download lives under **Network / Downloads** (default on). After every feed refresh (`refreshAllFeeds`, single-podcast refresh, Inbox pull-to-refresh, Keep updated), `AutoDownloadCoordinator` picks the newest unplayed episodes that are not already downloaded or in-flight and enqueues them through `DownloadService.download` (`.automatic` source skips the manual Wi‑Fi gate). Storage-limit eviction after successful downloads is unchanged. **Per-feed** Auto-download (Use global / Always / Never) is on each podcast’s settings sheet (Feed detail → gear); Always enqueues even when global is off; Never skips that feed; episode cap and Wi‑Fi-only remain global.

## Mobile / Wi‑Fi policy

Settings → **Network / Downloads** (shared `NWPathMonitor` via `NetworkPathGate`):

| Preference | Default | Behavior |
|------------|---------|----------|
| **Auto-download Wi‑Fi only** (`autoDownloadWifiOnly`) | on | Auto-download enqueue skipped on cellular / when path unsatisfied |
| **Manual download Wi‑Fi only** (`manualDownloadWifiOnly`) | off | User Download buttons refused on cellular; error recorded (`lastError` + download-errors log) |
| **Stream Wi‑Fi only** (`streamWifiOnly`) | off | `PlaybackService` refuses network stream URLs on cellular; local offline files still play; honest alert (“Cannot stream”) |

Wi‑Fi / Ethernet satisfy the gate; cellular does not. Turn a toggle off to allow cellular for that action.





## Per-feed settings

Feed detail → **gear** opens a sheet with overrides:

- **Auto-download** — Use global / Always / Never; Always/Never beat the global Settings toggle; episode cap and Network / Downloads Wi‑Fi-only stay global.
- **Keep updated** — Never excludes the podcast from refresh-all; Use global / Always both refresh with the others.
- **New episodes** — Use global / Inbox only / Add to Queue (Queue+download stays a global Settings choice).
- **Notify on new episodes** — Use global / Always / Never; Always/Never beat the global notification toggle (system permission still required).
- **Skip intro / Skip outro** — Use global / Off / 5 / 10 / 15 / 30 / 60 seconds (`nil` in the side map = Use global; explicit `0` = Off for this podcast). Same presets as Settings → Playback.
- **Playback speed** — Use global / 0.8× / 1.0× / 1.2× / 1.5× / 2.0× (`nil` = Use global). Applied when starting a fresh episode for this podcast.

Persisted as a side map keyed by stable `PodcastFeed.id` in Application Support `feed-settings.json` (survives feed refresh; cleared on unsubscribe). Reset to global defaults removes the map entry. `PlaybackService` resolves intro/outro/speed from the feed override when set, otherwise `AppSettings`.

The same sheet also manages **Tags / Folders** (see below).

## Local folder feeds (beta)

**Add podcast → Folder → Choose folder…** uses SwiftUI `fileImporter` (UIDocumentPicker) to pick a directory. A **security-scoped bookmark** is stored in Application Support `local-folder-bookmarks.json`.

**Synthetic feed:** `PodcastFeed` with `feedUrl` scheme `local-folder://{uuid}`. Episodes = audio files in that folder (**mp3 / m4a / aac / wav / flac**, non-recursive); **title** = filename without extension; `downloadUrl` = `file://…` so `DownloadService.localURL` / play treat them as **already local** (no network download).

**Refresh** (Subscriptions swipe or Keep-updated bulk) **re-scans** the folder via the bookmark. **Unsubscribe** deletes the bookmark and ends scoped access.

**Honest limits:** no RSS/Atom; no network feed refresh; not pushed to gpodder / Nextcloud; omitted from OPML and HTML export. Shown in **Subscriptions** with a **Folder** badge. Bookmarks in JSON backup may not work on another device — re-pick the folder after import.

## Tags / Folders

Organize subscriptions with simple string **tags** (Android-style folders, flat — no nested hierarchy in this beta).

- **Persistence:** Application Support `feed-tags.json` — map of feed id → `[String]` (0..n tags per feed). Survives feed refresh; cleared on unsubscribe.
- **Manage:** Feed detail → **gear** (Per-feed settings) → Tags / Folders: add an existing tag or type a new name, swipe/context **Remove**; context **Rename…** (global) or **Delete tag everywhere**. Feed detail shows assigned tags when any exist (**Manage tags…** opens the same sheet).
- **Subscriptions list:** when any tags exist, filter chips (**All** / each tag / **Untagged**) plus optional **Group by tag** (All only): sections per tag then Untagged; a podcast with several tags appears under each. With grouping off, tag names show as a subtitle on rows.
- **Sort:** toolbar menu (**Sort**) — **Recently updated** (default; newest episode `pubDateEpochMs`, same proxy as Home) or **Alphabetical A–Z** by feed title. Persisted in `AppSettings.subscriptionsSort` (+ JSON backup). Applied after search/tag filters; when grouping by tag, feeds inside each section use the same order. **Client-side only** — no drag-reorder of subscriptions in this beta.
- **Lifecycle:** tags exist only while assigned; removing the last use drops the name from the vocabulary (no empty-tag Settings manager in this MVP).

## Skip intervals (Rewind / Fast-forward)

Settings → **Playback → Rewind** / **Fast-forward**: presets **5 / 10 / 15 / 20 / 30 / 60** seconds (`AppSettings.rewindSeconds` / `fastForwardSeconds`, UserDefaults). Defaults match AntennaPod Android (`prefRewindSecs` = 10, `prefFastForwardSecs` = 30). Mini player, full player, and Lockscreen / Now Playing remote skip commands all use these values (SF Symbol icons update when a numbered glyph exists; 20s falls back to plain `gobackward` / `goforward`). Changing the pickers refreshes `MPRemoteCommandCenter` preferred intervals immediately.

## Skip intro / Skip outro

Settings → **Playback → Skip intro** / **Skip outro**: presets **0 / 5 / 10 / 15 / 30 / 60** seconds (`AppSettings.skipIntroSeconds` / `skipOutroSeconds`, UserDefaults; **0 = Off**). On a **fresh start** (resume position ≈ 0), playback seeks forward by skip-intro once per episode play session. When duration is known and **remaining ≤ skip-outro**, `PlaybackService` treats the episode as finished once (mark played + continuous queue next, same path as natural end) — guarded so it does not loop. Resume from mid-episode does not re-apply skip intro. **Per-feed override** (Feed detail → gear → Playback): Use global / Off / same presets; when set, that podcast’s episodes use the override instead of Settings.

## Prefer stream vs download

Settings → **Playback → Playback source**: **Prefer download** (local file via `DownloadService.localURL` when present), **Prefer stream** (always the episode network URL even if downloaded), or **Automatic** (default: local if the file exists, else stream). `PlaybackService.play` and continuous queue auto-next honor this; EpisodeRow / Downloads play buttons no longer force a local URL. Mini player and full player show a small **Local** / **Stream** indicator for the active item.

## Auto-delete after playing

Settings → **Downloads / Storage → Delete episode after playing** (default off, `AppSettings.autoDeleteAfterPlaying`). When an episode is marked played — manual toggle or playback finished / continuous auto-next (`PlaybackService` → `PodcastStore.markPlayed`) — if a local download exists, `DownloadService.delete` removes the offline file and catalog entry. The feed episode row and `isPlayed` status stay. Deletion is deferred while that episode is still the active player item **and** playing from a local file (`shouldBlockAutoDelete`); `PlaybackService` flushes the pending delete on end / stop / switch. **Favorited / starred episodes are skipped** (offline file kept). Starring while a delete is pending cancels it. Storage-limit eviction is unchanged.


## Notifications (new episodes)

Settings → **Notifications → Notify on new episodes** (default on). Uses `UserNotifications` **locally** only — no APNs / push server. Permission is requested when you enable the toggle, or on the first feed refresh that finds new episodes while the toggle is on and status is still undetermined. Settings shows Allowed / Denied / Not determined; if denied, the preference can stay on but no banners fire until iOS Settings allows Notifications (Open iOS Settings button). Per-feed **Notify on new episodes** (Use global / Always / Never) overrides the global toggle for that podcast. After Inbox pull-to-refresh, Keep updated, or a single podcast refresh, newly appeared episode IDs (existing subscriptions only — not first subscribe) post a local notification: **title** = feed title, **body** = episode title, or **“N new episodes”** when several arrive for that feed. Tap opens the **Inbox** tab (best-effort; feed-detail deep link not wired). `PodcastFeed.id` is preserved across refresh so notification ids stay stable.

## Download log / errors + notify on failures

Failed downloads are appended to a ring buffer (~50) in Application Support `download-errors.json` (episode id, title, feed title, message, timestamp). `DownloadService.lastError` still drives a red **Last download failed** banner on the **Downloads** tab (episode + feed when known). **Downloads → Errors** toolbar and **Settings → Notifications → Download errors** open the same simple list; **Clear** wipes the log and banner (offline files kept).

Settings → **Notifications → Notify on download errors** (default on) reuses the same `UNUserNotificationCenter` permission path as new-episode alerts. On failure (no media URL, HTTP error, move failure, or task error — not user cancel), if the toggle is on and permission allows, a **local** notification posts: **title** = episode title, **body** = short error. Tap opens the **Downloads** tab. **No push / APNs.**

Settings → **Notifications → Notify on sync errors** (default on) shares that same permission path. When gpodder.net / Nextcloud **login** or **sync** fails (`GpodderSyncService` records `lastSyncError`), a **local** notification posts: **title** = “Sync failed”, **body** = short error. Tap opens the **Settings** tab and scrolls to **Sync**. **No push / APNs.**

## Discovery

Add podcast sheet (**Subscriptions → +**) has four segments: **Apple**, **Index**, **fyyd**, and **URL**.

**Feed URL / Add by RSS** — Add podcast → **URL** tab: paste an RSS/Atom feed URL → **Preview feed** → Confirm Subscribe (same Preview pipeline as discovery). Already subscribed → **Open feed**.

**Online feed preview** — discovering a podcast (search / charts) or tapping **Preview** on the Feed URL tab opens a Preview screen that fetches and parses the RSS/Atom via `FeedRepository` (same parser as subscribe). Shows title, author/artwork when known (discovery hints + feed image), episode count, and the first **10** episode titles. **Confirm Subscribe** runs `PodcastStore.subscribe(feedUrl:)`; **Cancel** goes back. If the feed URL is already in the library, the primary action is **Open feed** (pushes `FeedDetailView`) instead of Subscribe. Discovery rows are no longer fire-and-forget Subscribe.

**Top lists / Charts** (**Home → Discover** preview, **Subscriptions → Library → Discover**, or See all charts): public Apple iTunes RSS `https://itunes.apple.com/{country}/rss/toppodcasts/limit=25/explicit=true/json` (no API key). Country defaults to the device region (fallback **de**); override under **Settings → Discovery → Charts country**. Entries are parsed for title / artist / artwork; collection ids are resolved to RSS `feedUrl` via a batch `itunes.apple.com/lookup` call. Pull-to-refresh reloads the list; network/country errors are shown honestly. Rows open **Preview** (then Confirm Subscribe).

**Apple Podcasts** uses the public iTunes Search API (`media=podcast`, no API key) via `URLSession` (`ItunesSearchService`). Results that include a `feedUrl` are listed with artwork, title, and artist; **Preview** then Confirm Subscribe uses `PodcastStore.subscribe(feedUrl:)` / `FeedRepository`. Search is lightly debounced (~400 ms). Empty results and network/decode errors are surfaced in the Add sheet.

**Podcast Index** (`PodcastIndexSearchService`) calls `https://api.podcastindex.org/api/1.0/search/byterm` with auth headers `X-Auth-Date`, `X-Auth-Key`, and `Authorization` = SHA-1(`apiKey` + `apiSecret` + unix time) per the Podcast Index docs. **API key and secret are user-supplied** (free registration at podcastindex.org) and stored only in the **Keychain** (`PodcastIndexKeychain`) — nothing is hardcoded or shipped with the app. Paste them under **Settings → Discovery / Podcast Index**. If keys are missing, the Add sheet shows an honest empty state explaining how to get keys. Results show title, author, and artwork; **Preview** then Confirm Subscribe. Debounce matches Apple (~400 ms).

**fyyd** (`FyydSearchService`) calls the public fyyd.de API `https://api.fyyd.de/0.2/search/podcast?term=` (optional `count` / `page`). **No API key** for basic search. Results that include `xmlURL` are listed with artwork (`imgURL`), title, and author; **Preview** then Confirm Subscribe. Debounce matches Apple (~400 ms). Empty results and network/decode errors are surfaced honestly in the Add sheet.


## Sync / gpodder.net / Nextcloud

Settings → **Sync** (beta MVP — **subscriptions only**):

- **Provider** picker: **gpodder.net** (default) vs **Nextcloud** (Gpodder Sync app).
- **Host / base URL**
  - gpodder.net: defaults to `https://gpodder.net` (editable).
  - Nextcloud: custom base — server root (`https://cloud.example.com`) or full API root (`https://cloud.example.com/index.php/apps/gpoddersync/`). If the path does not already contain `gpoddersync`, the client appends `index.php/apps/gpoddersync/` (same root AntennaPod Android + [nextcloud-gpodder](https://github.com/thrillfall/nextcloud-gpodder) use).
- **Username** / **password**: password in the **Keychain**; username + provider + host + device metadata in `UserDefaults`. Nextcloud: prefer an **app password**.
- **Device name** + stable **device id** (gpodder.net API2; Nextcloud has no device API — fields kept for UI/state only; update is a no-op).
- **Login** / **Logout** / **Sync now**; last sync time, status, error. Login/sync failures can post a **local** notification when Settings → Notify on sync errors is on (tap → Settings Sync).

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

## Data backup (iOS JSON)

Settings → **Backup** (beta):

- **Include downloaded episode files** — toggle (default **off**). Off = catalog-only JSON ZIP (small/fast). On = also pack Documents/downloads into ZIP folder `downloads/` (STORE / no compression); UI shows approximate file count + size and a confirmation when exporting with media (can be large/slow).
- **Export data backup** — builds a ZIP (`AntennaPod-iOS-Backup-….zip`) with `manifest.json` (`includesMedia` flag), Application Support maps (`feeds`, `queue`, `playback`, `downloads` catalog, `feed-settings`, `favorites`, `archived`, `feed-tags`, `download-errors`, `local-folder-bookmarks`), `app-settings.json`, `gpodder-prefs.json`, and optionally `downloads/<fileName>` media. Share via the system sheet.
- **Import data backup** — file importer (`.zip`) → confirmation **Replace local data?** → restore JSON maps + prefs → if present, write ZIP `downloads/*` into Documents/downloads (merge: overwrite same names, leave other local files) → refresh store / downloads catalog (pruned to media present on device) / Settings / gpodder.
- **Honesty:** iOS JSON Application Support backup — **not** Android AntennaPod database export. Media is **optional** (default omitted). **No Keychain secrets** (re-enter gpodder password / Podcast Index keys on a new device; same-device Keychain may still unlock login). HTML subscription list is **Export subscriptions as HTML** under Import / Export (not this ZIP).

## OPML

Export writes AntennaPod-compatible OPML 2.0 (`outline` with `text`/`title`/`xmlUrl`/`htmlUrl`) via a share sheet. Import uses the system file picker (`.opml` / `.xml`), parses with Foundation `XMLParser`, and subscribes each feed URL through the existing `FeedRepository` pipeline (skips duplicates; shows progress and per-feed errors). Entry points: **Settings → Import / Export** and **Subscriptions** toolbar.

## HTML export

**Settings → Import / Export → Export subscriptions as HTML** (also on Subscriptions toolbar sheet). Writes a self-contained `.html` file (inline CSS, AntennaPod-blue lite styling) listing each subscription: **title** (links to site when known), **feed URL** as a link, and **episode count**. Share via the system sheet. Sorted by title. Distinct from OPML (machine import) and the JSON ZIP backup (full state). Export-only — no HTML import.
