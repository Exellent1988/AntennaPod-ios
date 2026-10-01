# ios/ — AntennaPod for iOS

Fork-only SwiftUI shell. Playback via AVFoundation; networking/downloads via URLSession; persistence in-memory for now (SQLite later). Shared KMP parser is validated in `shared/kmp`; the iOS app currently uses a Foundation `XMLParser` fallback with the same golden fixtures in mind. Wiring the XCFramework into the app is the next integration step.

## Status (Phase 1 skeleton)

- Subscribe by feed URL
- Apple Podcasts / iTunes Search discovery (Add sheet; debounced; Subscribe via feed URL)
- Podcast Index discovery (Add sheet tab; user-supplied API key+secret in Keychain; Settings → Discovery; debounced; Subscribe via feed URL)
- fyyd discovery (Add sheet tab; public fyyd.de search API, no key; debounced; Preview → Subscribe via feed URL)
- Top lists / Quick discovery (Apple iTunes RSS charts; Home preview + Subscriptions → Discover; country in Settings; pull-to-refresh; Subscribe via feed URL)
- Online feed preview (before subscribe: discovery rows + Feed URL → Preview via FeedRepository; episode count + first titles; Confirm Subscribe / Cancel; already subscribed → Open feed)
- Add from Clipboard (beta; Add podcast toolbar + URL tab when pasteboard holds trimmed http(s) URL with host; opens same Preview → Confirm Subscribe; no auto-subscribe; not OPML clipboard)
- Episode list
- Stream playback (AVPlayer, speed tap-cycle presets + long-press menu, configurable skip intervals)
- Full player sheet (artwork or video surface, scrubber, **Jump to position** (mm:ss / min+sec → seek), **Play from beginning** (seek to 0 + play), **Previous/Next chapter** when chapters exist, **current chapter title** (mini + full), transport, **Shownotes** (plain text / HTML stripped); secondary **Download / Cancel download / Delete download** via `DownloadService` (hidden for local-folder `file://`; **Delete** uses `confirmationDialog` with episode title — local offline file only, keeps played / queue / favorites; same confirm on Downloads swipe Delete; manual Wi‑Fi gate); tap mini player to open; **Open podcast** → dismiss → Subscriptions Feed detail; orphan → disabled / unavailable alert; mini ⋯ menu same)
- Video player (beta lite; MIME video/* or mp4/m4v/mov/webm → AVPlayerLayer in full player; PiP beta lite)
- Video → audio only (Settings + full-player toggle; default off; Lockscreen stays audio)
- Volume adaptation (Settings; default off; iOS AVAudioSession spokenAudio / speech optimize — not Android loudness gain)
- Skip silence (Settings toggle only; not applied on stock AVPlayer — needs custom audio graph)
- Stereo to mono (Settings; default off; best-effort `AVAudioSession` preferred output channels = 1 — route-dependent; not ExoPlayer remix)
- Keep screen on while playing (Settings; default off; `isIdleTimerDisabled` only — no Low Power Mode override / brightness; PiP/background audio unchanged)
- Chapters (PSC / Podcast Index from feed + media-file QuickTime/MP4 tags on local files; list in full player; tap to seek; **Previous/Next chapter** when available; **current chapter title** on mini + full player)
- Transcripts (beta; feed `podcast:transcript` URL only — fetch VTT/SRT/JSON, scrollable sheet, tap cue seek; no Whisper/STT)
- Episode description / Shownotes (beta; RSS `description`/`content:encoded` → `descriptionText`; full player + EpisodeRow context sheet; plain text, HTML stripped; empty state; refresh to populate existing feeds)
- Episode duration on list rows (beta; RSS `itunes:duration` / Media RSS → `PodcastEpisode.durationSeconds`; EpisodeRow caption `m:ss`/`h:mm:ss` via share/scrubber formatter; fallback to `playback.json` duration; hide when unknown/zero; VoiceOver EN/DE; no Settings toggle)
- Episode enclosure/file size on list rows (beta; EpisodeRow caption compact KB/MB/GB via `DownloadStorageUsage.formatBytes` / `ByteCountFormatter`; prefer on-disk `fileSize` when downloaded or local-folder, else feed enclosure `PodcastEpisode.size` when > 0; hide when unknown; same honesty as Downloads rows; VoiceOver EN/DE **Size …**; no Settings toggle)
- Relative publish dates on list rows (beta; EpisodeRow `pubDateEpochMs` via `EpisodeDateFormatting`: Today / Yesterday / N days ago for ≤7 calendar days (`RelativeDateTimeFormatter` locale-aware EN/DE), else medium absolute; caption `date · duration · size` (omit unknown parts); History/Favorites/Archived `dateOverride` stays live SwiftUI `.relative`; VoiceOver includes publish caption; no Settings toggle)
- EpisodeRow in-progress playback (beta polish; thin `ProgressView` under caption when `playback.json` `positionSeconds > 1` and not `isPlayed` and duration known — fraction = position/duration; duration from playback state or feed `itunes:duration`/media; hide when unplayed, played, or duration unknown; VoiceOver EN/DE **N percent played** + remaining, or **At m:ss** if duration unknown; no Settings toggle)
- Feed / podcast description (beta; channel `description`/`subtitle`/`summary` → `PodcastFeed.descriptionText`; Feed detail toolbar info → sheet with title + plain text; hidden when empty; refresh may be needed for older saves; no author on model)
- Lockscreen / Now Playing (title, podcast, artwork, remote play/pause/skip/seek using Settings intervals)
- CarPlay (honest partial: system Now Playing / remotes + background audio; **no** custom CPTemplate / CarPlay entitlement)
- Headset / Bluetooth pause (AVAudioSession interruption + headphone unplug; remotes unchanged)
- Sleep timer (clock presets + end of episode + Custom… 1–180 min, fade-out; mini player shows live remaining when active)
- Offline download to Documents/downloads (background URLSession; survives suspend/relaunch; Feed detail **Download all** for unplayed/not-archived/not-downloaded, newest 50 soft cap; **Full player** Download / Cancel / Delete via same `DownloadService.download` / `cancelDownload` / `delete`)
- Queue tab (JSON; swipe Remove (**confirm** + title; queue only — no download delete / mark played / stop playback) + Archive; Edit drag reorder; EpisodeRow context **Move to top** / **Move to bottom** via `moveQueue`; toolbar **Shuffle** (`shuffleQueue` full queue + confirm; **blocked when locked**; disabled if <2; currently playing moves with episode id); **Queue lock** toolbar + Settings disables reorder / Shuffle / Move to top-bottom only; filter chips **All** / **Unplayed** / **Played** via `isPlayed` (`queueFilter`); **remaining time** info bar over visible filtered list; `.searchable` title/feed with debounce; reorder disabled while chip/search filtering or locked; toolbar Clear queue with **always** confirm (full queue count + honesty; works when locked); **tab badge** = `queue.count` (**full** queue, not chip/search; hidden when 0); **full player** Queue menu Add/Remove toggle (**Remove** confirm + title; queue only) + Play Next)
- Home tab (configurable sections: Continue, Inbox, Queue, Discover, Recently updated, Favorites optional; Settings → Home layout; pull-to-refresh; `.searchable` title/feed on section episode previews + Recently updated podcast titles with debounce; empty sections hide while filtering; Discover hidden while searching; empty state when no matches)
- German localization (beta; main `Localizable.xcstrings` en+de + per-target Widget/Watch catalogs; tabs/nav, Settings headers + footnotes/help captions, parental detail, Statistics + Echo, Discovery chrome, library empty states, download errors, Sync labels, notification titles, Chapters/Transcript, Homescreen Widget + Apple Watch UI — **partial**, not full i18n)
- Accessibility / VoiceOver (beta polish; EpisodeRow combined labels (incl. relative publish date + duration + size when known + in-progress percent/remaining when known) + action button labels; mini/full player transport; tab Labels; Settings toggle hints — not a full audit)
- Inbox tab (unplayed, non-archived across subscriptions; pull-to-refresh; swipe Archive + Mark played + Play Next + Add to queue; toolbar **Sort** Newest/Oldest first by `pubDateEpochMs` (`inboxSort`); toolbar menu **Add all to queue** (confirm eligible = full Inbox minus queued; `enqueueAllInbox` append newest-first; skip queued; OK when Queue locked) + Archive all + Mark all as played with confirm; **remaining time** info bar over visible sorted Inbox list (hidden during library search); **tab badge** = `inboxEpisodes.count`, hidden when 0)
- History (played / in-progress from `playback.json`; Subscriptions → Library → History; toolbar **Sort** Newest/Oldest first by `lastPlayedAtEpochMs` (`historySort`); **History size** cap Settings → Library `historySizeLimit` 50/100/200/500/Unlimited default; **remaining time** info bar over visible sort+search list (played→0; not Clear catalog); `.searchable` title/feed filter with debounce; toolbar Clear history with confirm on full list)
- Statistics (beta; Subscriptions → Library → Statistics + Settings; totals + top podcasts from `playback.json`; approx time; **time range** This week / This month / This year / All time)
- Echo / Year in Review (beta lite; Library + Settings; shared Statistics time range on playback/favorites; ShareLink text)
- About / contribute links (Settings → About; fork blurb; Bundle version; antennapod.org / GitHub / contribute / docs / this fork)
- Rating prompt (optional; after 10 mark-played, once per install `AppStore.requestReview`; Settings toggle default on + Reset; iOS may suppress)
- Siri Shortcuts lite (App Intents Play/Pause / Skip forward/back + `antennapod://` URL schemes; opens app; needs current episode)
- Homescreen widget (beta lite; WidgetKit Continue listening from App Group snapshot; tap → `antennapod://play`; empty placeholder; may be stale / no scrubber)
- Apple Watch companion (beta lite; watchOS Continue listening from same snapshot via WC push; Play → iPhone `antennapod://play`; empty state; no independent playback / downloads / queue)
- Swipe actions (Queue Remove(**confirm**+title; queue only)+Archive + drag reorder (off when Queue locked) + Shuffle confirm (full queue; blocked when locked; <2 off) + Clear queue confirm + EpisodeRow Move to top/bottom when queued and unlocked; Downloads Play Next+Add to queue+Delete + toolbar Add all to queue confirm + Delete played downloads confirm; Inbox Archive+Mark played+Play Next+Add to queue; Feed Mark played/unplayed+Archive (+ remaining time sort→chip→search; searchable title; Download all / Mark all played / Add all to queue confirm on full-feed eligibility)/History(+ remaining time + searchable + Add all to queue confirm + Clear history confirm)/Favorites(+ remaining time + searchable + Add all to queue confirm + Clear favorites confirm)/Archived(+ remaining time + searchable + Add all to queue confirm + Restore all confirm)/All Episodes(+ remaining time soft-capped+filtered; Mark played/unplayed+Archive; toolbar Add all to queue confirm soft-cap newest 500))
- Favorites / starred episodes (Subscriptions → Library → Favorites; optional Home preview via Home layout; star on **EpisodeRow** + **full player** secondary via `PodcastStore.toggleFavorite` / `favorites.json`; VoiceOver Add to favorites / Remove from favorites; swipe Unfavorite + Archive; **remaining time** info bar over visible sort+search list; `.searchable` title/feed filter with debounce; toolbar **Add all to queue** (confirm eligible full Favorites; OK when Queue locked) + Clear favorites with confirm on full list; auto-delete skips favorites)
- Archive / restore episodes (side map `archived.json`; hide from Inbox / Home New; feed lists keep with dim/badge; **full player** secondary Archive/Restore via `PodcastStore.toggleArchived` + EpisodeRow + Feed/Inbox/Queue/Favorites/All Episodes swipe; Library → Archived with toolbar **Sort** Newest/Oldest by `archivedAtEpochMs` (`archivedSort`) + **remaining time** info bar over visible sort+search list (archived≠played; not Restore all catalog) + `.searchable` + toolbar **Add all to queue** (confirm eligible full Archived; newest archived first; OK when Queue locked; does not restore) + Restore all confirm on full list; bulk **Add all to queue** + Archive all + Mark all as played in Inbox; Favorites / Downloads / History / All Episodes / Feed detail toolbar **Add all to queue**)
- Episodes / All episodes (Subscriptions → Library → Episodes; all feeds; soft cap newest 500 then toolbar Sort Newest/Oldest by pubDate (`allEpisodesSort`) → All/Unplayed/Downloaded/Favorites chips + searchable title/feed; Oldest only within cap; **remaining time** info bar over visible soft-capped+filtered list; toolbar **Add all to queue** (confirm eligible soft-capped newest 500; newest pubDate first; OK when Queue locked); EpisodeRow actions; swipe Archive + Mark played/unplayed; filter + sort persisted in AppSettings)
- Share podcast / episode (system share sheet; episode URL: page link → enclosure → feed site/RSS; `Title — Podcast` message; **Share with position** = same URL + text timestamp `(12:34)` when current item; full player + Shownotes toolbar + EpisodeRow / swipe / context; FeedDetail podcast share + Copy feed URL; no AntennaPod deep link / no `#t=` / no gPodder fake share)
- Open episode website (opens episode `link` http(s) in system Safari/default browser via `openURL`; full player secondary + Shownotes toolbar + EpisodeRow context; hidden when no usable link; never enclosure / never invents URL; no in-app WebView)
- Copy episode link (pasteboard `UIPasteboard.general` + brief Copied alert / haptic like Copy feed URL; webpage `link` http(s) only via `websiteURL`; full player + Shownotes + EpisodeRow context; optional clearly labeled **Copy media URL** for enclosure; never silently copies enclosure as episode link; never invents URL)
- Library search (local subscriptions/episodes; Inbox searchable + Subscriptions list searchable title/`descriptionText`; Queue/Downloads/Favorites/History/Archived/Home title/feed; Feed detail episode title; not iTunes)
- Playback progress save / resume (`lastPlayedAt` for History)
- Mark played / unplayed (EpisodeRow button/context, Feed leading swipe, **Full player** secondary, All Episodes leading swipe via `PodcastStore.isPlayed` / `togglePlayed` — same `playback.json`; no seek/stop on toggle; VoiceOver hints; Smart mark Off/15/30/60/120 default 30; Inbox + Feed detail Mark all as played with confirm; Feed detail **Add all to queue** with confirm on full feed catalog)
- Settings tab (**Appearance** Theme System/Light/Dark via `preferredColorScheme`, **Home layout** (show/hide + reorder), default playback speed, rewind/FF intervals, skip intro/outro, volume adaptation, skip silence preference, Stereo to mono, Keep screen on, Continuous playback, Show remaining time, Rewind after pause, Smart mark as played, playback source, play video as audio only, feed refresh interval, **new-episode action** (Inbox / Queue / Queue+download), auto-download, Network / Downloads Wi‑Fi policy, auto-delete after play, notify on new episodes / download errors / sync errors, Discovery charts country + Podcast Index API keys, gpodder.net / Nextcloud Gpodder sync, **Parental controls** (PIN / Keychain), **Backup** (iOS JSON), Import / Export (OPML + HTML), Statistics / Echo links, App Store rating prompt, Siri/Shortcuts note, Homescreen widget note, Apple Watch note, CarPlay note, About; **`.searchable`** filters sections/rows by localized title + listed footnotes with debounce; empty sections hide; empty state when no matches)
- Prefer stream vs download (Prefer download / Prefer stream / Automatic; honored on play)
- Continuous playback (Settings toggle, default on; auto-next from Queue when an episode ends; off = stop without advance)
- Show remaining time (Settings toggle, default off; mini + full player right label −remaining; full-player tap toggles)
- Rewind after pause (Settings Off/1/2/3/5/10, default 2; resume after pause ≥1s seeks back; not on cold play)
- Smart mark as played (Settings picker Off/15/30/60/120, default 30; Off = natural end / explicit only)
- Feed refresh / Keep updated (global interval; auto on launch & foreground when due)
- New-episode action (Inbox only / Add to Queue / Add to Queue and download; per-feed Use global / Inbox / Queue; after refresh newcomers only)
- Auto-download (global on/off + episodes-per-feed cap; **new episode IDs after refresh only**; Wi‑Fi only under Network / Downloads; per-feed Use global / Always / Never; skips local-folder)
- Mobile / Wi‑Fi policy (auto / manual download / stream Wi‑Fi-only toggles; shared NWPathMonitor)
- Per-feed settings (Feed detail → gear: Auto-download, Keep updated, New episodes, Notify, Skip intro/outro, Playback speed overrides)
- Tags / Folders for subscriptions (side map `feed-tags.json`; assign on per-feed settings; **Manage tags** in Settings → Library + Subscriptions toolbar — list with counts, rename, delete with confirm; filter chips + optional group-by-tag; untagged)
- Unsubscribe confirm (Subscriptions trailing swipe + Feed detail ⋯; destructive dialog with podcast title; removes feed + feed-settings + tags + queue items from that feed + favorites/archive/playback history for its episodes; **keeps downloaded files**; local-folder releases bookmark; dismisses Feed detail after confirm)
- Subscriptions list sort (toolbar: Recently updated default / Alphabetical A–Z; `subscriptionsSort` pref + backup; client-side only, no drag-reorder)
- Subscriptions list search (`.searchable`; filter by feed title and optional `descriptionText`; light debounce ~250 ms; empty query = sorted list; empty state when no matches; sort + tag filters still apply; no author/authorEmail on model)
- Subscriptions unplayed badge (per-row count `!isPlayed && !isArchived`; hide when 0; VoiceOver includes count; single-pass `PodcastStore.unplayedCountsByFeedId`; full stored feed catalog — not All Episodes 500 soft cap)
- Refresh all on Subscriptions (toolbar **Refresh all** + pull-to-refresh → `PodcastStore.refreshAllFeeds()`; ProgressView while `isLoading`; disabled when empty / in flight; same keep-updated / network / auto-download path as Home, Inbox, and interval)
- Feed episode list sort (Feed detail toolbar: Newest first default / Oldest first by `pubDateEpochMs`; global `feedEpisodeSort` + backup; All Episodes has `allEpisodesSort`; Inbox has its own sort)
- Inbox sort (Inbox toolbar: Newest first default / Oldest first by `pubDateEpochMs`; `inboxSort` pref + backup; missing dates last, tiebreaker episode `id`; Home New preview stays newest-first)
- All Episodes sort (Library → Episodes toolbar: Newest first default / Oldest first by `pubDateEpochMs`; `allEpisodesSort` pref + backup; soft cap newest-500 first — Oldest only reorders within cap; pipeline soft cap → sort → chip → search; missing dates last, tiebreaker episode `id`)
- History sort (History toolbar: Newest first default / Oldest first by `lastPlayedAtEpochMs` = lastPlayedAt else updatedAt; `historySort` pref + backup; tiebreaker episode `id`; applies to search; store catalog stays newest-first for Home Continue / Clear counts)
- History size limit (Settings → Library **History size**: 50 / 100 / 200 / 500 / **Unlimited** default; `historySizeLimit` + backup; trim oldest by lastPlayedAt else updatedAt on append/load/Settings change — same as Remove from history; no separate history.json; History footnote when finite)
- Favorites sort (Favorites toolbar: Newest first default / Oldest first by `favoritedAtEpochMs`; `favoritesSort` pref + backup; tiebreaker episode `id`; applies to search; store catalog stays newest-first for Home Favorites preview / Clear counts)
- Archived sort (Archived toolbar: Newest first default / Oldest first by `archivedAtEpochMs`; `archivedSort` pref + backup; tiebreaker episode `id`; applies to search; store catalog stays newest-first for Restore all counts)
- Local folder feeds (beta; Add podcast → Folder via fileImporter; security-scoped bookmark; synthetic feed from mp3/m4a/aac/wav/flac; refresh re-scans; no RSS/network; Folder badge; unsubscribe releases bookmark)
- OPML import/export (Settings + Subscriptions; share sheet / file picker; batch subscribe)
- HTML subscription export (Settings + Subscriptions Import / Export; share sheet `.html`)
- Local data backup import/export (Settings → Backup; iOS JSON ZIP of Application Support maps + Settings + gpodder prefs; optional Include downloaded episode files → ZIP `downloads/`; no Keychain secrets; not Android DB)
- HTML export (Settings → Import / Export → Export subscriptions as HTML; self-contained list with title, feed URL links, episode count; share sheet; distinct from OPML + JSON backup)
- Download storage limit (Settings: usage + max size; auto-evict played first)
- Auto-delete after playing (global toggle; deletes offline file on mark played; keeps episode row)
- Notifications for new episodes (local UserNotifications after refresh; Settings toggle **default off**; one aggregated banner; tap opens Inbox; no push)
- Downloads tab filter chips (**All** / **Unplayed** / **Played** via `isPlayed`; persisted `downloadsFilter`) + **remaining time** info bar (visible chip+search filtered list; unknowns skipped with `~`; **not** full catalog / tab badge) + search (`.searchable`; title and/or feed; light debounce; empty query = all under chip; empty state when no matches) + **row file size** when known (disk `fileSize` preferred, else enclosure `PodcastEpisode.size`; `ByteCountFormatter`; hide when unknown) + toolbar **status** total (`storageUsage`) + toolbar **Add all to queue** (confirm eligible full catalog; catalog order oldest completed first; OK when Queue locked) + toolbar **Delete played downloads** (confirm **global** count/size — not chip-scoped; skips favorites; keeps unplayed) + **tab badge** = `DownloadService.downloads.count` (**full** completed catalog, not chip/search/in-progress; hidden when 0)
- Queue tab filter chips (**All** / **Unplayed** / **Played** via `isPlayed`; persisted `queueFilter`) + **remaining time** info bar (visible filtered list; unknowns skipped with `~`) + search (`.searchable`; title and/or feed; light debounce; empty query = all under chip; empty state when no matches; **Edit/drag reorder disabled while chip/search filtering** — filtered indices would not map to full queue; Move to top/bottom stay id-based when unlocked; Shuffle/Clear still target full queue)
- Favorites search (`.searchable`; filter by episode title and/or feed title; light debounce; empty query = all; empty state when no matches; **remaining time** info bar over visible sort+search list — **not** full-catalog Clear count; **Add all to queue** / **Clear favorites** still use **full** favorites catalog (eligible = not already queued for Add all; Clear count always full list); enabled for Clear whenever favorites non-empty even if filter shows no rows; Add all disabled when eligible==0)
- History search (`.searchable`; filter by episode title and/or feed title; light debounce; empty query = all; empty state when no matches; **Sort** Newest/Oldest by `lastPlayedAtEpochMs` applies to filtered results; **remaining time** info bar over visible sort+search list — **not** full-catalog Clear count; **played** (not current) → 0 (totals may often be low); **Add all to queue** / **Clear history** still use **full** history catalog (eligible = not already queued for Add all; Clear count always full list); enabled for Clear whenever history non-empty even if filter shows no rows; Add all disabled when eligible==0)
- Archived search (`.searchable`; filter by episode title and/or feed title; light debounce; empty query = all; empty state when no matches; **Sort** Newest/Oldest by `archivedAtEpochMs` applies to filtered results; **remaining time** info bar over visible sort+search list — **not** full-catalog Restore all count; **archived ≠ played** (normal duration−position; played→0); **Add all to queue** / **Restore all** still use **full** archived catalog (eligible = not already queued for Add all; Restore count always full list); enabled for Restore whenever archived non-empty even if filter shows no rows; Add all disabled when eligible==0; Add all does not restore/unarchive; Restore does not mark unplayed or delete downloads)
- Feed detail search (`.searchable`; filter by episode title; light debounce ~250 ms; empty query = sorted full list; empty state when no matches; respects Newest/Oldest sort on the filtered set; title + optional `descriptionText`; **remaining time** info bar over visible sort→chip→search list; **Download all / Mark all as played / Add all to queue still use full-feed eligibility counts** — not the filtered subset)
- Download log / errors (ring buffer in Application Support; Downloads banner + errors list; Clear errors)
- Notify on download / sync errors (local UserNotifications; Settings toggles default on; DL tap → Downloads; Sync tap → Settings Sync; no push)
- Parental controls (beta; Settings → Parental controls; 4–6 digit PIN in Keychain; lock Add/Discover; optional Network/Downloads lock + hide explicit charts; session unlock until background)
- gpodder.net / Nextcloud Gpodder sync (subscriptions MVP: provider picker; Keychain; pull+push feed URLs; additive merge; episode actions later)

Root tabs (6): **Home**, Inbox (count badge when `inboxEpisodes.count` > 0), Subscriptions, Queue (count badge when `queue.count` > 0 — **full** queue, not filter chips), Downloads (count badge when `downloads.downloads.count` > 0 — **full** completed catalog, not chip/search/in-progress), Settings.

## Layout

```
ios/
├── README.md
├── project.yml              # XcodeGen (app + AntennaPodWidget + AntennaPodWatch)
├── Shared/                  # App Group Continue-listening snapshot (app + widget + watch keys)
├── AntennaPodWidget/        # WidgetKit extension (Continue listening + Localizable.xcstrings en+de)
├── AntennaPodWatch/         # watchOS companion (Continue listening + Play on iPhone + Localizable.xcstrings en+de)
└── AntennaPod/
    ├── AntennaPodApp.swift
    ├── AntennaPod.entitlements   # App Group
    ├── App/RootTabView.swift
    ├── Data/…               # store, repository, playback, download, parsers, WatchCompanionBridge
    └── Features/…           # home (+ charts preview + searchable), inbox (+ tab badge; remaining time), all episodes (+ remaining time), history (+ remaining time), statistics, echo, favorites (+ remaining time), archived (+ remaining time), library search, subscriptions (+ Discover charts + Manage tags + unplayed badge), feed detail + per-feed settings (+ tags), ManageTagsView, add/discover (+ feed preview + local folder), top lists, player (+ transcripts sheet), downloads (+ tab badge full catalog; filter chips + searchable + error log), queue (+ tab badge full count; searchable; reorder off while filtering), settings (+ searchable titles/footnotes; Home layout + Manage tags + gpodder/Nextcloud sync + charts country + Parental controls + Backup + Statistics + Echo + App Store rating + Siri note + Homescreen widget note + Apple Watch note + CarPlay note + About), queue swipes/reorder, OPML, HTML export, data backup, notifications (new eps + DL errors)
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

Subscriptions, queue, per-feed settings (`feed-settings.json`), subscription tags (`feed-tags.json`), starred episode ids (`favorites.json`), archived episode ids (`archived.json`), and per-episode playback state (`positionSeconds`, `durationSeconds`, `isPlayed`, `lastPlayedAtEpochMs`) are stored as JSON under Application Support (`PodcastPersistence`: `feeds.json`, `queue.json`, `feed-settings.json`, `feed-tags.json`, `favorites.json`, `archived.json`, `playback.json`). Inbox is derived from that state (unplayed, non-archived episodes across feeds; store order newest-first; Inbox tab re-sorts via `inboxSort`). Archived episodes stay on feed lists (dimmed/badge) and in Library → Archived (store catalog newest-archived first; ArchivedView re-sorts via `archivedSort`); toolbar **Add all to queue** (confirm eligible full catalog; newest archived first; Queue lock does not block; does not restore/unarchive) + Restore all (confirm). All Episodes is the same cross-feed catalog without the unplayed filter (soft-capped at newest 500 by pubDate; AllEpisodesView re-sorts via `allEpisodesSort` — Oldest only within that cap); toolbar **Add all to queue** (confirm eligible soft-capped newest 500; newest pubDate first within cap; Queue lock does not block; not chip/search). History lists played or in-progress episodes (store catalog newest `lastPlayedAt` first; HistoryView re-sorts via `historySort`); swipe removes playback state or marks unplayed; toolbar **Add all to queue** (confirm eligible full catalog; newest last-played first; Queue lock does not block) + Clear history bulk-removes the same playback entries (confirm). Older `playback.json` without `lastPlayedAt` migrates from `updatedAt` when played/in-progress. Playback resumes from the saved position; episodes are auto-marked played within the configurable Smart mark window (`smartMarkAsPlayedSeconds`, default 30; Off = natural end / explicit only) or when playback ends. Theme, default playback speed, rewind/fast-forward intervals, skip intro/outro seconds, volume adaptation, skip silence preference, Stereo to mono, Keep screen on, Continuous playback, Show remaining time, Rewind after pause, Smart mark as played, playback source preference, feed refresh interval, new-episode action, auto-download, Network / Downloads Wi‑Fi policy (`autoDownloadWifiOnly` / `manualDownloadWifiOnly` / `streamWifiOnly`), auto-delete-after-playing, notify-on-new-episodes / notify-on-download-errors, subscriptions list sort (`subscriptionsSort`), feed episode list sort (`feedEpisodeSort`), Inbox sort (`inboxSort`), Downloads sort (`downloadsSort`), Downloads filter (`downloadsFilter`), Queue filter (`queueFilter`), History sort (`historySort`), History size limit (`historySizeLimit`), Favorites sort (`favoritesSort`), Archived sort (`archivedSort`), All Episodes filter (`allEpisodesFilter`), All Episodes sort (`allEpisodesSort`), and Statistics/Echo time range (`statisticsTimeRange`) prefs live in `UserDefaults` (`AppSettings`) and apply via `preferredColorScheme` / fresh episode starts / mini+full+Now Playing skip / `PlaybackService.play` source resolution / launch+foreground due-check / post-refresh enqueue / mark-played download cleanup. Downloads are files under Documents/downloads with a JSON catalog (`downloads.json`), in-flight background task↔episode map (`pending-downloads.json`), and a recent download-error ring buffer (`download-errors.json`, ~50 entries: episode id/title, feed, message, timestamp). Background transfers use `URLSessionConfiguration.background(withIdentifier:)` plus `AppDelegate.handleEventsForBackgroundURLSession`. Download storage limit lives in `UserDefaults` (`AppSettings.downloadStorageLimit`); `DownloadService` measures Documents/downloads usage, enforces the budget after each successful download (and on Settings open / app launch) by deleting **played** episodes first (oldest file mtime), then unplayed (LRU). Settings also offers **Clear downloads** with confirmation. Single **Delete** (Downloads swipe and Full Player) confirms with the episode title — removes the local offline file only (played status, queue, and favorites stay). The **Downloads** tab offers filter chips (**All** / **Unplayed** / **Played**) via `downloadsFilter`, toolbar **Add all to queue** (confirm with **eligible** full-catalog count minus already queued; `enqueueAllDownloads` append catalog order oldest completed first; Queue lock does not block), and toolbar **Delete played downloads** (confirm with **full-catalog** count + approximate size — **not** limited to the visible chip/search filter): removes offline files for episodes marked played via the single-delete path; **skips favorited / starred** episodes (same as auto-delete-after-playing); keeps unplayed downloads, played status, and queue — distinct from Clear all. GRDB/SQLite aligned with AntennaPod schema comes later.

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

- **Discover** — Apple iTunes top podcasts preview (charts country from Settings); See all → full charts list with Preview → Confirm Subscribe. When enabled, always shows the charts preview (not empty-hidden) **except while Home search is active** (hidden during filtering — charts are not title-matched).
- **Continue listening** — in-progress episodes (`positionSeconds > 1`, not played), newest `lastPlayedAt` first; rows reuse `EpisodeRow` (resume / download / queue / mark). Hidden when empty.
- **New / Inbox** — preview of unplayed, non-archived episodes (same derivation as Inbox, capped; always newest-first — does not follow Inbox `inboxSort`); chevron / See all switches to the Inbox tab. Hidden when empty.
- **Queue** — preview of queued episodes when the queue is non-empty; See all → Queue tab. Hidden when empty.
- **Recently updated** — subscriptions sorted by newest episode `pubDateEpochMs`; tap → `FeedDetailView`; See all → Subscriptions. Hidden when empty.
- **Favorites** (optional) — starred episodes preview; See all → Library Favorites. **Off by default**; enable under Home layout. Hidden when empty.

Default order: Discover → Continue → Inbox → Queue → Recently updated → Favorites (hidden). Home layout supports toggles, Edit/drag reorder, and Reset to defaults. Pull-to-refresh calls `refreshAllFeeds()` (same as Inbox / Subscriptions pull + Subscriptions toolbar **Refresh all**; Discover preview reloads on appear / country change). Empty library shows a welcome empty state (and Discover when that section is enabled). **Search** (`.searchable`, ~250 ms debounce) filters Continue / Inbox / Queue / Favorites episode previews by episode title and/or feed title, and Recently updated by feed title (filters the full section catalog then caps at the preview limit). Empty optional sections still hide when they have no matches. **Discover** is hidden while searching (charts preview is not title-filtered). Empty state when the query matches nothing. Home layout prefs / section order are unchanged.


## Localization (German, beta / partial)

Development language remains **English** (`developmentRegion: en`). `ios/project.yml` `knownRegions` includes `en`, `de`, and `Base`. User-visible copy lives in **`ios/AntennaPod/Localizable.xcstrings`** (main app String Catalog; en source + de), plus per-target catalogs **`ios/AntennaPodWidget/Localizable.xcstrings`** and **`ios/AntennaPodWatch/Localizable.xcstrings`** (duplicated minimal keys; not shared with the main catalog).

SwiftUI `Text` / `Label` / `Button` / `navigationTitle` / `Section` / `Toggle` string literals resolve via `LocalizedStringKey`. Plain `String` surfaces that need a lookup use `String(localized:)` (e.g. Settings/Backup/Parental help captions, `HomeSectionId.label`, Add-mode / discovery ternaries, notification titles, charts help format string, Parental PIN Save/Unlock defaults).

**Covered (partial):**

- Tab bar + main navigation titles: Home, Inbox, Subscriptions, Queue, Downloads, Settings (+ About, Favorites, History, Archived, Episodes, Discover, Download errors, Home layout, Add podcast, Transcript)
- Settings section headers: Appearance, Home, Playback, Library, Privacy, About, Backup, Sync, Feeds / Keep updated, Auto-download, Network / Downloads, Notifications, Downloads / Storage, Discovery, App Store, Siri / Shortcuts, Homescreen widget, Apple Watch, CarPlay, Import / Export
- Discovery chrome: Add segmented modes (Apple / Index / fyyd / URL / Folder), **Add from Clipboard** (when pasteboard has http(s) URL), search placeholders, empty/API-key states, Results / Feed URL / charts loading + help, OPML import/export labels, Preview/Open row actions
- Primary actions: Play, Pause, Resume, Download, Download all, Subscribe / Confirm Subscribe, Cancel, Save, Delete, Remove, Archive, Mark played / unplayed, Mark all as played, Sort / Sort subscriptions / Sort episodes / Sort inbox / Sort downloads / Sort history / Sort favorites / Sort archived / Alphabetical A–Z / Newest first / Oldest first, common empty-state titles + main-tab and library empty descriptions (History / Favorites / Archived / Episodes / Tags filters)
- Home section labels (layout toggles + Home headers): Continue listening, New / Inbox, Queue, Discover, Recently updated, Favorites; Home search prompt + empty (Search home / No matching home items); Settings search prompt + empty (Search settings / No matching settings)
- Backup / Sync: section labels, primary Backup buttons, Sync form field labels (Host / Username / Password / Device / Login / Sync now), notification toggles
- Download errors: banner title, Errors list title/empty, clear confirmation
- Full player: Chapters / Transcript / Shownotes sheet titles + loading / unavailable / empty copy
- Local notifications: Download failed, Sync failed, “N new episodes”
- Settings footnotes / help captions: Playback (speed, skip, video-as-audio, volume adaptation, skip silence, Stereo to mono, keep screen on, continuous playback, playback source), Feeds / Keep updated, Auto-download, Network / Downloads, Notifications, Downloads / Storage, Discovery, Sync provider blurbs, Backup help + media captions, Home layout footer, App Store rating / Siri / Widget / Watch / CarPlay notes
- Appearance Theme: picker title / System·Light·Dark + help caption (EN/DE); VoiceOver label/value/hint on the Theme picker
- Per-feed settings Keep updated: picker title / Use global·Always·Never / help captions + Refresh-all footer (EN/DE); VoiceOver label/value/hint on the Keep updated picker
- Parental controls detail: enable/options help, PIN sheet copy, lock status, common PIN errors
- Statistics + Echo (Year in Review): navigation titles (already), time-range segmented labels (Week/Month/Year/All + full This week/…), empty / out-of-range states, totals/period section headers, row labels (played / in progress / listening time / favorites), top-podcasts footers, approximation + range footnotes, duration units (`%lldh %lldm` / Min. / s), feed subtitles, Echo ShareLink text
- Homescreen Widget UI: configuration display name + description, Continue listening label, empty “Open AntennaPod to continue”, placeholder episode/podcast titles (`AntennaPodWidget/Localizable.xcstrings`)
- Apple Watch companion UI: Continue listening, Play / Open on iPhone, empty state, status (“Opening…” / “Playing…”), honest-limits footnote (`AntennaPodWatch/Localizable.xcstrings`)

**Widget / Watch (per-target catalogs):** Separate `Localizable.xcstrings` under `AntennaPodWidget/` (5 keys) and `AntennaPodWatch/` (8 keys) — EN source + DE. Intentionally **duplicated** minimal keys (not the main app catalog) so App Group / multi-target wiring stays simple; XcodeGen already compiles each target’s sources folder (no `project.yml` source change). SwiftUI `Text`/`Label`/`navigationTitle` / WidgetKit `configurationDisplayName`/`description` resolve via catalog; Watch status strings use `String(localized:)`.

**Still English (honest):** OS/`localizedDescription` network errors, many secondary accessibility hints, and DEBUG preview sample episode titles. Regenerating XcodeGen on a Mac picks up catalogs + regions; device/simulator language German shows translated keys when present.

## Accessibility (VoiceOver, beta polish)

VoiceOver-oriented polish on the existing beta UI (not a full accessibility audit / Dynamic Type pass):

- **EpisodeRow** — combined `accessibilityLabel` (title, feed, relative/absolute publish date when known, duration when known, played / **N percent played** + remaining or position-only when in-progress, downloaded, favorite, archived) with `.isStaticText`; thin ProgressView for started-not-finished (bar `accessibilityHidden`; included in combined label); icon-only Play / Download / Queue / Mark played / Favorite / Archive / Share buttons get explicit localized labels (+ `.startsMediaSession` on Play).
- **Mini + full player** — play/pause, rewind/forward (interval seconds), speed (tap cycles presets; long-press full menu), sleep timer (VoiceOver **Sleep timer, N minutes remaining** / end of episode when active), and scrubber / progress (value + hint). Secondary full-player actions labeled like EpisodeRow; **Queue actions** menu is state-aware (In queue / Not in queue + Add/Remove / Play Next).
- **Main tabs** — VoiceOver names from `Label` titles in `RootTabView` (String Catalog en+de).
- **Settings toggles** — bindings unchanged; short `accessibilityHint` on playback / network / notification / storage / rating toggles where the on-screen caption is long.
- **Appearance Theme** — picker VoiceOver label/value/hint (System follows iOS; Light/Dark force mode; no custom accents).
- **Per-feed Keep updated** — picker VoiceOver label/value/hint (Never → Refresh all / automatic refresh skip; manual single-podcast refresh still OK).

Honest limits: not every screen/control audited; no custom rotor / reduce-motion work in this pass.

## Queue

**Queue** tab lists enqueued episodes (JSON under Application Support). **Tab badge** = `PodcastStore.queue.count` (**full** queue length; **not** chip/search filtered; hidden when 0; system VoiceOver). Swipe trailing **Remove** (**always** `confirmationDialog` with episode title; `removeFromQueue` only after confirm — queue entry only; does not delete download, mark played, or stop playback), leading **Archive**. **Edit** enables drag reorder via `PodcastStore.moveQueue(from:to:)` (persists with `queue.json`). **Queue lock** (toolbar Lock/Unlock with `lock.fill` / `lock.open`, same preference as **Settings → Queue → Lock queue**; `AppSettings.queueLocked` / UserDefaults, default **off**, included in iOS JSON backup) disables **Edit / `.onMove` drag reorder**, **Shuffle**, and hides EpisodeRow **Move to top / Move to bottom**. **Honest:** lock is **reorder-only** — Enqueue (incl. Inbox / Favorites / Downloads / History / Archived / All Episodes / Feed detail **Add all to queue**), Play Next, Remove, Archive swipe, and Clear queue **keep working** (mirrors Android `prefQueueLocked` / queue lock; does not block add/remove). **Remaining time** info bar (under filter chips, AntennaPod-like): `N episodes • Hh Mm left` via `StatisticsView.formatDuration`. Sums **`max(0, duration − position)`** over the **visible** chip + search filtered list (not the full queue when filtering). Duration from feed / saved playback / live player when current; unplayed with known duration → full length; **played** (not current) → 0 (mark-played clears position); **unknown duration skipped** — prefix `~` when any episode omitted; count-only when all unknown (never invents time). Wall-clock only (does **not** divide by playback speed). Updates when queue, playback progress, or filter changes. EN/DE + VoiceOver. **Filter chips** (**All** default / **Unplayed** / **Played** via `PodcastStore.isPlayed`; archive ignored — same honesty as Downloads; pref `AppSettings.queueFilter` / UserDefaults, included in iOS JSON backup). Pipeline: chip → **Search** (`.searchable`, ~250 ms debounce by episode title and/or feed title); empty query shows the chip-filtered queue; empty state when nothing matches. **Honest:** while a chip ≠ All **or** search is active **or** the queue is locked, **Edit is disabled and drag reorder is off** — filtered `onMove` indices would not map to the persisted queue; lock turns off manual reorder by design. **Move to top / Move to bottom** stay available when unlocked (they use episode id → full-queue indices, not filtered IndexSets). **Shuffle** (toolbar ⋯ → **Shuffle**) **always** shows a `confirmationDialog` then `PodcastStore.shuffleQueue()` — Fisher–Yates on the **full** persisted queue (not chip/search); persists via `queue` didSet like `moveQueue`; **blocked when locked** (same reorder-only gate as Edit); disabled when `queue.count` < 2; does not stop playback / change progress / mark played / delete downloads; currently playing **keeps the same episode id** and **moves with its new list index** (not pinned); continuous next still `nextQueueEpisode(after:)` by id. EN/DE + VoiceOver. **Clear queue** **always** shows a `confirmationDialog` (full `store.queue.count` + honest warning: does not stop playback, change progress, mark played, or delete downloads) before `clearQueue()`; the menu stays enabled whenever the queue is non-empty, even if the current chip/search shows no rows (and even when locked — Queue lock is reorder-only). With Settings **Continuous playback** on (default), finishing an episode advances with `nextQueueEpisode`; when off, playback stops without queue advance (progress / mark played still apply).

**Add to Queue** (`PodcastStore.enqueue`) appends if absent. **Remove from Queue** (`PodcastStore.removeFromQueue`) drops the episode from `queue.json` (same as Queue-tab swipe Remove / Full Player Remove — both **confirm** with episode title first; queue entry only — does not delete download, mark played, or stop playback). **`isInQueue`** is the read-side check. **Play Next** (`PodcastStore.playNext(_:currentlyPlayingId:)`) moves/inserts immediately after the currently playing queue item, or at the **head** when nothing is playing / the current episode is not in the queue — so auto-next after finish still hits that head item (honest: same as today’s append semantics when current is not queued). Entry points: EpisodeRow context menu, Feed detail swipe, Inbox swipe, Downloads swipe. **Full player** secondary uses a **Queue** menu (HStack was crowded): label shows Queue / In queue; menu offers **Add to queue** ↔ **Remove from queue** from `isInQueue` (**Remove** confirms with episode title; Add is immediate), plus **Play Next** when a simulated `playNext` would change order (hidden when already next). No second queue store.

**Move to top** / **Move to bottom** (`PodcastStore.moveQueueItemToTop` / `moveQueueItemToBottom`) reorder an episode that is **already in the queue** via the same `moveQueue(from:to:)` path as Edit drag reorder (one persistence source of truth → `queue.json`). **Literal** list ends: top = index **0**, bottom = last index — matching Android `queue.add(0, …)` / append, and **distinct from Play Next** (which inserts after the currently playing item). Shown on **EpisodeRow** context menu (Queue tab and any other list that reuses EpisodeRow) only when the episode is queued **and Queue lock is off**; **Move to top** is hidden when already first, **Move to bottom** when already last, both when not in queue or when locked. EN / DE + VoiceOver labels/hints. No second queue store.

## Library search

Local-only search over subscribed feeds and their episodes (title, feed title, feed description) — distinct from Apple Podcasts / iTunes discovery in Add podcast. **Inbox** uses `.searchable` with a short debounce (~250 ms): empty query keeps the unplayed Inbox (**remaining time** info bar over that sorted list); non-empty shows Podcasts + Episodes sections (remaining bar hidden — library hits ≠ Inbox list). Matching feeds navigate to `FeedDetailView`; episodes reuse `EpisodeRow` (play / download / queue / mark played). **Subscriptions** also filters the feed list via searchable. **Downloads**, **Queue**, **Favorites**, and **History** filter by episode title or feed title (same light debounce; empty query shows all under any chip filter). Downloads chips (**All** / **Unplayed** / **Played** via `isPlayed`; `downloadsFilter`) and Queue chips (**All** / **Unplayed** / **Played** via `isPlayed`; `queueFilter`) run before search; Downloads **Sort** (Newest/Oldest; download completion else pubDate), History **Sort** (Newest/Oldest; `lastPlayedAt` else `updatedAt`) + **remaining time** over that visible set (not Clear catalog; played→0), Favorites **Sort** (Newest/Oldest; favoritedAt) + **remaining time** over that visible set (not Clear catalog), All Episodes soft-cap→sort→chip→search + **remaining time** (never beyond newest 500), and Archived **Sort** (Newest/Oldest; archivedAt) + **remaining time** over that visible set (not Restore all catalog; archived≠played; played→0) apply to their filtered sets. Queue disables Edit/reorder while chip/search filtering (Move to top/bottom stay id-based when unlocked). Empty states when nothing matches. Downloads toolbar **Add all to queue** confirms with the **eligible** count (full `DownloadService.downloads` catalog minus already queued — **not** chip/search), then `enqueueAllDownloads()` appends via `enqueue` in **catalog order** (oldest completed first; not UI `downloadsSort`). Already queued skipped; **Queue lock does not block**. Disabled when eligible == 0. Downloads toolbar **Delete played downloads** confirms with the **global** count (and size) of played offline files — not the visible chip/search subset — then deletes each via `DownloadService.delete` — skips favorites (matches auto-delete), keeps unplayed downloads / played flags / queue; disabled when none eligible globally. Not the same as Settings **Clear downloads**. **Feed detail** filter chips All / Unplayed / Played + search by episode title + **remaining time** over that visible set (sort preserved; bulk Download all / Mark all played / Add all to queue stay full-feed — Add all = full catalog minus queued, newest-pubDate-first; Queue lock does not block).

## History

**Subscriptions → Library → History** (no extra root tab). Lists episodes that are marked played or have progress (`positionSeconds > 1`). **Honesty:** there is **no separate `history.json`** — History is derived from Application Support `playback.json` (`playbackStates` with `belongsInHistory`). **Sort** toolbar — **Newest first** (default) / **Oldest first** by `HistoryEpisode.lastPlayedAtEpochMs` (**sort key honesty:** `playbackStates.lastPlayedAtEpochMs`, else `updatedAtEpochMs` — same value shown as the row’s “Last played” date; older `playback.json` without `lastPlayedAt` migrates from `updatedAt` when played/in-progress). Preference `AppSettings.historySort` (UserDefaults + JSON backup). Stable tiebreaker episode `id`. Client-side re-sort in HistoryView only — `PodcastStore.historyEpisodes` stays newest-first for Home Continue / Clear history counts. Sort applies to the `.searchable` filtered set. **History size** (Settings → Library): **50 / 100 / 200 / 500 / Unlimited** (default **Unlimited**). Pref `AppSettings.historySizeLimit` (UserDefaults + JSON backup). When finite, `PodcastStore.trimHistoryToSizeLimitIfNeeded()` drops the oldest History-listed entries (lowest `lastPlayedAt` else `updatedAt` — end of the newest-first catalog) on append (`saveProgress` / `markPlayed` / `touchLastPlayed`), after load (launch once settings are wired + `reloadFromPersistence`), and when the Settings picker changes — same as per-row Remove (progress + `isPlayed` + `lastPlayedAt` gone). Favorites, archive, downloads, and queue stay; Statistics / Echo / Continue listening may lose trimmed episodes. History list shows a footnote when the cap is finite. Rows show feed title and a relative last-played date; tap actions reuse `EpisodeRow` (play / download / queue / mark played / favorite). Swipe trailing **Remove** clears that episode’s playback state (leaves the feed row). Swipe leading **Mark unplayed** when played (episode drops out of History if there is no remaining progress). **Search** (`.searchable`, ~250 ms debounce) filters by episode title and/or feed title; empty query shows the full list; empty state when nothing matches. **Remaining time** info bar (`N episodes • Hh Mm left`) sums `max(0, duration − position)` over the **visible** sort + search filtered list (**not** the full history catalog used by Clear history); unknown durations omitted (`~`); live position for the current episode; wall-clock only (no speed); **played** (not current) → 0 — History is mostly played/in-progress so totals may often be low (correct; still useful for in-progress); respects history size limit catalog as-is. Toolbar menu **Add all to queue** confirms with the **eligible** count (full `historyEpisodes` catalog minus already queued — **not** the searchable filtered subset), then `enqueueAllHistory()` appends via `enqueue` in **newest-lastPlayed-first store order** (not UI `historySort`). Already queued ids are skipped. **Queue lock does not block** (reorder-only). Disabled when eligible == 0 (or history empty). Toolbar menu **Clear history** confirms with the **full** history count (`items.count` / `store.historyEpisodes`), then `clearHistory()` drops the whole `playbackStates` entry for every listed episode — same honesty as per-row Remove (progress + `isPlayed` + `lastPlayedAt` gone; feed rows, downloads, queue, and favorites stay). Clear stays enabled whenever history is non-empty, even if the current filter shows no rows. Disabled when empty. Root tabs stay at six (Home first).

## Statistics

**Subscriptions → Library → Statistics** (also **Settings → Library → Statistics**). Derived from existing `playback.json` — no separate cumulative `listenedSeconds` counter in this beta.

- **Time range** — segmented **This week / This month / This year / All time** (default). Pref `AppSettings.statisticsTimeRange` (UserDefaults + JSON backup); **shared with Echo**. Device calendar (`Calendar.current`). Filter key: `lastPlayedAtEpochMs` else `updatedAtEpochMs` (same honesty as History / Echo). **Coarse episode-level stamps** — not per-session listen windows; an episode last touched in-range counts its full estimate for that range.
- **Played episodes** — count of episodes with `isPlayed` in range.
- **In progress** — episodes with progress (`positionSeconds > 1`) that are not marked played (shown when non-zero), in range.
- **Approx. listening time** — sum of estimates: **played** use saved `durationSeconds` (position is cleared on mark-played); **in-progress** use `positionSeconds`. Footnote on screen: does **not** count rewinds, speed, or re-listens.
- **Top podcasts** — per-feed rollup sorted by approximate time, then play count.

Empty state when there is no played / in-progress playback data; distinct copy when All time has data but the selected range does not.

## Echo (Year in Review)

**Subscriptions → Library → Echo** (also **Settings → Library → Echo**). Beta lite listening summary with the **same time-range picker** as Statistics (`statisticsTimeRange`; default **All time**; choose **This year** for classic year-in-review). Device `Calendar.current` (Europe/Berlin when the device is set that way).

- **Played episodes** — `isPlayed` with `lastPlayedAt` (else `updatedAt`) in the selected range.
- **Approx. listening time** — same estimate as Statistics (played → saved duration).
- **Top podcasts** — per-feed rollup for that range (up to 10).
- **Favorites** — count starred in range from `favorites.json` (plus total if different).
- **Share** — toolbar `ShareLink` with a plain-text summary when there is data (title adapts to range).

Honest empty / out-of-range states. Footnote: approximate — same limits as Statistics (no rewinds / speed / re-listens; coarse episode stamps; derived from `playback.json`).

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
- **Localization:** `AntennaPodWidget/Localizable.xcstrings` (en+de; per-target, not shared with main app).
- **Honest limits:** snapshot **may be stale** (not live Now Playing); **no scrubber / transport** on the widget; requires App Group entitlement + codesigning for the extension to install; add the widget manually from the home screen.

Shared Codable helpers live in `ios/Shared/WidgetContinueSnapshot.swift` (compiled into app, widget, and Watch targets).

## Apple Watch companion (beta lite)

**watchOS** app target (`AntennaPodWatch`, XcodeGen, watchOS 10+, `WKCompanionAppBundleIdentifier` → `de.danoeh.antennapod.ios`) shows **Continue listening**: episode title + feed name.

- **Snapshot source:** same Codable payload / key as the Homescreen Widget (`group.de.danoeh.antennapod.ios` / `widget.continueListening.snapshot.v1`). Because App Group containers are **per-device**, the iPhone pushes snapshot bytes to the Watch via **Watch Connectivity** `updateApplicationContext` (`WatchCompanionBridge` on save / activate). Watch also tries App Group `UserDefaults` as a local fallback (usually empty).
- **Play / Open on iPhone:** Watch Connectivity `sendMessage` / `transferUserInfo` with action `play` → iPhone `PlaybackDeepLinkRouter` (`antennapod://play`). Best-effort fallback: `WKApplication.openSystemURL(antennapod://play)` (custom schemes are less reliable than WC).
- **Empty:** “Open AntennaPod on iPhone to continue”.
- **Localization:** `AntennaPodWatch/Localizable.xcstrings` (en+de; per-target, not shared with main app).
- **Honest limits:** **no** independent Watch audio playback, **no** download management, **no** full queue UI. When the phone is already playing, use **system Now Playing** controls on the Watch. Snapshot may be stale until WC delivers. Requires Dev Team + App Group capability for device install.

## Swipe actions

Consistent list swipes (EpisodeRow icon buttons remain for play / download / queue / mark / favorite / archive / share):

| Screen | Leading | Trailing | Extra |
|--------|---------|----------|-------|
| Subscriptions | Refresh (per feed) | Unsubscribe (confirm) | Toolbar **Refresh all** + list pull-to-refresh → `refreshAllFeeds()` (disabled while `isLoading` / empty). Destructive Unsubscribe confirm shows podcast title; keeps downloads; no full-swipe |
| Queue | Archive | Remove from queue (**confirm** + title; queue only) | remaining time info bar (visible filtered list); filter chips All / Unplayed / Played (`queueFilter`); Edit → drag reorder (`moveQueue`) when All + empty search and unlocked; EpisodeRow context **Move to top** / **Move to bottom** (queued only; hide if first/last/locked; id-based OK while filtering); toolbar **Lock queue** / **Unlock queue**; `.searchable` title/feed; toolbar **Shuffle** (confirm; full queue; blocked when locked; disabled if <2; current playing moves with id); toolbar Clear queue (always confirm, full queue count + honesty; works when locked) |
| Downloads | — | Play Next + Add to queue + Delete download (**confirm** + title; local file only) | remaining time info bar (visible filtered list); filter chips All / Unplayed / Played (`downloadsFilter`); Sort; `.searchable`; toolbar **Add all to queue** (confirm, full catalog eligible) + Delete played (global) |
| Inbox | Mark played | Play Next + Add to queue + Archive | remaining time info bar (visible sorted Inbox list; hidden during library search); toolbar menu: **Add all to queue** (confirm, full Inbox eligible) + Mark all as played (confirm) + Archive all |
| Feed detail | Mark played / unplayed + Archive / Restore | Play Next + Queue + Share | remaining time info bar (visible sort→chip→search list; not bulk eligibility); filter chips All / Unplayed / Played + `.searchable` episode title; toolbar Download all + Mark all as played + **Add all to queue** (confirm, full-feed catalog minus queued; newest-pubDate-first; OK when Queue locked) + **Unsubscribe** (destructive confirm + dismiss) + EpisodeRow context: Play Next + Add to queue + Move to top/bottom (when queued) + Mark played/unplayed |
| History | Mark unplayed (if played) | Remove playback state | remaining time info bar (visible sort+search list; played→0); `.searchable` title/feed; toolbar **Add all to queue** (confirm, full History eligible) + Clear history (confirm, full list) |
| Favorites | Archive | Unfavorite | remaining time info bar (visible sort+search list); `.searchable` title/feed; toolbar **Add all to queue** (confirm, full Favorites eligible) + Clear favorites (confirm, full list) |
| Archived | — | Restore | remaining time info bar (visible sort+search list; archived≠played; played→0); `.searchable` title/feed; toolbar Sort Newest/Oldest; toolbar **Add all to queue** (confirm, full Archived eligible) + Restore all (confirm, full list) |
| All Episodes | Mark played / unplayed | Archive / Restore | remaining time info bar (visible soft-capped+filtered list; never beyond newest 500); toolbar **Add all to queue** (confirm, soft-capped newest-500 eligible) |

## Favorites

**Subscriptions → Library → Favorites** (no extra root tab; optional Home preview via **Settings → Home layout**, off by default). Starred episode IDs live in Application Support `favorites.json` (episode id → `favoritedAtEpochMs`), independent of `playback.json` so clearing History does not unstar. Toggle from **EpisodeRow** (star icon) or the **full player** secondary actions. Toolbar **Sort** — **Newest first** (default) / **Oldest first** by favorited-at (`AppSettings.favoritesSort`); swipe **Unfavorite** + **Archive**. **Remaining time** info bar (`N episodes • Hh Mm left`) sums `max(0, duration − position)` over the **visible** sort + search filtered list (**not** the full favorites catalog used by Clear favorites); unknown durations omitted (`~`); live position for the current episode; wall-clock only (no speed). **Search** (`.searchable`, ~250 ms debounce) filters by episode title and/or feed title; empty query shows the full list under the current sort; empty state when nothing matches. Toolbar menu **Add all to queue** confirms with the **eligible** count (full `favoriteEpisodes` catalog minus already queued — **not** the searchable filtered subset), then `enqueueAllFavorites()` appends via `enqueue` in **newest-favorited-first store order** (not UI `favoritesSort`). Already queued ids are skipped. **Queue lock does not block** (reorder-only). Disabled when eligible == 0 (or favorites empty). Toolbar menu **Clear favorites** confirms with the **full** favorites count (`items.count` / `store.favoriteEpisodes`), then `clearFavorites()` clears the whole `favoriteAtById` side map — same honesty as per-row Unfavorite (downloads, archive, played state, and queue stay; no auto-delete on unfavorite). Clear stays enabled whenever favorites are non-empty, even if the current filter shows no rows. Disabled when empty. When **Delete episode after playing** is on, auto-delete **skips** favorited episodes (keeps the offline file). Unsubscribing a feed clears that feed’s favorite entries.

## Archive / restore

**Subscriptions → Library → Archived** (no extra root tab). Archived episode IDs live in Application Support `archived.json` (episode id → `archivedAtEpochMs`), independent of played status (`playback.json`). Archive **hides** episodes from **Inbox** and the Home **New / Inbox** preview without marking them played (queue rows stay unless you Remove). **Feed** episode lists still show archived items (dimmed + archivebox badge). Toggle from the **full player** secondary actions (Archive when not archived; Restore when archived — same `PodcastStore.toggleArchived` / `archived.json` as lists; hidden when nothing is playing), **EpisodeRow** (button + context menu), **Feed detail** leading swipe, **Inbox** trailing swipe, or Inbox toolbar menu **Archive all** / **Mark all as played**. Library → Archived toolbar **Sort** — **Newest first** (default) / **Oldest first** by archived-at (`AppSettings.archivedSort`); swipe **Restore**. **Search** (`.searchable`, ~250 ms debounce) filters by episode title and/or feed title; empty query shows the full list under the current sort; empty state when nothing matches. **Remaining time** info bar (`N episodes • Hh Mm left`) sums `max(0, duration − position)` over the **visible** sort + search filtered list (**not** the full archived catalog used by Restore all); unknown durations omitted (`~`); live position for the current episode; wall-clock only (no speed); **archived ≠ played** — normal duration−position rules; **played** (not current) → 0. Toolbar menu **Add all to queue** confirms with the **eligible** count (full `archivedEpisodes` catalog minus already queued — **not** the searchable filtered subset), then `enqueueAllArchived()` appends via `enqueue` in **newest-archived-first store order** (not UI `archivedSort`). Already queued ids are skipped. Does **not** restore or unarchive (archive side map unchanged). **Queue lock does not block** (reorder-only). Disabled when eligible == 0 (or archived empty). Toolbar menu **Restore all** confirms with the **full** archived count (`items.count` / `store.archivedEpisodes`), then `restoreAllArchived()` clears the whole `archivedAtById` side map — same honesty as per-row Restore (does **not** mark unplayed or delete downloads; played status, queue, and favorites stay). Restore stays enabled whenever archived is non-empty, even if the current filter shows no rows. Disabled when empty. Unsubscribing a feed clears that feed’s archive entries.

## Episodes (All)

**Subscriptions → Library → Episodes** (no extra root tab). Flat list of episodes from every subscription, showing feed title; rows reuse `EpisodeRow` (play / download / queue / mark / favorite / archive / share).

**Soft limit: newest 500** episodes (`PodcastStore.allEpisodes`) — not lazy-paged yet. Toolbar **Sort** — **Newest first** (default) / **Oldest first** by `pubDateEpochMs` (`AppSettings.allEpisodesSort`, UserDefaults + JSON backup). Missing dates sort last; stable tiebreaker episode `id`. **Soft-cap honesty:** the store already returns the newest-500; **Oldest first only reorders within that capped set** and does **not** pull older episodes from beyond the soft limit. **Filter chips** (Subscriptions-style capsules): **All** (default) / **Unplayed** / **Downloaded** / **Favorites**. Pipeline: soft cap → sort → chip → `.searchable` (title or podcast name) so filters never surface older episodes beyond the soft limit. **Remaining time** info bar (`N episodes • Hh Mm left`) sums `max(0, duration − position)` over that **same visible** soft-capped → sort → chip → search set — **never claims remaining beyond the newest-500 soft cap**; unknown durations omitted (`~`); live position for the current episode; wall-clock only (no speed). **Unplayed** = `!isPlayed` && not archived (Inbox spirit, still within All Episodes). **Downloaded** = local file via `DownloadService.isDownloaded`. **Favorites** = starred via `PodcastStore.isFavorite` (`favorites.json`), still within the capped set (not the full Library → Favorites list). Chip + sort persist in `AppSettings` (UserDefaults + iOS JSON backup). Empty state when the filter/search matches nothing. Chip VoiceOver: localized label + “Filters the All Episodes list” hint + selected trait; Sort VoiceOver: “Sort all episodes”. Toolbar menu **Add all to queue** confirms with the **eligible** count (soft-capped `allEpisodes` newest-**500** minus already queued — **not** the chip or searchable filtered subset), then `enqueueAllEpisodes()` appends via `enqueue` in **newest-pubDate-first store order within the soft cap** (not UI `allEpisodesSort`). Already queued ids are skipped. **Soft-cap honesty:** never enqueues beyond the newest-500 set. **Queue lock does not block** (reorder-only). Disabled when eligible == 0 (or catalog empty). Distinct from **Inbox** (unplayed-only, uncapped by this soft limit) and from **Library → Favorites** (uncapped starred list, newest-favorited first). Root tabs stay at six (Home first).

## Share

Share an **episode** or a **podcast** via the **system share sheet** only (`ShareLink` / `UIActivityViewController`). There is **no AntennaPod deep link**, no in-app social posting, and **no fake gPodder share** — recipients get a real title + URL they can open in a browser or player.

**Episode payload:** subject = episode title; message = `Title — Podcast` when the feed title is known (else title alone). **URL precedence** (first network URL wins; never invents a URL):

1. Episode page / `link`
2. Media enclosure / `downloadUrl`
3. Feed homepage / `siteLink`
4. Feed RSS / `feedUrl`

`file://` and `local-folder://` URLs are omitted. Share is **hidden or disabled** when nothing shareable is available.

**Share with position:** second action on the **full player** (and **Shownotes** toolbar when the shownotes episode is the **current playback item**). Same URL precedence; message appends a human-readable timestamp from `PlaybackService.positionSeconds` — e.g. `Title — Podcast (12:34)` (`m:ss` / `h:mm:ss`, same as the scrubber). **Text timestamp only** — does **not** invent AntennaPod deep links or append `#t=` media fragments. Hidden when position is unknown or the episode is not current (list rows keep plain Share only).

**Entry points:** full player secondary Share + Share with position; **Shownotes** sheet toolbar (Share + position when current); EpisodeRow button + context menu; Feed detail trailing swipe Share. **Feed detail** toolbar shares the **podcast** (title + feed URL); the ⋯ **Feed actions** menu also offers **Open podcast website** (http(s) `siteLink` → system browser; hidden when missing) and **Copy feed URL** (`UIPasteboard.general` + brief **Copied** alert / haptic). Local-folder feeds disable Copy / podcast Share — no network RSS URL. See also **Copy episode link** (webpage only) under Open episode website and **Open podcast website** (`siteLink`).

## Open episode website

Opens the episode’s real webpage (`PodcastEpisode.link`) in the **system browser** (Safari / default) via SwiftUI `openURL` — **not** an in-app WebView, and **not** the enclosure / media URL.

- **URL rule:** only non-empty `http` / `https` `episode.link`. No fallback to `downloadUrl`, feed `siteLink`, or feed RSS (those are share / podcast-site concerns). Never invents a URL.
- **Hidden** when no usable link (do not show a disabled control that implies a website exists).
- **Entry points:** full player secondary actions; **Shownotes** sheet toolbar (safari icon); EpisodeRow context menu.
- EN / DE + VoiceOver label **Open episode website** and hint **Opens the episode webpage in the system browser**.

## Open podcast website

Opens the podcast’s homepage (`PodcastFeed.siteLink`) in the **system browser** (Safari / default) via SwiftUI `openURL` — **not** an in-app WebView, and **not** the feed RSS / subscription URL.

- **URL rule:** only non-empty `http` / `https` `feed.siteLink` (`PodcastFeed.websiteURL`). **No** fallback to `feedUrl` / RSS. Never invents a URL.
- **Hidden** when missing or non-http(s) (do not show a disabled control that implies a website exists).
- **Distinct from** in-app **Open podcast** (full/mini player → Subscriptions → Feed detail) and from **Open episode website** (episode `link`).
- **Entry points:** Feed detail ⋯ **Feed actions** menu; Subscriptions row context menu.
- EN / DE + VoiceOver label **Open podcast website** / **Podcast-Website öffnen** and hint **Opens the podcast webpage in the system browser**.

## Copy episode link

Copies the episode webpage URL (`PodcastEpisode.websiteURL` / `link` http(s) only) to the pasteboard — same confirmation pattern as **Copy feed URL** (`UIPasteboard.general` + brief **Copied** alert + success haptic).

- **URL rule:** webpage `link` only. Does **not** silently copy enclosure / `downloadUrl` as “episode link”. Never invents a URL.
- Optional separate action **Copy media URL** (`PodcastEpisode.mediaURL` — enclosure `downloadUrl` http/https only), clearly labeled so it is not confused with the webpage link.
- **Hidden** when no usable webpage link (media action shown independently when enclosure URL exists).
- **Entry points:** full player secondary; **Shownotes** toolbar (`doc.on.doc` / `link`); EpisodeRow context menu.
- EN / DE + VoiceOver labels/hints for both actions.

## Full player

Tap the mini player title or progress bar to open a full-screen sheet: feed artwork **or video surface**, episode title, podcast name, scrubber synced to `PlaybackService`, play/pause, rewind/fast-forward (Settings intervals), speed (**tap** cycles `0.8 / 1.0 / 1.1 / 1.2 / 1.3 / 1.5 / 2.0`, wrap; **long-press** keeps the full preset menu — same on mini player), sleep timer (same presets + Custom… 1–180 min as mini; mini also shows live remaining countdown / End of ep. on the moon control badge), plus **Play from beginning** / **mark played / unplayed** (`PodcastStore.isPlayed` / `togglePlayed` — same `playback.json` as lists; does **not** seek or stop playback; VoiceOver hints; hidden when nothing playing) / **favorite** (star toggle → `PodcastStore.toggleFavorite`; VoiceOver Add/Remove from favorites; hidden when nothing playing) / queue / download / **Open episode website** (when `episode.link` is http(s)) / **Copy episode link** / optional **Copy media URL** / share. Chevron dismisses back to the mini player. Prior tabs (Inbox, search, discovery, etc.) unchanged.

**Jump to position:** tap the left (current) time under the scrubber to open a medium sheet. Enter **mm:ss** / **h:mm:ss** (or a plain seconds integer) in the TextField, or use **minutes** + **seconds** steppers; **Jump** parses, clamps to `[0, duration]`, and calls `PlaybackService.seek(toSeconds:)`. Disabled when there is no episode or duration is unknown / zero.

**Play from beginning:** full-player secondary action restarts the **currently loaded** episode with a **seek to 0** on the same `AVPlayer` item (not a separate stream / re-download). If already playing → seek to 0 and keep playing; if paused → seek to 0 and play. Progress is persisted via existing `seek` → `saveProgress` only — it does **not** flip played/unplayed. EpisodeRow **context menu** offers the same for any list episode (`playFromBeginning(episode:)`): if that episode is current, seeks in place; otherwise loads it at position **0** (ignores saved resume; skip-intro is not applied on this explicit path). Hidden when the full player has nothing loaded.

## Playback speed preset cycle

Mini + full player speed control: **tap** advances to the next `AppSettings.speedPresets` value (`0.8, 1.0, 1.1, 1.2, 1.3, 1.5, 2.0`, wraps), AntennaPod-style. **Long-press** (Menu) still lists every preset for direct pick — finer control is not removed. Session rate uses existing `PlaybackService.setRate` / `cycleToNextSpeedPreset`; Settings **Default speed** and per-feed speed overrides are unchanged (same preset list).

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

## Stereo to mono (P3 lite / best-effort)

Settings → **Playback → Stereo to mono**. Default **off**. Persisted in `AppSettings` / UserDefaults (`stereoToMonoEnabled`) and included in iOS JSON backup.

When **on**, `PlaybackService` calls `AVAudioSession.setPreferredOutputNumberOfChannels(1)` after configuring category/mode (on play and live via `applyAudioSessionConfiguration`). When **off**, requests up to **2** channels (or the route maximum). Keeps stock `AVPlayer` — video surface, Picture in Picture, and Now Playing stay intact (no `AVAudioEngine` graph).

**Honest:** Best-effort **system preference** only. Many routes ignore preferred channel count (built-in speaker, some Bluetooth / CarPlay). This is **not** AntennaPod Android / ExoPlayer stereo→mono channel remix.

## Keep screen on (beta)

Settings → **Playback → Keep screen on**. Default **off** (battery-friendly). Persisted in `AppSettings` / UserDefaults and included in iOS JSON backup.

When **on** and playback is actively playing (`PlaybackService.isPlaying` or player rate > 0), sets `UIApplication.shared.isIdleTimerDisabled = true`. When paused, stopped, no episode, or the toggle is off, restores `isIdleTimerDisabled = false`. Updates from play/pause/stop/end paths and Settings changes (`RootTabView` / `applyIdleTimerPolicy()`).

**Honest limits:** Idle timer only — does **not** override Low Power Mode system behavior beyond that; no brightness hacks; Picture in Picture and background audio are unchanged.

## Continuous playback

Settings → **Playback → Continuous playback**. Default **on**. Persisted in `AppSettings` / UserDefaults (`continuousPlaybackEnabled`) and included in iOS JSON backup.

When **on**, `PlaybackService.handlePlaybackEnded` snapshots `PodcastStore.nextQueueEpisode(after:)` before mark-played removes the finished item, then starts that next Queue episode (same Play Next / head-of-queue semantics as before). When **off**, episode end still saves progress and marks played (smart-mark / natural end) but does **not** auto-advance — same stop teardown as when the Queue has no next item. **End-of-episode sleep timer** still stops without advancing regardless of this toggle.

## Show remaining time

Settings → **Playback → Show remaining time**. Default **off** (Android `pref_show_remain_time`). Persisted in `AppSettings` / UserDefaults (`showRemainingTime`) and included in iOS JSON backup.

When **on**, the mini player and full player show **remaining** time on the right (`−m:ss` / `−h:mm:ss` = duration − position) instead of total duration. The left label stays current position. Tapping the full-player right-hand time label toggles the setting (AntennaPod-style); Settings toggle is the primary control.

## Rewind after pause (beta)

Settings → **Playback → Rewind after pause**. Presets **Off (0) / 1 / 2 / 3 / 5 / 10** seconds; default **2**. Persisted in `AppSettings` / UserDefaults (`rewindAfterPauseSeconds`) and included in iOS JSON backup.

When resuming after a pause of the **current** item lasting at least **1 second**, `PlaybackService` seeks to `max(0, position − N)` (user pause, Lockscreen / remote, headset interruption resume, sleep-timer pause). **Does not** apply on first start / cold play from a row (`play(episode:)` clears `pausedAt`). Accidental pause/play under 1s does not rewind. **Honest:** fixed seconds — not Android `RewindAfterPauseUtils` graduated elapsed-time tiers (800ms / 3s / 10s / 20s by pause length).

## Smart mark as played

Settings → **Playback → Smart mark as played**. Presets **Off (0) / 15 / 30 / 60 / 120** seconds; default **30** (AntennaPod `prefSmartMarkAsPlayedSecs`). Persisted in `AppSettings` / UserDefaults (`smartMarkAsPlayedSeconds`) and included in iOS JSON backup.

When leaving, stopping, or switching episodes, `PlaybackService.finishCurrentEpisode(ended: false)` marks played if remaining time is within the threshold (`almostEnded`). **Off (0)** disables that near-end path — only natural end (`ended: true`) or an explicit mark-played action counts. Scrubbing near the end without leaving does not by itself mark played.

## Chapters

**Feed sources:** Parsed by the Swift `XMLParser` path (`NativeRssAtomParser`): Podlove Simple Chapters (`psc:chapter` / `sc:chapter` with `start`/`title`/`href`/`image`) on RSS items and Atom entries, plus Podcast Index `<podcast:chapters url="…">`. Remote Podcast Index JSON is fetched lazily when the full player opens if only a URL is present.

**Media-file tags (beta, local only):** When the episode is playing from a **local** file (downloaded or local-folder feed) and the feed provided **no** chapters, `MediaFileChapterReader` asks AVFoundation for QuickTime/MP4 chapter tracks (`AVAsset.loadChapterMetadataGroups(bestMatchingPreferredLanguages:)`). Titles come from common metadata title items. **Merge preference:** feed chapters win wholesale when non-empty; otherwise media chapters (`ChapterMerger.preferFeed`). No union-by-start-time / Android same-length field merge in this beta.

**Honest ID3 limits:** **ID3v2 CHAP** (typical MP3) and **Vorbis** chapter comments are **not** read — AVFoundation does not expose them as chapter groups on iOS, and this fork does not ship a custom ID3/Vorbis parser. Nero `chpl` only if AVFoundation surfaces it. Matrix documents the same.

Model: `PodcastChapter` (`title`, `startTimeSeconds`, optional `href`/`imageUrl`). Full player shows a chapter list (hidden when empty); tap seeks; the active chapter is highlighted from `PlaybackService.positionSeconds`.

**Current chapter title (Mini + Full player):** When the episode has chapters, `ChapterIndexing.currentIndex(in:at:)` resolves the chapter at `positionSeconds` (same indexing as Previous/Next). Mini player shows a truncated secondary line under the episode title; Full player shows the title under the podcast name (list highlight unchanged). Hidden when no chapters or the title is empty. Updates as position crosses boundaries (existing playback publishes). Mini uses store/player chapters only (no lazy remote/media fetch — open Full Player once to load/persist those). Tap on the mini title area still opens the Full Player (chapter list there). EN/DE VoiceOver includes the chapter title when present.

**Previous / Next chapter (Full player):** Shown only when the merged chapter list is non-empty (hidden otherwise). **Next** seeks to the start of the next chapter after the current position (`ChapterIndexing.nextSeekSeconds`; disabled on the last chapter). **Previous** uses an AntennaPod-like **2s** threshold (`ChapterIndexing.previousRestartThresholdSeconds`): if more than 2 seconds into the current chapter, seek to that chapter’s start; otherwise seek to the previous chapter’s start (or `0` on the first chapter). Lockscreen / Now Playing remotes stay configurable skip± intervals — not chapter-aware in this beta.

## Transcripts (beta)

**Only when the feed provides a URL** — no Whisper / on-device speech-to-text.

- **Parse:** `NativeRssAtomParser` reads Podcast Index `<podcast:transcript url|href type="…">`. When several tags exist, prefer **JSON > VTT > SRT** (same priority as Android `TranscriptType`). Stores `transcriptUrl` + `transcriptType` on `PodcastEpisode`.
- **Full player:** **Transcript** button appears when `hasTranscriptURL`. Opens a sheet that fetches the remote file (`TranscriptService`), best-effort parses JSON / WebVTT / SRT into timed cues (plain-text fallback if cues cannot be parsed). Tap a cue to **seek**; current cue highlight follows playback. Footer notes feed-URL-only honesty.
- **Cache:** in-memory map (small cap) plus light Caches/`transcripts/` JSON files for the session — not a durable offline library.

## Episode description / Shownotes (beta)

- **Parse:** `NativeRssAtomParser` stores item `description` / `summary` / `content` / `subtitle` (prefer longer; CDATA supported) as `PodcastEpisode.descriptionText`. Populated on subscribe / refresh (existing subscriptions need a refresh).
- **Full player:** **Shownotes** button opens a sheet with scrollable **plain text** (`HTMLTextStripping` — tags removed; not a rich HTML renderer). Empty state when missing / blank after strip. Toolbar: **Open episode website** (when `link` is http(s)) + **Copy episode link** + optional **Copy media URL** + Share.
- **Episode row:** context menu **Shownotes** (same sheet) + **Open episode website** / **Copy episode link** when link exists + **Copy media URL** when enclosure exists.
- **Search:** Feed detail + library episode hits also match `descriptionText` (raw feed text).


## Feed / podcast description (beta)

- **Parse:** `NativeRssAtomParser` already stores channel `description` / `subtitle` / `summary` as `PodcastFeed.descriptionText` (may contain HTML). Populated on subscribe / refresh — **existing subscriptions may need a feed refresh** if an older save lacked the field.
- **Feed detail:** toolbar **info.circle** opens a sheet with the podcast **title** and scrollable **plain text** (`HTMLTextStripping`). Button is **hidden** when the description is empty after strip (no invented copy). Sheet toolbar: **Open podcast website** when `siteLink` is http(s).
- **No author:** `PodcastFeed` has no `author` / `authorEmail` in this beta (discovery preview may still show a hint author from iTunes/Podcast Index — not used here).
- **Not** a rich HTML / AttributedString renderer.


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

Settings → **Feeds / Keep updated** offers refresh presets: Manual only, Every 1 / 4 / 12 / 24 hours (persisted in `AppSettings`). When not manual, opening the app (launch `.task` or returning to foreground via `scenePhase`) calls `PodcastStore.refreshAllFeeds()` if the interval elapsed since `lastFeedRefreshAt` (also stamped after manual Refresh all / Home+Inbox+Subscriptions pull-to-refresh). **Subscriptions** toolbar **Refresh all** (and list pull-to-refresh) call the same `refreshAllFeeds()` — ProgressView while `store.isLoading`, disabled when empty or in flight. Global interval still drives when auto refresh runs; per-feed **Keep updated → Never** skips that feed in `refreshAllFeeds` (single-feed refresh from Subscriptions swipe still works). Use global / Always both participate today. **BGAppRefreshTask is stubbed**: `Info.plist` only has `UIBackgroundModes` → `audio` (no `fetch`, no `BGTaskSchedulerPermittedIdentifiers`), so `FeedRefreshCoordinator` does not register a background task — enable later by adding those keys.


## New-episode action (Inbox / Queue)

Settings → **Feeds / Keep updated → New episodes**: **Inbox only** (default), **Add to Queue**, or **Add to Queue and download**. After a refresh finds **newly appeared** episode IDs on an **existing** subscription (not first subscribe), `NewEpisodeActionCoordinator` applies the action:

- **Inbox only** — no side effects; episodes still show in Inbox while unplayed (and not archived).
- **Add to Queue** — `PodcastStore.enqueue` (idempotent); Inbox unchanged as a derived list.
- **Add to Queue and download** — enqueue plus `DownloadService.download` (`.automatic`), gated by **Auto-download Wi‑Fi only** (`NetworkPathGate`). Separate global Auto-download (new-ID cap per feed) may also run afterward on the same newcomers.

**Per-feed** (Feed detail → gear): **Use global** / **Inbox only** / **Add to Queue**. Queue+download is global-only; a per-feed Queue override never forces download. **Honest beta:** simple global/per-feed choice — not Android’s full new-episode filter rules (KMP later).


## Auto-download

**Download all (Feed detail):** toolbar menu **Download all** with confirmation showing the eligible count. Eligible = unplayed, not archived, not already downloaded / in-flight, remote media URL (skips local-folder files). Soft cap **newest 50**. Enqueues via `DownloadService.downloadAllManual` (`.manual` path); honors **Manual download Wi‑Fi only** once up front — on block shows the same `lastError` / error-log feedback as a single manual download (banner on Feed detail). Does not download played/archived and does not wipe existing downloads.

**Mark all as played (Feed detail):** same toolbar menu, **Mark all as played** with confirmation showing the count of unplayed, non-archived episodes on **this podcast only**. On confirm calls `PodcastStore.markAllPlayed(inFeedId:)` → `markPlayed` per id (auto-delete-after-playing + queue removal still apply). Does **not** archive and does **not** touch other feeds. Disabled when count is 0.

**Add all to queue (Feed detail):** same toolbar menu, **Add all to queue** with confirmation showing the **eligible** count (full `feed.episodes` catalog minus already queued — **not** the chip or searchable filtered subset; same full-feed honesty as Download all / Mark all as played). On confirm calls `PodcastStore.enqueueAllFromFeed(_:)` → `enqueue` append in **newest-pubDate-first** order (explicit sort by `pubDateEpochMs`; missing dates last; title tiebreak — same spirit as Feed Download all; **not** UI `feedEpisodeSort`). Already queued ids are skipped. **Includes played and archived** (unlike Download all / Mark all eligibility). **Queue lock does not block** (reorder-only). Disabled when eligible == 0 (or feed has no episodes).

**Episode sort (Feed detail):** toolbar **Sort** menu — **Newest first** (default) or **Oldest first** by `pubDateEpochMs`. Global preference `AppSettings.feedEpisodeSort` (UserDefaults + JSON backup); **not** per-feed (simpler than Android’s per-podcast sort). Missing dates sort last. Applies only to the Feed detail episode list — **All Episodes** has its own `allEpisodesSort`; **Inbox** has its own `inboxSort`.

**Episode filter (Feed detail):** filter chips (**All** default / **Unplayed** / **Played**) mirroring Downloads / All Episodes chip UX. **Unplayed** matches All Episodes (`!isPlayed` && not archived). **Played** uses `PodcastStore.isPlayed` only (archived played still appear). Preference `AppSettings.feedEpisodeFilter` (UserDefaults + JSON backup; **global**, not per-feed). Pipeline: `feedEpisodeSort` → chip → `.searchable`. Empty state when chip/search matches nothing. **Remaining time** info bar (`N episodes • Hh Mm left`) sums `max(0, duration − position)` over that **same visible** sort → chip → search set — **not** full-feed / Download all / Mark all as played / Add all to queue eligibility; unknown durations omitted (`~`); live position for the current episode; wall-clock only (no speed). Chip VoiceOver: localized label + “Filters the Feed episodes list” hint + selected trait. Toolbar **Download all** / **Mark all as played** / **Add all to queue** stay **full-feed** (eligibility counts ignore the visible chip/search filter — same honesty as Downloads **Delete played downloads**).

**Inbox sort:** toolbar **Sort** menu — **Newest first** (default) or **Oldest first** by `pubDateEpochMs`. Preference `AppSettings.inboxSort` (UserDefaults + JSON backup). Missing dates sort last; stable tiebreaker is episode `id` (there is no `dateAdded` on `PodcastEpisode`). Client-side re-sort of `PodcastStore.inboxEpisodes` in the Inbox tab only — **Home New** preview stays newest-first. No new filters or multi-select.

**All Episodes sort:** toolbar **Sort** menu on Library → Episodes — **Newest first** (default) or **Oldest first** by `pubDateEpochMs`. Preference `AppSettings.allEpisodesSort` (UserDefaults + JSON backup). Missing dates sort last; stable tiebreaker is episode `id`. **Soft-cap honesty:** `PodcastStore.allEpisodes` already returns the newest-500 by pubDate; Oldest first only reorders within that capped set and does **not** surface older episodes beyond the soft limit. Pipeline: soft cap → `allEpisodesSort` → chip (`allEpisodesFilter`) → `.searchable`. Client-side re-sort in AllEpisodesView only — store catalog stays newest-first.

**Downloads sort:** toolbar **Sort** menu — **Newest first** (default) or **Oldest first**. Preference `AppSettings.downloadsSort` (UserDefaults + JSON backup). **Sort key honesty:** prefers stored download completion time (`DownloadedEpisode.downloadedAtEpochMs`, written when a download finishes; older catalog rows without the field are backfilled once from the offline file’s creation date, else content modification date, when available); otherwise falls back to episode `pubDateEpochMs`. Missing dates sort last; stable tiebreaker is episode `id`. Applies to the chip + `.searchable` filtered list as well. Does not change storage-limit eviction order (still file mtime / played-first).

**Downloads played filter:** filter chips (**All** default / **Unplayed** / **Played**) mirroring All Episodes chip UX. Uses `PodcastStore.isPlayed` on downloaded episodes (archive state is ignored here — Downloads is offline-file oriented). Preference `AppSettings.downloadsFilter` (UserDefaults + JSON backup). Pipeline: chip → `.searchable` → `downloadsSort`. Empty state when chip/search matches nothing. Chip VoiceOver: localized label + “Filters the Downloads list” hint + selected trait. **Add all to queue** stays **full-catalog** (eligible = completed downloads minus already queued; catalog order oldest completed first; not chip/search/`downloadsSort`; Queue lock does not block; disabled when eligible == 0). **Delete played downloads** stays **global** (full catalog played-eligible count/size; enabled whenever any eligible exist even if Unplayed chip shows an empty list). **Remaining time** info bar (under chips): same honesty as Queue — sums over the **visible** chip+search list only (**not** the tab-badge full catalog); unknowns skipped with `~`; wall-clock (no speed).

**Downloads file size:** custom Downloads rows show a compact **KB/MB/GB** size via `DownloadStorageUsage.formatBytes` / `ByteCountFormatter` when known. **Source honesty:** prefer the offline file’s on-disk `fileSize` (`DownloadedEpisode.localFileByteSize`); if the file is missing/unreadable, fall back to feed enclosure `PodcastEpisode.size` when > 0; **hide** when both unknown (never invent MB figures). VoiceOver includes localized **Size …**. Optional toolbar **status** shows the same folder total already measured for Settings (`DownloadService.storageUsage.usedFormatted` — Documents/downloads file count/bytes; VoiceOver **Total downloads size …**). Does not persist a separate size field in `downloads.json`.

**EpisodeRow enclosure/file size:** list captions (Feed detail, Inbox, Queue, All Episodes, History, Favorites, Archived, library search, Home previews — anywhere `EpisodeRow` is reused) append compact KB/MB/GB after date · duration when known (`date · duration · size`, omitting unknown parts). **Same source honesty as Downloads:** prefer on-disk size when a local offline copy exists (`DownloadedEpisode.knownByteSize` / `localURL` fileSize, including local-folder `file://`); else feed enclosure `PodcastEpisode.size` when > 0; **hide** when unknown. Reuses `DownloadStorageUsage.formatBytes`. VoiceOver EN/DE **Size …** (existing String Catalog key). No Settings toggle.

**Downloads remaining time:** info bar under filter chips (AntennaPod-like): `N episodes • Hh Mm left` via `StatisticsView.formatDuration`. Sums **`max(0, duration − position)`** over the **visible** chip + search filtered list (**not** the full offline catalog that drives the tab badge). Duration from feed / saved playback / live player when current; unplayed with known duration → full length; **played** (not current) → 0 (mark-played clears position); **unknown duration skipped** — prefix `~` when any episode omitted; count-only when all unknown (never invents time). Wall-clock only (does **not** divide by playback speed). Updates when downloads, playback progress, or filter changes. EN/DE + VoiceOver.

**Inbox remaining time:** info bar on the Inbox list (AntennaPod-like): `N episodes • Hh Mm left` via `StatisticsView.formatDuration`. Sums **`max(0, duration − position)`** over the **visible** sorted Inbox list (`inboxSort`). Duration from feed / saved playback / live player when current; unplayed with known duration → full length; **played** (not current) → 0 (Inbox is usually unplayed-only — still handled); **unknown duration skipped** — prefix `~` when any episode omitted; count-only when all unknown (never invents time). Wall-clock only (does **not** divide by playback speed). **Hidden while library search** is active (`.searchable` shows `LibrarySearchResultsView` — do not report full-Inbox / tab-badge totals over library hits). Updates when inbox, playback progress, or sort changes. EN/DE + VoiceOver.

**Favorites remaining time:** info bar on the Favorites list (AntennaPod-like): `N episodes • Hh Mm left` via `StatisticsView.formatDuration`. Sums **`max(0, duration − position)`** over the **visible** sort + searchable filtered list (**not** the full favorites catalog / Clear favorites count). Duration from feed / saved playback / live player when current; unplayed with known duration → full length; **played** (not current) → 0 (mark-played clears position); **unknown duration skipped** — prefix `~` when any episode omitted; count-only when all unknown (never invents time). Wall-clock only (does **not** divide by playback speed). Updates when favorites, playback progress, sort, or search changes. EN/DE + VoiceOver.

**All Episodes remaining time:** info bar on Library → Episodes under filter chips (AntennaPod-like): `N episodes • Hh Mm left` via `StatisticsView.formatDuration`. Sums **`max(0, duration − position)`** over the **visible** soft-capped → sort → chip → search filtered list. **Soft-cap honesty:** never claims remaining beyond the newest-500 set (Oldest only reorders within that cap). Duration from feed / saved playback / live player when current; unplayed with known duration → full length; **played** (not current) → 0 (mark-played clears position); **unknown duration skipped** — prefix `~` when any episode omitted; count-only when all unknown (never invents time). Wall-clock only (does **not** divide by playback speed). Updates when catalog, playback progress, sort, chip, or search changes. EN/DE + VoiceOver.

**History remaining time:** info bar on the History list (AntennaPod-like): `N episodes • Hh Mm left` via `StatisticsView.formatDuration`. Sums **`max(0, duration − position)`** over the **visible** sort + searchable filtered list (**not** the full history catalog / Clear history count). Respects history size limit catalog as-is (store-trimmed). Duration from feed / saved playback / live player when current; unplayed with known duration → full length; **played** (not current) → 0 (mark-played clears position — **History honesty:** mostly played/in-progress so totals may often be low; still useful for in-progress); **unknown duration skipped** — prefix `~` when any episode omitted; count-only when all unknown (never invents time). Wall-clock only (does **not** divide by playback speed). Updates when history, playback progress, sort, or search changes. EN/DE + VoiceOver.

**Feed remaining time:** info bar on Feed detail under filter chips (AntennaPod-like): `N episodes • Hh Mm left` via `StatisticsView.formatDuration`. Sums **`max(0, duration − position)`** over the **visible** sort → chip → searchable filtered list (**not** full-feed / **Download all** / **Mark all as played** / **Add all to queue** eligibility counts). Duration from feed / saved playback / live player when current; unplayed with known duration → full length; **played** (not current) → 0 (mark-played clears position); **unknown duration skipped** — prefix `~` when any episode omitted; count-only when all unknown (never invents time). Wall-clock only (does **not** divide by playback speed). Updates when feed episodes, playback progress, sort, chip, or search changes. EN/DE + VoiceOver.

**Archived remaining time:** info bar on the Archived list (AntennaPod-like): `N episodes • Hh Mm left` via `StatisticsView.formatDuration`. Sums **`max(0, duration − position)`** over the **visible** sort + searchable filtered list (**not** the full archived catalog / Restore all count). Duration from feed / saved playback / live player when current; unplayed with known duration → full length; **played** (not current) → 0 (mark-played clears position); **archived ≠ played** — archive alone does not zero remaining; **unknown duration skipped** — prefix `~` when any episode omitted; count-only when all unknown (never invents time). Wall-clock only (does **not** divide by playback speed). Updates when archived, playback progress, sort, or search changes. EN/DE + VoiceOver.

**Queue played filter:** filter chips (**All** default / **Unplayed** / **Played**) mirroring Downloads chip UX. Uses `PodcastStore.isPlayed` on queued episodes (archive ignored — queue can still hold archived items). Preference `AppSettings.queueFilter` (UserDefaults + JSON backup). Pipeline: chip → `.searchable`. Empty state when chip/search matches nothing. Chip VoiceOver: localized label + “Filters the Queue list” hint + selected trait. **Edit/`.onMove` disabled** while chip ≠ All or search active (same as search alone — filtered indices ≠ full queue). **Move to top/bottom** remain id-based when unlocked. **Shuffle** / **Clear queue** stay **full-queue** (Shuffle: unlocked + count ≥ 2 even while filtering; Clear: enabled whenever `store.queue` is non-empty even if Unplayed chip shows an empty list).

**History sort:** toolbar **Sort** menu — **Newest first** (default) or **Oldest first**. Preference `AppSettings.historySort` (UserDefaults + JSON backup). **Sort key honesty:** `HistoryEpisode.lastPlayedAtEpochMs` — `playbackStates.lastPlayedAtEpochMs`, else `updatedAtEpochMs` (same as the History row “Last played” date and the store catalog key). Stable tiebreaker episode `id`. Client-side re-sort in HistoryView only; `PodcastStore.historyEpisodes` stays newest-first for Home Continue / Clear history counts. Applies to the `.searchable` filtered list as well.

**History size limit:** Settings → Library **History size** — **50 / 100 / 200 / 500 / Unlimited** (default **Unlimited**). Preference `AppSettings.historySizeLimit` (UserDefaults + JSON backup). **Honesty:** no separate `history.json`; History is derived from `playback.json`. Finite caps call `trimHistoryToSizeLimitIfNeeded()` after history-growing writes, on load (settings wired), and when the picker changes — drops oldest History-listed `playbackStates` entries by `lastPlayedAt` else `updatedAt` (same as Remove from history). Favorites / archive / downloads / queue untouched; Statistics / Echo / Continue may lose trimmed episodes. History screen footnote when the cap is finite. EN/DE + VoiceOver.

**Favorites sort:** toolbar **Sort** menu — **Newest first** (default) or **Oldest first**. Preference `AppSettings.favoritesSort` (UserDefaults + JSON backup). **Sort key honesty:** `FavoriteEpisode.favoritedAtEpochMs` from `favoriteAtById` / `favorites.json` (same as the Favorites row “Favorited” date and the store catalog key). Stable tiebreaker episode `id`. Client-side re-sort in FavoritesView only; `PodcastStore.favoriteEpisodes` stays newest-first for Home Favorites preview / Clear favorites counts. Applies to the `.searchable` filtered list as well. No Title A–Z (parity with History / Inbox / Downloads).

**Archived sort:** toolbar **Sort** menu — **Newest first** (default) or **Oldest first**. Preference `AppSettings.archivedSort` (UserDefaults + JSON backup). **Sort key honesty:** `ArchivedEpisode.archivedAtEpochMs` from `archivedAtById` / `archived.json` (same as the Archived row “Archived” date and the store catalog key). Stable tiebreaker episode `id`. Client-side re-sort in ArchivedView only; `PodcastStore.archivedEpisodes` stays newest-first for Restore all counts. Applies to the `.searchable` filtered list as well. No Title A–Z (parity with Favorites / History / Inbox / Downloads).

**Search (Feed detail):** `.searchable` (~250 ms debounce) filters episodes by **title** and optional **`descriptionText`** after the chip filter. Empty query shows the chip-filtered list under the current sort; empty state when nothing matches. Swipes, Play Next, gear, sort menu, and filter chips stay available. Toolbar **Download all** / **Mark all as played** / **Add all to queue** confirmations still use **full-feed** eligibility counts (`downloadAllCandidates` / `markAllPlayedCandidates` / `enqueueAllFromFeedCandidatesCount` on the live feed), not the chip/search filtered subset — same honesty as Clear queue / Clear favorites / Restore all / Downloads Delete played. Add all appends newest-pubDate-first; Queue lock does not block.

Settings → **Auto-download**: global on/off (default **off**) and **Episodes per feed** cap (1 / 2 / 3 / 5, default 2 — **documented cap**). **Wi‑Fi only** for auto-download lives under **Network / Downloads** (default on; `NWPathMonitor` via `NetworkPathGate`). After a **successful** feed refresh that discovered newcomers (`refreshAllFeeds`, single-podcast refresh, Inbox pull-to-refresh, Keep updated), `AutoDownloadCoordinator` enqueues only those **newly appeared episode IDs** (not the whole unplayed backlog), newest-first per feed, unplayed / not archived / not already downloaded or in-flight, remote media URL, capped by the global episodes-per-feed setting, through `DownloadService.download` (`.automatic` skips the manual Wi‑Fi gate). **Local-folder / `file://` feeds and enclosures are skipped.** No separate silent BGAppRefresh download loop (BG fetch remains stubbed until Info.plist adds `fetch`). Storage-limit eviction after successful downloads is unchanged. **Per-feed** Auto-download (Use global / Always / Never) is on each podcast’s settings sheet (Feed detail → gear); Always enqueues new IDs even when global is off; Never skips that feed; episode cap and Wi‑Fi-only remain global.

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

- **Auto-download** — Use global / Always / Never; Always/Never beat the global Settings toggle; only newly appeared IDs after refresh; episode cap and Network / Downloads Wi‑Fi-only stay global; local-folder feeds skipped.
- **Keep updated** — Use global / Always / Never (default Use global). **Never** excludes the podcast from `refreshAllFeeds` (Subscriptions toolbar **Refresh all**, Home/Inbox pull-to-refresh, launch/foreground Keep updated interval). Use global / Always both refresh with the others. Manual single-podcast refresh (Subscriptions swipe / Feed detail) still works. EN/DE + VoiceOver on the picker; section footer notes Refresh all respects Never.
- **New episodes** — Use global / Inbox only / Add to Queue (Queue+download stays a global Settings choice).
- **Notify on new episodes** — Use global / Always / Never; Always/Never beat the global notification toggle (system permission still required).
- **Skip intro / Skip outro** — Use global / Off / 5 / 10 / 15 / 30 / 60 seconds (`nil` in the side map = Use global; explicit `0` = Off for this podcast). Same presets as Settings → Playback.
- **Playback speed** — Use global / 0.8× / 1.0× / 1.1× / 1.2× / 1.3× / 1.5× / 2.0× (`nil` = Use global). Applied when starting a fresh episode for this podcast.

Persisted as a side map keyed by stable `PodcastFeed.id` in Application Support `feed-settings.json` (survives feed refresh; cleared on unsubscribe). Reset to global defaults removes the map entry. `PlaybackService` resolves intro/outro/speed from the feed override when set, otherwise `AppSettings`.

The same sheet also manages **Tags / Folders** (see below).

## Local folder feeds (beta)

**Add podcast → Folder → Choose folder…** uses SwiftUI `fileImporter` (UIDocumentPicker) to pick a directory. A **security-scoped bookmark** is stored in Application Support `local-folder-bookmarks.json`.

**Synthetic feed:** `PodcastFeed` with `feedUrl` scheme `local-folder://{uuid}`. Episodes = audio files in that folder (**mp3 / m4a / aac / wav / flac**, non-recursive); **title** = filename without extension; `downloadUrl` = `file://…` so `DownloadService.localURL` / play treat them as **already local** (no network download).

**Refresh** (Subscriptions swipe or Keep-updated bulk) **re-scans** the folder via the bookmark. **Unsubscribe** deletes the bookmark and ends scoped access.

## Unsubscribe

**Subscriptions** trailing swipe and **Feed detail** ⋯ menu both open a destructive **Unsubscribe?** confirmation that includes the podcast title and an honesty line: removes the feed from Subscriptions, per-feed settings (`feed-settings.json`), tags (`feed-tags.json`), queue items from that feed, and favorites / archive / playback-history entries for its episodes; **downloaded files are kept** (Downloads catalog / offline media unchanged). Local-folder feeds also release the security-scoped bookmark. Confirm on Feed detail calls `PodcastStore.unsubscribe` then `dismiss()` so the detail pops. Swipe does **not** allow full-swipe (deliberate tap → confirm). Does **not** expand delete-downloads scope.


**Honest limits:** no RSS/Atom; no network feed refresh; not pushed to gpodder / Nextcloud; omitted from OPML and HTML export. Shown in **Subscriptions** with a **Folder** badge. Bookmarks in JSON backup may not work on another device — re-pick the folder after import.

## Tags / Folders

Organize subscriptions with simple string **tags** (Android-style folders, flat — no nested hierarchy in this beta).

- **Persistence:** Application Support `feed-tags.json` — map of feed id → `[String]` (0..n tags per feed) via `PodcastStore.tagsByFeedId` / `PodcastPersistence`. Survives feed refresh; cleared on unsubscribe. **No second tag store** — rename/delete update the same map.
- **Assign (per podcast):** Feed detail → **gear** (Per-feed settings) → Tags / Folders: add an existing tag or type a new name; swipe **Remove** (this podcast only). Context **Rename…** (global) or **Delete tag everywhere** (destructive **confirm**). Feed detail shows assigned tags when any exist (**Manage tags…** opens the same per-feed sheet).
- **Manage tags (global):** **Settings → Library → Manage tags** and **Subscriptions** toolbar (tag icon) → `ManageTagsView`: lists every in-use tag with **podcast counts**; **Rename** (alert; updates all feeds using that name via `PodcastStore.renameTag`); **Delete** (confirmation dialog; `deleteTag` strips the label from feeds — **does not unsubscribe** or delete downloads). Empty state explains how to add tags. EN/DE + VoiceOver labels/hints.
- **Subscriptions list:** when any tags exist, filter chips (**All** / each tag / **Untagged**) plus optional **Group by tag** (All only): sections per tag then Untagged; a podcast with several tags appears under each. With grouping off, tag names show as a subtitle on rows. Each row shows a trailing **unplayed badge** (`!isPlayed && !isArchived`, same spirit as Inbox / Feed detail Unplayed) when the count is > 0; VoiceOver includes the count. Counts come from one store pass over stored `feed.episodes` (not the All Episodes newest-500 soft cap; RSS window honesty applies).
- **Search:** `.searchable` (prompt **Search subscriptions**, ~250 ms debounce) filters by feed **title** and optional **`descriptionText`** (`PodcastStore.matchingFeeds`). Empty query shows the full list under the current sort; empty state when nothing matches (separate copy when only the tag filter empties the list). No `author` / `authorEmail` fields on `PodcastFeed` in this beta.
- **Sort:** toolbar menu (**Sort**) — **Recently updated** (default; newest episode `pubDateEpochMs`, same proxy as Home) or **Alphabetical A–Z** by feed title. Persisted in `AppSettings.subscriptionsSort` (+ JSON backup). Applied after search/tag filters; when grouping by tag, feeds inside each section use the same order. **Client-side only** — no drag-reorder of subscriptions in this beta.
- **Lifecycle:** tags exist only while assigned; removing the last use (or Delete on Manage tags) drops the name from `allTags`.

## Skip intervals (Rewind / Fast-forward)

Settings → **Playback → Rewind** / **Fast-forward**: presets **5 / 10 / 15 / 20 / 30 / 60** seconds (`AppSettings.rewindSeconds` / `fastForwardSeconds`, UserDefaults). Defaults match AntennaPod Android (`prefRewindSecs` = 10, `prefFastForwardSecs` = 30). Mini player, full player, and Lockscreen / Now Playing remote skip commands all use these values (SF Symbol icons update when a numbered glyph exists; 20s falls back to plain `gobackward` / `goforward`). Changing the pickers refreshes `MPRemoteCommandCenter` preferred intervals immediately.

## Skip intro / Skip outro

Settings → **Playback → Skip intro** / **Skip outro**: presets **0 / 5 / 10 / 15 / 30 / 60** seconds (`AppSettings.skipIntroSeconds` / `skipOutroSeconds`, UserDefaults; **0 = Off**). On a **fresh start** (resume position ≈ 0), playback seeks forward by skip-intro once per episode play session. When duration is known and **remaining ≤ skip-outro**, `PlaybackService` treats the episode as finished once (mark played + continuous queue next, same path as natural end) — guarded so it does not loop. Resume from mid-episode does not re-apply skip intro. **Per-feed override** (Feed detail → gear → Playback): Use global / Off / same presets; when set, that podcast’s episodes use the override instead of Settings.

## Prefer stream vs download

Settings → **Playback → Playback source**: **Prefer download** (local file via `DownloadService.localURL` when present), **Prefer stream** (always the episode network URL even if downloaded), or **Automatic** (default: local if the file exists, else stream). `PlaybackService.play` and continuous queue auto-next honor this; EpisodeRow / Downloads play buttons no longer force a local URL. Mini player and full player show a small **Local** / **Stream** indicator for the active item.

## Auto-delete after playing

Settings → **Downloads / Storage → Delete episode after playing** (default off, `AppSettings.autoDeleteAfterPlaying`). When an episode is marked played — manual toggle or playback finished / continuous auto-next (`PlaybackService` → `PodcastStore.markPlayed`) — if a local download exists, `DownloadService.delete` removes the offline file and catalog entry. The feed episode row and `isPlayed` status stay. Deletion is deferred while that episode is still the active player item **and** playing from a local file (`shouldBlockAutoDelete`); `PlaybackService` flushes the pending delete on end / stop / switch. **Favorited / starred episodes are skipped** (offline file kept). Starring while a delete is pending cancels it. Storage-limit eviction is unchanged.


## Notifications (new episodes)

Settings → **Notifications → Notify on new episodes** (default **off**). Uses `UserNotifications` **locally** only — no APNs / push server. Permission is requested when you enable the toggle, or on the first feed refresh that finds new episodes while the toggle is on and status is still undetermined. Settings shows Allowed / Denied / Not determined; if denied, the preference can stay on but no banners fire until iOS Settings allows Notifications (Open iOS Settings button). Per-feed **Notify on new episodes** (Use global / Always / Never) overrides the global toggle for that podcast. Feeds with Keep updated → Never are skipped by bulk refresh and therefore never contribute newcomers from Refresh all / interval refresh (single-feed refresh still can). After Inbox pull-to-refresh, Keep updated, or a single podcast refresh, newly appeared episode IDs (existing subscriptions only — not first subscribe) post **one aggregated** local notification per refresh (replaces prior banner): single feed → **title** = feed title, **body** = episode title or **“N new episodes”**; multiple feeds → **title** = “New episodes”, **body** = **“N new episodes”**. Tap opens the **Inbox** tab (best-effort; no episode-level deep link). Stable notification id `new-episodes.aggregate`.

## Download log / errors + notify on failures

Failed downloads are appended to a ring buffer (~50) in Application Support `download-errors.json` (episode id, title, feed title, message, timestamp). `DownloadService.lastError` still drives a red **Last download failed** banner on the **Downloads** tab (episode + feed when known). **Downloads → Errors** toolbar and **Settings → Notifications → Download errors** open the same simple list; **Clear** wipes the log and banner (offline files kept).

Settings → **Notifications → Notify on download errors** (default on) reuses the same `UNUserNotificationCenter` permission path as new-episode alerts. On failure (no media URL, HTTP error, move failure, or task error — not user cancel), if the toggle is on and permission allows, a **local** notification posts: **title** = episode title, **body** = short error. Tap opens the **Downloads** tab. **No push / APNs.**

Settings → **Notifications → Notify on sync errors** (default on) shares that same permission path. When gpodder.net / Nextcloud **login** or **sync** fails (`GpodderSyncService` records `lastSyncError`), a **local** notification posts: **title** = “Sync failed”, **body** = short error. Tap opens the **Settings** tab and scrolls to **Sync**. **No push / APNs.**

## Discovery

Add podcast sheet (**Subscriptions → +**) has four segments: **Apple**, **Index**, **fyyd**, and **URL**.

**Feed URL / Add by RSS** — Add podcast → **URL** tab: paste an RSS/Atom feed URL → **Preview feed** → Confirm Subscribe (same Preview pipeline as discovery). Already subscribed → **Open feed**.

**Add from Clipboard** — when the pasteboard holds a trimmed **http**/**https** URL with a host (first non-empty line only), Add podcast shows **Add from Clipboard** (toolbar on any Add mode + URL-tab section with the detected URL). Tap opens the **same** online Preview → Confirm Subscribe path (`FeedPreviewRequest` / `FeedRepository`); does **not** subscribe on launch or without a tap. Not OPML-from-clipboard. Non-http(s) pasteboard text hides the action. Preview/load errors surface on the Preview screen as usual.

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
