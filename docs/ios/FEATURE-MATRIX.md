# Feature-Matrix (Android → iOS)

Status: `todo` | `wip` | `done` | `n/a` (kein sinnvolles iOS-Äquivalent).  
Gewicht: 5 = P0 … 1 = P4. Details und Begründung: [PLAN.md](PLAN.md).

Stand abgeleitet aus Android-Navigation (`NavigationNames`), Preferences (`ui/preferences`) und Modulgrenzen.

## Navigation / Shell

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Home (konfigurierbare Sektionen) | 4 | todo | Queue, Inbox, Downloads, … |
| Queue | 5 | wip | JSON persistence |
| Inbox | 4 | done | Unplayed across feeds (`!isPlayed`), newest first; tab + pull-to-refresh all feeds |
| Episodes (Alle) | 4 | todo | |
| Downloads-Liste | 5 | wip | P0, local files + persisted catalog |
| History | 3 | todo | |
| Favorites | 3 | todo | |
| Subscriptions | 5 | wip | List + subscribe sheet |
| Add podcast | 5 | wip | URL + Apple Podcasts search (Subscribe reuses feed URL pipeline) |
| Search (Bibliothek) | 4 | done | Local only: Inbox `.searchable` (debounced) filters feeds + episodes; Subscriptions filters feeds; EpisodeRow actions; not iTunes |
| Statistics | 2 | todo | P3 |
| Bottom nav / Drawer-Analog | 4 | wip | SwiftUI Tabs (5): Inbox, Subscriptions, Queue, Downloads, Settings |
| Miniplayer + Full Player | 5 | done | Mini player; tap → full sheet (artwork, scrubber, ±30s, speed, sleep timer, mark/queue/download) |
| Video Player | 1 | todo | P4, bewusst nachrangig |
| Settings | 5 | wip | Tab: theme + default speed + playback source + download storage limit + refresh interval + auto-download (P0/P1); more prefs later |

## Subscriptions

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Subscribe / Unsubscribe (URL) | 5 | wip | Subscribe-by-URL skeleton |
| OPML Import/Export | 5 | done | Pure Swift XML (fork `ios/`); Settings + Subscriptions; batch subscribe with progress/errors |
| Feed aktualisieren | 5 | done | Fetch + parse on subscribe; pull-to-refresh all; auto refresh by Settings interval |
| Episodenliste / Feed-Seite | 5 | wip | |
| Archive / restore | 3 | todo | |
| Tags / Folders | 3 | todo | |
| Per-feed settings | 4 | todo | Auto-DL, Speed, Skip Intro |
| Keep updated | 4 | done | Global via Settings refresh interval (all subscribed feeds on launch/foreground when due); per-feed toggle later |
| New-episode action (Inbox/Queue) | 4 | todo | Regeln → KMP |
| Local folder feeds | 2 | todo | iOS DocumentPicker |
| Share podcast/episode | 3 | todo | |

## Playback

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Stream playback | 5 | wip | AVPlayer skeleton |
| Lockscreen / Now Playing | 5 | done | MPNowPlayingInfoCenter + remote play/pause/±30s/scrub; artwork from feed |
| Variable speed | 5 | wip | Mini + full player rate menu |
| Sleep timer (Basis) | 5 | done | Clock presets 5–60 min + end of episode; fade last 10s; mini + full player menu |
| Fortschritt speichern / fortsetzen | 5 | done | JSON `playback.json`; resume on play |
| Mark played / unplayed | 5 | done | Manual + smart-mark last 30s (AntennaPod default) |
| Continuous playback (Queue) | 5 | done | Auto-next from queue on episode end (`nextQueueEpisode`); end-of-episode sleep timer still stops without advancing |
| FF / Rewind deltas | 4 | wip | ±30s in mini + full player |
| Skip silence | 2 | todo | P3, iOS-API-abhängig |
| Volume adaptation | 2 | todo | P3 |
| Chapters | 4 | done | PSC inline (`psc:chapter`) + Podcast Index URL/JSON; full player list, tap seek, current highlight; hidden when none. Media-file tags later |
| Transcripts | 2 | todo | P3 |
| Headset / Bluetooth pause | 4 | done | AVAudioSession interruption (pause / resume if shouldResume) + routeChange oldDeviceUnavailable (unplug); remotes/Now Playing unchanged |
| Prefer stream vs download | 5 | done | Settings: Prefer download / Prefer stream / Automatic (default); `PlaybackService.play` resolves via `DownloadService.localURL`; mini + full player show Local/Stream |
| Video → audio-only | 1 | todo | mit Video P4 |

