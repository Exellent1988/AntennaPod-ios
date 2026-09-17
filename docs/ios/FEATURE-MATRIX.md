# Feature-Matrix (Android → iOS)

Status: `todo` | `wip` | `done` | `n/a` (kein sinnvolles iOS-Äquivalent).  
Gewicht: 5 = P0 … 1 = P4. Details und Begründung: [PLAN.md](PLAN.md).

Stand abgeleitet aus Android-Navigation (`NavigationNames`), Preferences (`ui/preferences`) und Modulgrenzen.

## Navigation / Shell

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Home (konfigurierbare Sektionen) | 4 | todo | Queue, Inbox, Downloads, … |
| Queue | 5 | wip | In-memory on iOS skeleton |
| Inbox | 4 | todo | Neue Episoden |
| Episodes (Alle) | 4 | todo | |
| Downloads-Liste | 5 | wip | P0, local file downloads |
| History | 3 | todo | |
| Favorites | 3 | todo | |
| Subscriptions | 5 | todo | Grid/Liste, Tags später |
| Add podcast | 5 | todo | URL + Discovery |
| Search (Bibliothek) | 4 | todo | |
| Statistics | 2 | todo | P3 |
| Bottom nav / Drawer-Analog | 4 | todo | SwiftUI Tabs |
| Miniplayer + Full Player | 5 | todo | AVFoundation / Now Playing |
| Video Player | 1 | todo | P4, bewusst nachrangig |
| Settings | 5 | todo | Basis in P0 |

## Subscriptions

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Subscribe / Unsubscribe (URL) | 5 | todo | |
| OPML Import/Export | 5 | todo | KMP-Kandidat |
| Feed aktualisieren | 5 | todo | |
| Episodenliste / Feed-Seite | 5 | todo | |
| Archive / restore | 3 | todo | |
| Tags / Folders | 3 | todo | |
| Per-feed settings | 4 | todo | Auto-DL, Speed, Skip Intro |
| Keep updated | 4 | todo | |
| New-episode action (Inbox/Queue) | 4 | todo | Regeln → KMP |
| Local folder feeds | 2 | todo | iOS DocumentPicker |
| Share podcast/episode | 3 | todo | |

## Playback

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Stream playback | 5 | todo | P0 |
| Lockscreen / Now Playing | 5 | todo | |
| Variable speed | 5 | todo | |
| Sleep timer (Basis) | 5 | todo | |
| Fortschritt speichern / fortsetzen | 5 | todo | |
| Mark played / unplayed | 5 | todo | |
| Continuous playback (Queue) | 5 | todo | |
| FF / Rewind deltas | 4 | todo | |
| Skip silence | 2 | todo | P3, iOS-API-abhängig |
| Volume adaptation | 2 | todo | P3 |
| Chapters | 4 | todo | Feed + Media-Tags |
| Transcripts | 2 | todo | P3 |
| Headset / Bluetooth pause | 4 | todo | |
| Prefer stream vs download | 5 | todo | |
| Video → audio-only | 1 | todo | mit Video P4 |

## Downloads

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Manual download / delete | 5 | todo | P0, gleich Streaming |
| Offline Wiedergabe | 5 | todo | |
| Speicherverwaltung / Cache-Limit | 5 | todo | |
| Auto-download (global + Regeln) | 4 | todo | Regeln in KMP |
| Per-feed auto-download | 4 | todo | |
| Auto-delete after play | 4 | todo | |
| Mobile/Wi‑Fi Policy | 4 | todo | Cellular toggles |
| Background downloads | 5 | todo | URLSession + BGTasks |
| Download log / errors | 3 | todo | |

## Discovery

| Feature | Gewicht | iOS-Status | Hinweis |
|---------|---------|------------|---------|
| Add by RSS URL | 5 | todo | |
| Apple Podcasts / iTunes Search | 4 | todo | KMP-Client |
| Podcast Index | 4 | todo | |
| fyyd | 3 | todo | |
| Top lists / Quick discovery | 4 | todo | |
| Online feed preview | 4 | todo | |

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
| Theme light/dark/auto | 5 | todo | |
| Default playback speed | 5 | todo | |
| FF/Rewind seconds | 4 | todo | |
| Refresh interval | 4 | todo | |
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
| Domain models, Feed-Parser, OPML | SwiftUI, AVFoundation |
| Geschäftsregeln (Filter, Queue, Auto-DL-Kandidaten) | URLSession Downloads, BGTasks |
| Discovery- & Sync-Protokoll-Clients | GRDB/SQLite Persistenz |
| Schema-/Verhaltens-Specs | UNUserNotificationCenter, WidgetKit |
