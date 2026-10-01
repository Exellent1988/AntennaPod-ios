# Beta testing checklist / Beta-Checkliste

For Axel — short bilingual checklist of major AntennaPod iOS flows before a TestFlight / device beta.  
Kurz-Checkliste (DE/EN) der wichtigsten Flows vor einem Geräte-/TestFlight-Beta.

Mark each item: ☐ todo · ☑ ok · ✗ fail (+ note).  
Jedes Item: ☐ offen · ☑ ok · ✗ Fehler (+ Notiz).

---

## Setup / Einrichtung

| DE | EN |
|----|----|
| ☐ App auf Gerät/Simulator bauen (`xcodegen` + Team/Signing) | ☐ Build on device/simulator (`xcodegen` + Team/signing) |
| ☐ App Group `group.de.danoeh.antennapod.ios` für App + Widget + Watch | ☐ App Group enabled for app + widget + Watch targets |
| ☐ Background audio in Info.plist vorhanden (`UIBackgroundModes` → `audio`) | ☐ Background audio present (`UIBackgroundModes` → `audio`) |

---

## Subscribe / Abonnieren

| DE | EN |
|----|----|
| ☐ Feed-URL abonnieren (Add → URL) | ☐ Subscribe via feed URL |
| ☐ Online-Vorschau → Confirm Subscribe | ☐ Online feed preview → Confirm Subscribe |
| ☐ Discovery: Apple Podcasts / iTunes Search | ☐ Discovery: Apple Podcasts / iTunes Search |
| ☐ Discovery: Podcast Index (API-Key in Settings) | ☐ Discovery: Podcast Index (API keys in Settings) |
| ☐ Discovery: fyyd | ☐ Discovery: fyyd |
| ☐ Top lists / Charts (Land in Settings) | ☐ Top lists / charts (country in Settings) |
| ☐ Local folder feed (Datei-Ordner) | ☐ Local folder feed |
| ☐ OPML import (mehrere Feeds) | ☐ OPML import (batch) |
| ☐ Bereits abonniert → Open feed | ☐ Already subscribed → Open feed |

---

## Play / Wiedergabe

| DE | EN |
|----|----|
| ☐ Stream starten (Episode tippen) | ☐ Start stream (tap episode) |
| ☐ Download spielen (offline Datei) | ☐ Play downloaded file |
| ☐ Mini-Player + Full Player (Artwork / Video) | ☐ Mini player + full player (artwork / video) |
| ☐ Play/Pause, Rewind/FF (Settings-Intervalle) | ☐ Play/Pause, rewind/FF (Settings intervals) |
| ☐ Scrubber / Seek | ☐ Scrubber / seek |
| ☐ Geschwindigkeit (Default aus Settings) | ☐ Speed (default from Settings) |
| ☐ Sleep timer (Uhr / Ende der Episode) | ☐ Sleep timer (clock / end of episode) |
| ☐ Chapters tippen → Seek (wenn im Feed) | ☐ Chapters tap → seek (when in feed) |
| ☐ Transcript sheet (nur Feed-URL) | ☐ Transcript sheet (feed URL only) |
| ☐ Video → audio only Toggle | ☐ Play video as audio only |
| ☐ Picture in Picture (Video-Surface, Button) | ☐ Picture in Picture (video surface, button) |
| ☐ Continuous queue (nächste Episode) | ☐ Continuous queue (next episode) |
| ☐ Progress speichern / Resume | ☐ Progress save / resume |
| ☐ Mark played / unplayed (+ smart-mark ~30s) | ☐ Mark played / unplayed (+ smart-mark ~30s) |
| ☐ Skip intro / outro (wenn > 0) | ☐ Skip intro / outro (when > 0) |

---

## Lockscreen / Now Playing / CarPlay (ehrlich)

| DE | EN |
|----|----|
| ☐ Lockscreen: Titel, Podcast, Artwork | ☐ Lockscreen: title, podcast, artwork |
| ☐ Remote Play/Pause/Skip/Seek | ☐ Remote play/pause/skip/seek |
| ☐ Hintergrund weiterhören (Audio-Session `.playback`) | ☐ Background continues (`.playback` session) |
| ☐ Headset/BT Pause bei Unterbrechung / Unplug | ☐ Headset/BT pause on interrupt / unplug |
| ☐ CarPlay: System-Now-Playing sichtbar (kein eigenes CPTemplate) | ☐ CarPlay: system Now Playing only (no custom CPTemplate) |

---

## Download / Netzwerk

