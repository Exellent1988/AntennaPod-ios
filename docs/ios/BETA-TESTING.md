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
| ☐ Full/Mini: Open podcast → Feed-Detail (fehlt → disabled / Hinweis) | ☐ Full/Mini: Open podcast → feed detail (missing → disabled / alert) |
| ☐ Play/Pause, Rewind/FF (Settings-Intervalle) | ☐ Play/Pause, rewind/FF (Settings intervals) |
| ☐ Scrubber / Seek | ☐ Scrubber / seek |
| ☐ Geschwindigkeit Tippen = nächste Preset (0.8…2.0 Wrap); Long-Press = Menü; Default aus Settings | ☐ Speed tap = next preset (0.8…2.0 wrap); long-press = menu; default from Settings |
| ☐ Sleep timer (Uhr / Ende der Episode) | ☐ Sleep timer (clock / end of episode) |
| ☐ Chapters tippen → Seek (wenn im Feed) | ☐ Chapters tap → seek (when in feed) |
| ☐ Transcript sheet (nur Feed-URL) | ☐ Transcript sheet (feed URL only) |
| ☐ Video → audio only Toggle | ☐ Play video as audio only |
| ☐ Picture in Picture (Video-Surface, Button) | ☐ Picture in Picture (video surface, button) |
| ☐ Keep screen on (Settings; idle timer während Play) | ☐ Keep screen on (Settings; idle timer while playing) |
| ☐ Continuous playback Toggle (an → Queue-Next; aus → Stop ohne Advance) | ☐ Continuous playback toggle (on → queue next; off → stop, no advance) |
| ☐ Show remaining time (Settings; Mini/Full rechts −Rest; Tippen Full-Label) | ☐ Show remaining time (Settings; mini/full right −remaining; tap full label) |
| ☐ Stereo to mono (Settings; best-effort preferredOutputChannels=1; Route kann ignorieren) | ☐ Stereo to mono (Settings; best-effort preferredOutputChannels=1; route may ignore) |
| ☐ Rewind after pause (Settings Off/1/2/3/5/10, default 2; Pause ≥1s → Seek zurück; kein Cold-Play) | ☐ Rewind after pause (Settings Off/1/2/3/5/10, default 2; pause ≥1s → seek back; not on cold play) |
| ☐ Progress speichern / Resume | ☐ Progress save / resume |
| ☐ Mark played / unplayed (+ Smart mark Settings Off/15/30/60/120, default 30) | ☐ Mark played / unplayed (+ Smart mark Settings Off/15/30/60/120, default 30) |
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
| ☐ Feed: Alle herunterladen (Bestätigung + Cap) | ☐ Feed: Download all (confirm + cap) |
| ☐ Feed: Alle als gehört markieren (Bestätigung) | ☐ Feed: Mark all as played (confirm) |
| ☐ Background-Download überlebt Suspend | ☐ Background download survives suspend |
| ☐ Auto-download nach Refresh (Cap + Wi‑Fi) | ☐ Auto-download after refresh (cap + Wi‑Fi) |
| ☐ Storage-Limit / Eviction | ☐ Storage limit / eviction |
| ☐ Auto-delete after play | ☐ Auto-delete after play |
| ☐ Network / Downloads Wi‑Fi-only Gates | ☐ Network / Downloads Wi‑Fi-only gates |
| ☐ Download-Fehlerbanner + Log | ☐ Download error banner + log |
| ☐ Downloads: Suche (Titel / Feed) | ☐ Downloads: search (title / feed) |
| ☐ Downloads: Swipes (Play Next / Queue / Delete) | ☐ Downloads: swipes (Play Next / Add to queue / Delete) |
| ☐ Downloads: Gehörte löschen (Bestätigung; Favoriten überspringen) | ☐ Downloads: Delete played (confirm; skip favorites) |

---

## Navigation / Library