## Downloads

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Manual download / delete | 5 | done | Documents/downloads + JSON catalog (`downloads.json`) |
| Offline Wiedergabe | 5 | done | Play from local file; catalog restored on launch |
| Speicherverwaltung / Cache-Limit | 5 | done | UserDefaults byte budget (unlimited / 1 / 5 / 10 GB / custom MB); usage in Settings; eviction: played oldest-mtime first then unplayed LRU; after DL + Settings open + launch; Clear downloads |
| Auto-download (global + Regeln) | 4 | done | Global toggle + per-feed cap (1/2/3/5 newest unplayed); enqueue after refresh via DownloadService; Wi‑Fi-only via NWPathMonitor; storage eviction unchanged. Full Android-style filter rules → KMP later |
| Per-feed auto-download | 4 | todo | Global only in this slice; per-feed enable/disable later |
| Auto-delete after play | 4 | todo | |
| Mobile/Wi‑Fi Policy | 4 | wip | Auto-download Wi‑Fi/Ethernet-only via NWPathMonitor; manual downloads still allow cellular; broader cellular prefs later |
| Background downloads | 5 | done | `URLSessionConfiguration.background`; AppDelegate `handleEventsForBackgroundURLSession`; task↔episode in `pending-downloads.json` |
| Download log / errors | 3 | todo | lastError surfaced in UI |

## Discovery

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Add by RSS URL | 5 | wip | Add sheet Feed URL tab |
| Apple Podcasts / iTunes Search | 4 | done | Native URLSession; Add sheet Search tab; debounced; feedUrl → subscribe |
| Podcast Index | 4 | todo | |
| fyyd | 3 | todo | |
| Top lists / Quick discovery | 4 | todo | |
| Online feed preview | 4 | wip | Subscribe fetches+parses feed (episodes) via FeedRepository; no separate preview screen yet |

## Sync & Import

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| gpodder.net sync | 4 | todo | **P1** |
| Nextcloud Gpodder sync | 4 | todo | **P1** |
| AntennaPod DB backup import/export | 3 | todo | P2 |
| HTML export | 2 | todo | |
| Wear OS companion | 1 | n/a | → Watch später P4 |

## Settings (P0-Subset zuerst)

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Theme light/dark/auto | 5 | done | UserDefaults; `preferredColorScheme` system/light/dark |
| Default playback speed | 5 | done | UserDefaults; applied on fresh episode start; mini-player marks Default |
| Prefer stream vs download | 5 | done | UserDefaults; Prefer download / Prefer stream / Automatic; honored in `PlaybackService.play` |
| FF/Rewind seconds | 4 | todo | |
| Refresh interval | 4 | done | UserDefaults presets: manual / 1h / 4h / 12h / 24h; due-check on launch + foreground → `refreshAllFeeds()`; BGAppRefreshTask stubbed (no `fetch` in Info.plist) |
| Swipe actions | 3 | todo | |
| Parental controls | 2 | todo | |
| Notifications (DL/Sync errors) | 4 | todo | |
| About / contribute links | 2 | todo | |

## Extras

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Statistics | 2 | todo | |
| Echo (Year in Review) | 2 | todo | |
| Homescreen Widget | 1 | todo | WidgetKit |
| CarPlay | 1 | todo | |
| Siri Shortcuts | 1 | todo | |
| Apple Watch companion | 1 | todo | |
| Chromecast | 1 | n/a | AirPlay statt Cast |
| Rating prompt | 1 | todo | optional |

## KMP vs. native (Kurz)

| In KMP (Shared) | Native iOS |
|-----------------|------------|
| Domain models, Feed-Parser, OPML (later) | SwiftUI, AVFoundation; OPML native for beta |
| Geschäftsregeln (Filter, Queue, Auto-DL-Kandidaten) | URLSession Downloads, BGTasks |
| Discovery- & Sync-Protokoll-Clients | GRDB/SQLite Persistenz |
| Schema-/Verhaltens-Specs | UNUserNotificationCenter, WidgetKit |