| DE | EN |
|----|----|
| ☐ Episode manuell laden | ☐ Manual download |
| ☐ Background-Download überlebt Suspend | ☐ Background download survives suspend |
| ☐ Auto-download nach Refresh (Cap + Wi‑Fi) | ☐ Auto-download after refresh (cap + Wi‑Fi) |
| ☐ Storage-Limit / Eviction | ☐ Storage limit / eviction |
| ☐ Auto-delete after play | ☐ Auto-delete after play |
| ☐ Network / Downloads Wi‑Fi-only Gates | ☐ Network / Downloads Wi‑Fi-only gates |
| ☐ Download-Fehlerbanner + Log | ☐ Download error banner + log |

---

## Navigation / Library

| DE | EN |
|----|----|
| ☐ Home (Continue / Inbox / Queue / Discover) | ☐ Home (Continue / Inbox / Queue / Discover) |
| ☐ Inbox (unplayed) + Swipes | ☐ Inbox (unplayed) + swipes |
| ☐ Queue: Remove, Archive, Reorder | ☐ Queue: remove, archive, reorder |
| ☐ Subscriptions + Tags/Filter | ☐ Subscriptions + tags/filter |
| ☐ Library: Episodes / History / Favorites / Archived / Statistics / Echo | ☐ Library: Episodes / History / Favorites / Archived / Statistics / Echo |
| ☐ Favoriten (Stern) | ☐ Favorites (star) |
| ☐ Archive / Restore | ☐ Archive / restore |
| ☐ Library search (lokal) | ☐ Library search (local) |
| ☐ Share Podcast / Episode | ☐ Share podcast / episode |

---

## Sync / Backup

| DE | EN |
|----|----|
| ☐ gpodder.net: Login + Sync (Subscriptions MVP) | ☐ gpodder.net: login + sync (subscriptions MVP) |
| ☐ Nextcloud Gpodder: Base-URL + Sync | ☐ Nextcloud Gpodder: base URL + sync |
| ☐ Sync-Fehler-Notification (lokal) | ☐ Sync error notification (local) |
| ☐ Backup export ZIP (ohne Keychain-Secrets; default ohne Media) | ☐ Backup export ZIP (no Keychain secrets; default no media) |
| ☐ Backup: Include downloaded episode files (Warnung Größe/Zeit) | ☐ Backup: Include downloaded episode files (size/time warning) |
| ☐ Backup import (Warnung + Reload; Media-Merge wenn vorhanden) | ☐ Backup import (warn + reload; media merge when present) |
| ☐ OPML / HTML export | ☐ OPML / HTML export |

---

## Parental / Settings / Extras

| DE | EN |
|----|----|
| ☐ Parental PIN setzen / Unlock / Disable | ☐ Parental PIN set / unlock / disable |
| ☐ Lock Add/Discover (+ optional Network) | ☐ Lock Add/Discover (+ optional Network) |
| ☐ Theme light/dark/system | ☐ Theme light/dark/system |
| ☐ Notify new episodes (lokal, kein Push) | ☐ Notify new episodes (local, no push) |
| ☐ Per-feed settings (auto-DL / keep / notify / tags) | ☐ Per-feed settings (auto-DL / keep / notify / tags) |
| ☐ Feed refresh interval / Keep updated | ☐ Feed refresh interval / Keep updated |
| ☐ New-episode action (Inbox / Queue) | ☐ New-episode action (Inbox / Queue) |
| ☐ Siri / Shortcuts lite (`antennapod://…`) | ☐ Siri / Shortcuts lite (`antennapod://…`) |
| ☐ Homescreen widget Continue listening (kann stale sein) | ☐ Homescreen widget Continue listening (may be stale) |
| ☐ Apple Watch: Continue listening + Play on iPhone (kein eigenes Playback) | ☐ Apple Watch: Continue listening + Play on iPhone (no independent playback) |
| ☐ About / Version / Links | ☐ About / version / links |
| ☐ Rating prompt (optional; iOS kann unterdrücken) | ☐ Rating prompt (optional; iOS may suppress) |

---

## Nicht erwartet / Not expected (honest)

- **Kein** eigenes CarPlay-UI (`CPTemplate`) ohne Apple-Entitlement.  
  **No** custom CarPlay templates without Apple entitlement.
- Apple Watch: **kein** unabhängiges Watch-Playback / Downloads / Queue — nur Continue-Snapshot + Play-on-iPhone + System-Now-Playing.  
  Apple Watch: **no** independent Watch playback / downloads / queue — Continue snapshot + Play on iPhone + system Now Playing only.
- **Kein** Push (nur lokale UserNotifications).  
  **No** push (local UserNotifications only).
- Skip silence: Preference only — nicht auf stock AVPlayer.  
  Skip silence: preference only — not applied on stock AVPlayer.
- Volume adaptation: iOS session mode (`.spokenAudio`), nicht Android LoudnessEnhancer.  
  Volume adaptation: iOS session mode, not Android loudness gain.

Siehe auch: [FEATURE-MATRIX.md](FEATURE-MATRIX.md), [ios/README.md](../../ios/README.md).