| DE | EN |
|----|----|
| ☐ Home (Continue / Inbox / Queue / Discover) | ☐ Home (Continue / Inbox / Queue / Discover) |
| ☐ Inbox (unplayed) + Swipes (Archive / Mark played / Play Next / Queue) | ☐ Inbox (unplayed) + swipes (Archive / Mark played / Play Next / Add to queue) |
| ☐ Inbox: Alle als gehört markieren (Bestätigung) | ☐ Inbox: Mark all as played (confirm) |
| ☐ Queue: Remove, Archive, Reorder | ☐ Queue: remove, archive, reorder |
| ☐ Queue: Warteschlange leeren (Bestätigung) | ☐ Queue: Clear queue (confirm) |
| ☐ Queue: Suche (Titel / Feed; kein Reorder während Filter) | ☐ Queue: search (title / feed; no reorder while filtering) |
| ☐ Subscriptions + Tags/Filter | ☐ Subscriptions + tags/filter |
| ☐ Subscriptions: Sortierung (Zuletzt aktualisiert / Alphabetisch) | ☐ Subscriptions: sort (Recently updated / Alphabetical) |
| ☐ Feed-Detail: Episoden-Sortierung (Neueste / Älteste zuerst) | ☐ Feed detail: episode sort (Newest / Oldest first) |
| ☐ Feed-Detail: Suche (Episodentitel) | ☐ Feed detail: search (episode title) |
| ☐ Library: Episodes (Filter All / Ungehört / Heruntergeladen) / History / Favorites / Archived / Statistics / Echo | ☐ Library: Episodes (filter All / Unplayed / Downloaded) / History / Favorites / Archived / Statistics / Echo |
| ☐ History: Verlauf leeren (Bestätigung) | ☐ History: Clear history (confirm) |
| ☐ History: Suche (Titel / Feed) | ☐ History: search (title / feed) |
| ☐ Favoriten (Stern) | ☐ Favorites (star) |
| ☐ Favoriten: Suche (Titel / Feed) | ☐ Favorites: search (title / feed) |
| ☐ Favoriten: Favoriten leeren (Bestätigung) | ☐ Favorites: Clear favorites (confirm) |
| ☐ Archive / Restore | ☐ Archive / restore |
| ☐ Archiviert: Suche (Titel / Feed) | ☐ Archived: search (title / feed) |
| ☐ Archiviert: Alle wiederherstellen (Bestätigung) | ☐ Archived: Restore all (confirm) |
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
- Stereo to mono: Best-Effort `setPreferredOutputNumberOfChannels(1)`; Route kann ignorieren; kein ExoPlayer-Remix; AVPlayer bleibt.  
  Stereo to mono: best-effort `setPreferredOutputNumberOfChannels(1)`; route may ignore; not ExoPlayer remix; AVPlayer kept.
- Keep screen on: nur Idle-Timer (`isIdleTimerDisabled`); kein Low-Power-Override / keine Helligkeit; PiP/Hintergrund-Audio unverändert.  
  Keep screen on: idle timer only; no Low Power Mode override / no brightness; PiP/background audio unchanged.
- Continuous playback: Toggle Standard **an**; aus = Episode-Ende ohne Queue-Advance (Mark played / Progress bleiben); Sleep-Timer Ende der Episode stoppt weiterhin ohne Advance.  
  Continuous playback: toggle default **on**; off = episode end without queue advance (mark played / progress still apply); end-of-episode sleep timer still stops without advance.
- Show remaining time: Settings Toggle Standard **aus**; an = Mini + Full rechts −Restzeit statt Dauer; Links Position; Tippen auf Full-Player-Label toggelt.  
  Show remaining time: Settings toggle default **off**; on = mini + full right −remaining instead of duration; left position; tap full-player label toggles.
- Rewind after pause: Settings → Playback Picker Off/1/2/3/5/10 (Standard **2**); nur nach echter Pause ≥1s der aktuellen Episode — nicht bei Cold-Play / erstem Start; fester Betrag (nicht Android-Zeitstufen).  
  Rewind after pause: Settings → Playback picker Off/1/2/3/5/10 (default **2**); only after a real pause ≥1s of the current item — not cold play / first start; fixed amount (not Android elapsed tiers).
- Smart mark as played: Settings → Playback Picker Off/15/30/60/120 (Standard **30**); Aus (0) = nur natürliches Ende oder manuell als gehört — kein Near-End-Scrub.  
  Smart mark as played: Settings → Playback picker Off/15/30/60/120 (default **30**); Off (0) = only natural end or explicit mark — not near-end scrub.

Siehe auch: [FEATURE-MATRIX.md](FEATURE-MATRIX.md), [ios/README.md](../../ios/README.md).
