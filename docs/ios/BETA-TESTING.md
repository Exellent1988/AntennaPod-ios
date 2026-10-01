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
| ☐ Aus Zwischenablage hinzufügen (http(s); Vorschau; kein Auto-Abo) | ☐ Add from Clipboard (http(s); Preview; no auto-subscribe) |
| ☐ Online-Vorschau → Confirm Subscribe | ☐ Online feed preview → Confirm Subscribe |
| ☐ Discovery: Apple Podcasts / iTunes Search | ☐ Discovery: Apple Podcasts / iTunes Search |
| ☐ Discovery: Podcast Index (API-Key in Settings) | ☐ Discovery: Podcast Index (API keys in Settings) |
| ☐ Discovery: fyyd | ☐ Discovery: fyyd |
| ☐ Top lists / Charts (Land in Settings) | ☐ Top lists / charts (country in Settings) |
| ☐ Local folder feed (Datei-Ordner) | ☐ Local folder feed |
| ☐ OPML import (mehrere Feeds) | ☐ OPML import (batch) |
| ☐ Bereits abonniert → Open feed | ☐ Already subscribed → Open feed |
| ☐ Abo beenden: Swipe auf Subscriptions (Bestätigung + Titel; Downloads bleiben) | ☐ Unsubscribe: Subscriptions swipe (confirm + title; downloads kept) |
| ☐ Abo beenden: Feed-Detail ⋯ (Bestätigung; pop nach Confirm) | ☐ Unsubscribe: Feed detail ⋯ (confirm; pop after confirm) |

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
| ☐ Jump to position (Full: mm:ss / Min+Sek → Seek; disabled ohne Dauer) | ☐ Jump to position (Full: mm:ss / min+sec → seek; disabled without duration) |
| ☐ Play from beginning (Full secondary: Seek 0 + Play; EpisodeRow Kontext; kein Unplayed-Flag) | ☐ Play from beginning (Full secondary: seek 0 + play; EpisodeRow context; no unplayed flag) |
| ☐ Mark played / unplayed (Full secondary; `isPlayed` Toggle via `togglePlayed`; kein Seek/Stop; gleiche playback.json wie Listen) | ☐ Mark played / unplayed (Full secondary; `isPlayed` toggle via `togglePlayed`; no seek/stop; same playback.json as lists) |
| ☐ Favorit umschalten (Full secondary Stern; EpisodeRow; sofort via `favorites.json`) | ☐ Favorite toggle (Full secondary star; EpisodeRow; immediate via `favorites.json`) |
| ☐ Archivieren / Wiederherstellen (Full secondary; EpisodeRow; sofort via `archived.json`; Inbox ausblenden) | ☐ Archive / restore (Full secondary; EpisodeRow; immediate via `archived.json`; hides from Inbox) |
| ☐ Queue-Menü Full Player (Add ↔ Remove via `isInQueue`; Play Next wenn nicht schon next; gleiche Store-APIs) | ☐ Full Player Queue menu (Add ↔ Remove via `isInQueue`; Play Next when not already next; same store APIs) |
| ☐ Full Player Download (nicht geladen → Laden; läuft → Abbrechen; geladen → Download löschen **mit Confirm** + Titel; lokal-Ordner ausgeblendet) | ☐ Full Player download (not downloaded → Download; in progress → Cancel; downloaded → Delete download **with confirm** + title; hidden for local-folder) |
| ☐ Geschwindigkeit Tippen = nächste Preset (0.8…2.0 Wrap); Long-Press = Menü; Default aus Settings | ☐ Speed tap = next preset (0.8…2.0 wrap); long-press = menu; default from Settings |
| ☐ Sleep timer (Uhr / Ende der Episode / Custom… 1–180 Min.; Mini-Player Restzeit-Badge) | ☐ Sleep timer (clock / end of episode / Custom… 1–180 min; mini player remaining badge) |
| ☐ Chapters tippen → Seek (wenn im Feed) | ☐ Chapters tap → seek (when in feed) |
| ☐ Kapitel Prev/Next (nur wenn Kapitel; Next → nächster Start; Prev → Anfang wenn >2s sonst vorheriges) | ☐ Chapter prev/next (only when chapters; Next → next start; Prev → restart if >2s else previous) |
| ☐ Aktueller Kapitel-Titel (Mini unter Episode; Full unter Podcast; leer/ohne Kapitel ausgeblendet; folgt Position) | ☐ Current chapter title (mini under episode; full under podcast; hidden when none/empty; follows position) |
| ☐ Transcript sheet (nur Feed-URL) | ☐ Transcript sheet (feed URL only) |
| ☐ Shownotes / Beschreibung (Full Player + Episode-Kontext; leer wenn keine; HTML → Plain Text) | ☐ Shownotes / description (full player + episode context; empty when none; HTML → plain text) |
| ☐ Episoden-Dauer in Listen (EpisodeRow Caption `m:ss`/`h:mm:ss` aus Feed/`playback`; versteckt wenn unbekannt; VoiceOver Dauer) | ☐ Episode duration on lists (EpisodeRow caption `m:ss`/`h:mm:ss` from feed/playback; hidden when unknown; VoiceOver Duration) |
| ☐ Enclosure-/Dateigröße in EpisodeRow (Caption `Datum · Dauer · Größe`; Disk bevorzugt, sonst Enclosure; ausblenden wenn unbekannt; VoiceOver Größe) | ☐ Enclosure/file size on EpisodeRow (caption `date · duration · size`; disk preferred, else enclosure; hide when unknown; VoiceOver Size) |
| ☐ Relative Veröffentlichungsdaten (EpisodeRow: Heute / Gestern / vor N Tagen ≤7 / sonst Medium-Absolut; Caption `Datum · Dauer · Größe` wenn bekannt; VoiceOver) | ☐ Relative publish dates (EpisodeRow: Today / Yesterday / N days ago ≤7 / else medium absolute; caption `date · duration · size` when known; VoiceOver) |
| ☐ Fortschrittsbalken EpisodeRow (gestartet-nicht-fertig: position>1, !isPlayed, Dauer bekannt; aus `playback.json`; VoiceOver Prozent + Rest / Position) | ☐ EpisodeRow progress bar (started-not-finished: position>1, !isPlayed, duration known; from `playback.json`; VoiceOver percent + remaining / position) |
| ☐ Podcast-Beschreibung (Feed-Detail info; Titel + Text; ausgeblendet wenn leer; ggf. Refresh nötig) | ☐ Podcast description (Feed detail info; title + text; hidden when empty; refresh may be needed) |
| ☐ Video → audio only Toggle | ☐ Play video as audio only |
| ☐ Picture in Picture (Video-Surface, Button) | ☐ Picture in Picture (video surface, button) |
| ☐ Keep screen on (Settings; idle timer während Play) | ☐ Keep screen on (Settings; idle timer while playing) |
| ☐ Continuous playback Toggle (an → Queue-Next; aus → Stop ohne Advance) | ☐ Continuous playback toggle (on → queue next; off → stop, no advance) |
| ☐ Show remaining time (Settings; Mini/Full rechts −Rest; Tippen Full-Label) | ☐ Show remaining time (Settings; mini/full right −remaining; tap full label) |
| ☐ Stereo to mono (Settings; best-effort preferredOutputChannels=1; Route kann ignorieren) | ☐ Stereo to mono (Settings; best-effort preferredOutputChannels=1; route may ignore) |
| ☐ Rewind after pause (Settings Off/1/2/3/5/10, default 2; Pause ≥1s → Seek zurück; kein Cold-Play) | ☐ Rewind after pause (Settings Off/1/2/3/5/10, default 2; pause ≥1s → seek back; not on cold play) |
| ☐ Progress speichern / Resume | ☐ Progress save / resume |
| ☐ Mark played / unplayed (EpisodeRow, Feed-Swipe, Full Player, Alle Episoden; VoiceOver Hints; Smart mark Off/15/30/60/120, default 30) | ☐ Mark played / unplayed (EpisodeRow, Feed swipe, Full Player, All Episodes; VoiceOver hints; Smart mark Off/15/30/60/120, default 30) |
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
| ☐ Full Player: Download / Abbrechen / Download löschen (gleiche DownloadService-APIs; Wi‑Fi-Gate; **Confirm** + Titel; nur lokale Datei) | ☐ Full Player: Download / Cancel / Delete download (same DownloadService APIs; Wi‑Fi gate; **confirm** + title; local file only) |
| ☐ Feed: Alle herunterladen (Bestätigung + Cap) | ☐ Feed: Download all (confirm + cap) |
| ☐ Feed: Alle als gehört markieren (Bestätigung) | ☐ Feed: Mark all as played (confirm) |
| ☐ Feed: Alle zur Warteschlange (Bestätigung; voller Feed-Katalog; pubDate neueste zuerst; schon eingereiht übersprungen; nicht Chip/Suche; inkl. gehört/archiviert; Sperre blockiert nicht) | ☐ Feed: Add all to queue (confirm; full feed catalog; newest pubDate first; skip already queued; not chip/search; includes played/archived; lock does not block) |
| ☐ Background-Download überlebt Suspend | ☐ Background download survives suspend |
| ☐ Auto-download nach Refresh (nur neue IDs, Cap 1/2/3/5, Wi‑Fi, Per-Feed, kein Local-Folder; kein separates BGAppRefresh) | ☐ Auto-download after refresh (new IDs only, cap 1/2/3/5, Wi‑Fi, per-feed, skip local-folder; no separate BGAppRefresh) |
| ☐ Storage-Limit / Eviction | ☐ Storage limit / eviction |
| ☐ Auto-delete after play | ☐ Auto-delete after play |
| ☐ Network / Downloads Wi‑Fi-only Gates | ☐ Network / Downloads Wi‑Fi-only gates |
| ☐ Download-Fehlerbanner + Log | ☐ Download error banner + log |
| ☐ Downloads: Suche (Titel / Feed) | ☐ Downloads: search (title / feed) |
| ☐ Downloads: Sortierung (Neueste / Älteste; Download-Zeit sonst pubDate; persistiert) | ☐ Downloads: sort (Newest / Oldest; download time else pubDate; persisted) |
| ☐ Downloads: Filter-Chips Alle / Ungehört / Gehört (persistiert; mit Suche + Sort) | ☐ Downloads: filter chips All / Unplayed / Played (persisted; with search + sort) |
| ☐ Downloads: Swipes (Play Next / Queue / Delete **mit Confirm** + Titel; nur lokale Datei — Played/Queue/Favoriten bleiben) | ☐ Downloads: swipes (Play Next / Add to queue / Delete **with confirm** + title; local file only — keeps played/queue/favorites) |
| ☐ Downloads: Gehörte löschen (Bestätigung; Favoriten überspringen; global — nicht nur sichtbarer Filter) | ☐ Downloads: Delete played (confirm; skip favorites; global — not visible filter only) |
| ☐ Downloads: Alle zur Warteschlange (Bestätigung; voller Downloads-Katalog; Katalogreihenfolge älteste zuerst; schon eingereiht übersprungen; Sperre blockiert nicht) | ☐ Downloads: Add all to queue (confirm; full Downloads catalog; catalog order oldest first; skip already queued; lock does not block) |
| ☐ Downloads: Dateigröße in Zeile (Datei auf Disk bevorzugt, sonst Enclosure-Größe; ausblenden wenn unbekannt) + Toolbar-Gesamtgröße | ☐ Downloads: row file size (disk preferred, else enclosure; hide when unknown) + toolbar total |
| ☐ Downloads: Tab-Badge (volle Katalog-Länge; nicht Chip/Suche/in-progress; 0 ausgeblendet; System-VoiceOver) | ☐ Downloads: tab badge (full catalog length; not chip/search/in-progress; hide when 0; system VoiceOver) |
| ☐ Downloads: Verbleibende Zeit (Info-Leiste; gefilterte Liste; ~ bei unbekannten Dauern; nicht Tab-Badge-Katalog) | ☐ Downloads: remaining time (info bar; visible filtered list; ~ when unknowns; not tab-badge catalog) |

---

## Navigation / Library

| DE | EN |
|----|----|
| ☐ Home (Continue / Inbox / Queue / Discover) | ☐ Home (Continue / Inbox / Queue / Discover) |
| ☐ Home: Suche (Titel / Feed; leere Abschnitte aus; Discover ausgeblendet während Suche) | ☐ Home: search (title / feed; empty sections hide; Discover hidden while searching) |
| ☐ Inbox (unplayed) + Swipes (Archive / Mark played / Play Next / Queue) | ☐ Inbox (unplayed) + swipes (Archive / Mark played / Play Next / Add to queue) |
| ☐ Inbox: Alle als gehört markieren (Bestätigung) | ☐ Inbox: Mark all as played (confirm) |
| ☐ Inbox: Alle zur Warteschlange (Bestätigung; voller Inbox-Katalog; schon eingereiht übersprungen; Sperre blockiert nicht) | ☐ Inbox: Add all to queue (confirm; full Inbox catalog; skip already queued; lock does not block) |
| ☐ Inbox: Sortierung (Neueste / Älteste zuerst; persistiert) | ☐ Inbox: sort (Newest / Oldest first; persisted) |
| ☐ Inbox: Tab-Badge (Anzahl Inbox-Episoden; 0 ausgeblendet; System-VoiceOver) | ☐ Inbox: tab badge (inbox episode count; hide when 0; system VoiceOver) |
| ☐ Inbox: Verbleibende Zeit (Info-Leiste; sortierte Inbox-Liste; ~ bei unbekannten Dauern; ausgeblendet bei Bibliothekssuche) | ☐ Inbox: remaining time (info bar; sorted Inbox list; ~ when unknowns; hidden during library search) |
| ☐ Queue: Tab-Badge (volle Warteschlangen-Länge; nicht Chip/Suche-Filter; 0 ausgeblendet; System-VoiceOver) | ☐ Queue: tab badge (full queue length; not chip/search filter; hide when 0; system VoiceOver) |
| ☐ Queue: Remove **mit Confirm** + Titel (nur Queue — kein Download-/Played-/Stopp); Archive, Reorder; Full-Player Add/Remove (**Remove mit Confirm**) | ☐ Queue: Remove **with confirm** + title (queue only — no download/played/stop); archive, reorder; Full Player Add/Remove (**Remove with confirm**) |
| ☐ Queue: Mischen (Bestätigung; volle Queue; gesperrt bei Sperre; <2 deaktiviert; aktuell spielende Episode wandert mit id) | ☐ Queue: Shuffle (confirm; full queue; blocked when locked; disabled if <2; current playing moves with id) |
| ☐ Queue: Warteschlange leeren (immer Bestätigung mit voller Anzahl + Hinweis; auch bei Sperre; kein Download/Fortschritt-Löschen) | ☐ Queue: Clear queue (always confirm with full count + honesty; works when locked; no download/progress wipe) |
| ☐ Queue: Suche (Titel / Feed; kein Reorder während Filter) | ☐ Queue: search (title / feed; no reorder while filtering) |
| ☐ Queue: An Anfang / Ans Ende (Kontextmenü; ausgeblendet wenn erste/letzte/nicht in Queue) | ☐ Queue: Move to top / bottom (context menu; hide if first/last/not queued) |
| ☐ Queue: Sperre (Toolbar + Settings; kein Reorder / Mischen / An Anfang-Ende; Einreihen / Als Nächstes / Entfernen / Leeren bleiben) | ☐ Queue: lock (toolbar + Settings; no reorder / Shuffle / Move to top-bottom; enqueue / Play Next / Remove / Clear still work) |
| ☐ Queue: Filterchips Alle / Ungehört / Gehört (persistiert; kein Reorder während Filter; Shuffle/Clear bleiben full-queue) | ☐ Queue: filter chips All / Unplayed / Played (persisted; no reorder while filtering; Shuffle/Clear stay full-queue) |
| ☐ Queue: Verbleibende Zeit (Info-Leiste; gefilterte Liste; ~ bei unbekannten Dauern) | ☐ Queue: remaining time (info bar; visible filtered list; ~ when unknowns) |
| ☐ Subscriptions + Tags/Filter | ☐ Subscriptions + tags/filter |
| ☐ Tags verwalten: Liste + Umbenennen + Löschen (Bestätigung; Settings / Abonnements) | ☐ Manage tags: list + rename + delete (confirm; Settings / Subscriptions) |
| ☐ Subscriptions: Suche (Titel / Beschreibung; Sort bleibt) | ☐ Subscriptions: search (title / description; sort preserved) |
| ☐ Subscriptions: Sortierung (Zuletzt aktualisiert / Alphabetisch) | ☐ Subscriptions: sort (Recently updated / Alphabetical) |
| ☐ Subscriptions: Alle aktualisieren (Toolbar + Pull; Progress während `isLoading`) | ☐ Subscriptions: Refresh all (toolbar + pull; progress while `isLoading`) |
| ☐ Subscriptions: Ungehört-Badge (pro Podcast; 0 ausgeblendet; VoiceOver; `!isPlayed` && nicht archiviert) | ☐ Subscriptions: unplayed badge (per podcast; hide when 0; VoiceOver; `!isPlayed` && not archived) |
| ☐ Feed-Detail: Episoden-Sortierung (Neueste / Älteste zuerst) | ☐ Feed detail: episode sort (Newest / Oldest first) |
| ☐ Feed-Detail: Suche (Episodentitel) | ☐ Feed detail: search (episode title) |
| ☐ Feed-Detail: Filterchips Alle / Ungehört / Gehört (persistiert; Bulk bleibt full-feed) | ☐ Feed detail: filter chips All / Unplayed / Played (persisted; bulk stays full-feed) |
| ☐ Feed-Detail: Verbleibende Zeit (Info-Leiste; sort→chip→Suche; ~ bei unbekannten Dauern; played→0; nicht Bulk-Katalog) | ☐ Feed detail: remaining time (info bar; sort→chip→search; ~ when unknowns; played→0; not bulk eligibility) |
| ☐ Library: Episodes (Filter All / Ungehört / Heruntergeladen / Favoriten) / History / Favorites / Archived / Statistics (Zeitraum Woche/Monat/Jahr/Gesamt) / Echo (gleicher Zeitraum) | ☐ Library: Episodes (filter All / Unplayed / Downloaded / Favorites) / History / Favorites / Archived / Statistics (time range Week/Month/Year/All) / Echo (same range) |
| ☐ Alle Episoden: Sortierung (Neueste / Älteste zuerst; pubDate; Soft-Cap 500 — Älteste nur innerhalb Cap; persistiert) | ☐ All Episodes: sort (Newest / Oldest first; pubDate; soft cap 500 — Oldest only within cap; persisted) |
| ☐ Alle Episoden: Verbleibende Zeit (Info-Leiste; Soft-Cap→Sort→Chip→Suche; ~ bei unbekannten Dauern; nie über Soft-Cap hinaus) | ☐ All Episodes: remaining time (info bar; soft-cap→sort→chip→search; ~ when unknowns; never beyond soft cap) |
| ☐ Alle Episoden: Alle zur Warteschlange (Bestätigung; Soft-Cap neueste 500; pubDate neueste zuerst; schon eingereiht übersprungen; nicht Chip/Suche; Sperre blockiert nicht) | ☐ All Episodes: Add all to queue (confirm; soft-cap newest 500; newest pubDate first; skip already queued; not chip/search; lock does not block) |
| ☐ History: Verlauf leeren (Bestätigung) | ☐ History: Clear history (confirm) |
| ☐ History: Alle zur Warteschlange (Bestätigung; voller Verlaufs-Katalog; zuletzt gespielt zuerst; schon eingereiht übersprungen; Sperre blockiert nicht) | ☐ History: Add all to queue (confirm; full History catalog; newest last-played first; skip already queued; lock does not block) |
| ☐ History: Suche (Titel / Feed) | ☐ History: search (title / feed) |
| ☐ History: Sortierung (Neueste / Älteste; lastPlayedAt sonst updatedAt; persistiert) | ☐ History: sort (Newest / Oldest; lastPlayedAt else updatedAt; persisted) |
| ☐ History: Größenlimit (Einstellungen → Bibliothek; 50/100/200/500/Unbegrenzt Standard; Trim älteste lastPlayedAt; Fußnote) | ☐ History: size limit (Settings → Library; 50/100/200/500/Unlimited default; trim oldest lastPlayedAt; footnote) |
| ☐ History: Verbleibende Zeit (Info-Leiste; sortierte+gefilterte Liste; ~ bei unbekannten Dauern; played→0; nicht Clear-Katalog) | ☐ History: remaining time (info bar; visible sort+search list; ~ when unknowns; played→0; not Clear catalog) |
| ☐ Statistics/Echo: Zeitraum Diese Woche / Dieser Monat / Dieses Jahr / Gesamte Zeit (persistiert; lastPlayedAt sonst updatedAt; grobe Episoden-Stempel) | ☐ Statistics/Echo: time range This week / This month / This year / All time (persisted; lastPlayedAt else updatedAt; coarse episode stamps) |
| ☐ Favoriten (Stern; Full Player + EpisodeRow; VoiceOver Add/Remove) | ☐ Favorites (star; Full Player + EpisodeRow; VoiceOver Add/Remove) |
| ☐ Favoriten: Suche (Titel / Feed) | ☐ Favorites: search (title / feed) |
| ☐ Favoriten: Sortierung (Neueste / Älteste; favoritedAt; persistiert) | ☐ Favorites: sort (Newest / Oldest; favoritedAt; persisted) |
| ☐ Favoriten: Favoriten leeren (Bestätigung) | ☐ Favorites: Clear favorites (confirm) |
| ☐ Favoriten: Alle zur Warteschlange (Bestätigung; voller Favoriten-Katalog; schon eingereiht übersprungen; Sperre blockiert nicht) | ☐ Favorites: Add all to queue (confirm; full Favorites catalog; skip already queued; lock does not block) |
| ☐ Favoriten: Verbleibende Zeit (Info-Leiste; sortierte+gefilterte Liste; ~ bei unbekannten Dauern; nicht Clear-Katalog) | ☐ Favorites: remaining time (info bar; visible sort+search list; ~ when unknowns; not Clear catalog) |
| ☐ Archive / Restore (Listen + Full Player; `archived.json`) | ☐ Archive / restore (lists + Full Player; `archived.json`) |
| ☐ Archiviert: Suche (Titel / Feed) | ☐ Archived: search (title / feed) |
| ☐ Archiviert: Sortierung (Neueste / Älteste; archivedAt; persistiert) | ☐ Archived: sort (Newest / Oldest; archivedAt; persisted) |
| ☐ Archiviert: Alle wiederherstellen (Bestätigung) | ☐ Archived: Restore all (confirm) |
| ☐ Archiviert: Alle zur Warteschlange (Bestätigung; voller Archiv-Katalog; zuletzt archiviert zuerst; schon eingereiht übersprungen; Sperre blockiert nicht; stellt nicht wieder her) | ☐ Archived: Add all to queue (confirm; full Archived catalog; newest archived first; skip already queued; lock does not block; does not restore) |
| ☐ Archiviert: Verbleibende Zeit (Info-Leiste; sortierte+gefilterte Liste; ~ bei unbekannten Dauern; archived≠played; played→0; nicht Restore-all-Katalog) | ☐ Archived: remaining time (info bar; visible sort+search list; ~ when unknowns; archived≠played; played→0; not Restore all catalog) |
| ☐ Library search (lokal) | ☐ Library search (local) |
| ☐ Share Podcast / Episode (Player, Shownotes, EpisodeRow; URL: link→enclosure→feed; kein Deep-Link) | ☐ Share podcast / episode (Player, Shownotes, EpisodeRow; URL: link→enclosure→feed; no deep link) |
| ☐ Mit Position teilen (Full Player + Shownotes wenn aktuell; Text `Titel — Podcast (12:34)`; kein `#t=`) | ☐ Share with position (Full Player + Shownotes when current; text `Title — Podcast (12:34)`; no `#t=`) |
| ☐ Episoden-Website öffnen (Player / Shownotes / EpisodeRow; nur http(s) `link`; Systembrowser; kein WebView) | ☐ Open episode website (Player / Shownotes / EpisodeRow; http(s) `link` only; system browser; no WebView) |
| ☐ Podcast-Website öffnen (Feed-Detail ⋯ / Abonnements Kontextmenü; nur http(s) `siteLink`; Systembrowser; kein RSS-Fallback; ≠ Open podcast) | ☐ Open podcast website (Feed detail ⋯ / Subscriptions context; http(s) `siteLink` only; system browser; no RSS fallback; ≠ Open podcast) |
| ☐ Episoden-Link kopieren (Player / Shownotes / EpisodeRow; nur http(s) `link`; Zwischenablage; optional Medien-URL separat) | ☐ Copy episode link (Player / Shownotes / EpisodeRow; http(s) `link` only; pasteboard; optional Copy media URL separate) |
| ☐ Feed-Detail: Feed-URL kopieren (Zwischenablage; local-folder disabled) | ☐ Feed detail: Copy feed URL (pasteboard; local-folder disabled) |

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
| ☐ Appearance Theme System/Hell/Dunkel (`preferredColorScheme`; Backup) | ☐ Appearance Theme System/Light/Dark (`preferredColorScheme`; backup) |
| ☐ Settings: Suche (Titel / Fußnoten; leere Abschnitte aus; NavigationLinks bleiben) | ☐ Settings: search (titles / footnotes; empty sections hide; NavigationLinks stay) |
| ☐ Notify new episodes (default aus; lokal; ein Banner; kein Push) | ☐ Notify new episodes (default off; local; one banner; no push) |
| ☐ Per-feed settings (auto-DL / keep / notify / tags) | ☐ Per-feed settings (auto-DL / keep / notify / tags) |
| ☐ Per-feed Keep updated → Never: Refresh all überspringt; Einzel-Refresh OK | ☐ Per-feed Keep updated → Never: Refresh all skips; single-feed refresh OK |
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
- Queue played filter: Chips **Alle** / **Ungehört** / **Gehört** via `isPlayed` (nicht archive-aware); persistiert `AppSettings.queueFilter` (Default Alle). Pipeline Chip → Suche. Edit/Ziehen-Reorder aus bei Chip ≠ Alle oder Suche (wie Suche allein); Move to top/bottom bleibt id-basiert wenn entsperrt; **Shuffle** / **Clear queue** bleiben full-queue (Shuffle auch bei aktivem Filter, wenn entsperrt und ≥2).
  Queue played filter: chips **All** / **Unplayed** / **Played** via `isPlayed` (not archive-aware); persists `AppSettings.queueFilter` (default All). Pipeline chip → search. Edit/drag reorder off when chip ≠ All or search active (same as search alone); Move to top/bottom stays id-based when unlocked; **Shuffle** / **Clear queue** stay full-queue (Shuffle OK while filtering when unlocked and ≥2).
- Queue remaining time: Info-Leiste unter Chips — Summe `max(0, Dauer − Position)` über **sichtbare** Chip+Suche-Liste; unbekannte Dauern ausgelassen (`~`); live Position für aktuelle Episode; Wanduhr (kein Speed); EN/DE a11y.
  Queue remaining time: info bar under chips — sum `max(0, duration − position)` over **visible** chip+search list; unknown durations omitted (`~`); live position for current episode; wall-clock (no speed); EN/DE a11y.
- Downloads remaining time: Info-Leiste unter Chips — Summe `max(0, Dauer − Position)` über **sichtbare** Chip+Suche-Liste (**nicht** voller Offline-Katalog / Tab-Badge); unbekannte Dauern ausgelassen (`~`); live Position für aktuelle Episode; Wanduhr (kein Speed); EN/DE a11y.
  Downloads remaining time: info bar under chips — sum `max(0, duration − position)` over **visible** chip+search list (**not** full offline catalog / tab badge); unknown durations omitted (`~`); live position for current episode; wall-clock (no speed); EN/DE a11y.
- Inbox remaining time: Info-Leiste — Summe `max(0, Dauer − Position)` über **sichtbare** sortierte Inbox-Liste; unbekannte Dauern ausgelassen (`~`); live Position für aktuelle Episode; Wanduhr (kein Speed); **ausgeblendet bei Bibliothekssuche** (nicht Tab-Badge über Library-Hits); EN/DE a11y.
  Inbox remaining time: info bar — sum `max(0, duration − position)` over **visible** sorted Inbox list; unknown durations omitted (`~`); live position for current episode; wall-clock (no speed); **hidden during library search** (not tab-badge totals over library hits); EN/DE a11y.
- Inbox Add all to queue: Toolbar ⋯ → **Alle zur Warteschlange** mit Bestätigung (eligible Count = voller `inboxEpisodes`-Katalog minus bereits in Queue); `enqueueAllInbox` → `enqueue` Append in **newest-first Store-Reihenfolge** (nicht UI `inboxSort`); schon eingereiht übersprungen; **nicht** Bibliothekssuche (Menü während Suche deaktiviert); **Warteschlangen-Sperre blockiert nicht** (nur Reorder); EN/DE a11y.
  Inbox Add all to queue: toolbar ⋯ → **Add all to queue** with confirm (eligible count = full `inboxEpisodes` catalog minus already queued); `enqueueAllInbox` → `enqueue` append in **newest-first store order** (not UI `inboxSort`); skips already queued; **not** library search (menu disabled while searching); **Queue lock does not block** (reorder-only); EN/DE a11y.
- Favorites Add all to queue: Toolbar ⋯ → **Alle zur Warteschlange** mit Bestätigung (eligible Count = voller `favoriteEpisodes`-Katalog minus bereits in Queue); `enqueueAllFavorites` → `enqueue` Append in **newest-favorited-first Store-Reihenfolge** (nicht UI `favoritesSort` / nicht Suchfilter); schon eingereiht übersprungen; **Warteschlangen-Sperre blockiert nicht** (nur Reorder); EN/DE a11y.
  Favorites Add all to queue: toolbar ⋯ → **Add all to queue** with confirm (eligible count = full `favoriteEpisodes` catalog minus already queued); `enqueueAllFavorites` → `enqueue` append in **newest-favorited-first store order** (not UI `favoritesSort` / not searchable filter); skips already queued; **Queue lock does not block** (reorder-only); EN/DE a11y.
- Downloads Add all to queue: Toolbar ⋯ → **Alle zur Warteschlange** mit Bestätigung (eligible Count = voller `DownloadService.downloads`-Katalog minus bereits in Queue); `enqueueAllDownloads` → `enqueue` Append in **Katalogreihenfolge** (älteste abgeschlossene zuerst; nicht UI `downloadsSort` / nicht Chip/Suche); schon eingereiht übersprungen; **Warteschlangen-Sperre blockiert nicht** (nur Reorder); EN/DE a11y.
  Downloads Add all to queue: toolbar ⋯ → **Add all to queue** with confirm (eligible count = full `DownloadService.downloads` catalog minus already queued); `enqueueAllDownloads` → `enqueue` append in **catalog order** (oldest completed first; not UI `downloadsSort` / not chip/search); skips already queued; **Queue lock does not block** (reorder-only); EN/DE a11y.
- History Add all to queue: Toolbar ⋯ → **Alle zur Warteschlange** mit Bestätigung (eligible Count = voller `historyEpisodes`-Katalog minus bereits in Queue); `enqueueAllHistory` → `enqueue` Append in **newest-lastPlayed-first Store-Reihenfolge** (nicht UI `historySort` / nicht Suchfilter); schon eingereiht übersprungen; **Warteschlangen-Sperre blockiert nicht** (nur Reorder); EN/DE a11y.
  History Add all to queue: toolbar ⋯ → **Add all to queue** with confirm (eligible count = full `historyEpisodes` catalog minus already queued); `enqueueAllHistory` → `enqueue` append in **newest-lastPlayed-first store order** (not UI `historySort` / not searchable filter); skips already queued; **Queue lock does not block** (reorder-only); EN/DE a11y.
- Archived Add all to queue: Toolbar ⋯ → **Alle zur Warteschlange** mit Bestätigung (eligible Count = voller `archivedEpisodes`-Katalog minus bereits in Queue); `enqueueAllArchived` → `enqueue` Append in **newest-archived-first Store-Reihenfolge** (nicht UI `archivedSort` / nicht Suchfilter); schon eingereiht übersprungen; **stellt nicht wieder her / entarchiviert nicht**; **Warteschlangen-Sperre blockiert nicht** (nur Reorder); EN/DE a11y.
  Archived Add all to queue: toolbar ⋯ → **Add all to queue** with confirm (eligible count = full `archivedEpisodes` catalog minus already queued); `enqueueAllArchived` → `enqueue` append in **newest-archived-first store order** (not UI `archivedSort` / not searchable filter); skips already queued; **does not restore/unarchive**; **Queue lock does not block** (reorder-only); EN/DE a11y.
- All Episodes Add all to queue: Toolbar ⋯ → **Alle zur Warteschlange** mit Bestätigung (eligible Count = Soft-Cap `allEpisodes` neueste **500** minus bereits in Queue); `enqueueAllEpisodes` → `enqueue` Append in **newest-pubDate-first Store-Reihenfolge innerhalb Soft-Cap** (nicht UI `allEpisodesSort` / nicht Chip/Suche); schon eingereiht übersprungen; **Soft-Cap-Ehrlichkeit** (nie über neueste 500); **Warteschlangen-Sperre blockiert nicht** (nur Reorder); EN/DE a11y.
  All Episodes Add all to queue: toolbar ⋯ → **Add all to queue** with confirm (eligible count = soft-capped `allEpisodes` newest **500** minus already queued); `enqueueAllEpisodes` → `enqueue` append in **newest-pubDate-first store order within soft cap** (not UI `allEpisodesSort` / not chip/search); skips already queued; **soft-cap honesty** (never beyond newest 500); **Queue lock does not block** (reorder-only); EN/DE a11y.
- Feed Add all to queue: Feed-Detail ⋯ → **Alle zur Warteschlange** mit Bestätigung (eligible Count = voller `feed.episodes`-Katalog minus bereits in Queue); `enqueueAllFromFeed` → `enqueue` Append in **newest-pubDate-first** (explizite Sortierung; gleicher Geist wie Download all; nicht UI `feedEpisodeSort` / nicht Chip/Suche); schon eingereiht übersprungen; **einschließlich gehört und archiviert**; **Warteschlangen-Sperre blockiert nicht** (nur Reorder); EN/DE a11y.
  Feed Add all to queue: Feed detail ⋯ → **Add all to queue** with confirm (eligible count = full `feed.episodes` catalog minus already queued); `enqueueAllFromFeed` → `enqueue` append in **newest-pubDate-first** (explicit sort; same spirit as Download all; not UI `feedEpisodeSort` / not chip/search); skips already queued; **includes played and archived**; **Queue lock does not block** (reorder-only); EN/DE a11y.
- Favorites remaining time: Info-Leiste — Summe `max(0, Dauer − Position)` über **sichtbare** Sort+Suche-Liste (**nicht** voller Favoriten-Katalog / Clear-Count); unbekannte Dauern ausgelassen (`~`); live Position für aktuelle Episode; Wanduhr (kein Speed); EN/DE a11y.
  Favorites remaining time: info bar — sum `max(0, duration − position)` over **visible** sort+search list (**not** full favorites catalog / Clear count); unknown durations omitted (`~`); live position for current episode; wall-clock (no speed); EN/DE a11y.
- All Episodes remaining time: Info-Leiste — Summe `max(0, Dauer − Position)` über **sichtbare** Soft-Cap→Sort→Chip→Suche-Liste (**Soft-Cap-Ehrlichkeit:** nie über neueste 500 hinaus); unbekannte Dauern ausgelassen (`~`); live Position für aktuelle Episode; Wanduhr (kein Speed); EN/DE a11y.
  All Episodes remaining time: info bar — sum `max(0, duration − position)` over **visible** soft-cap→sort→chip→search list (**soft-cap honesty:** never beyond newest 500); unknown durations omitted (`~`); live position for current episode; wall-clock (no speed); EN/DE a11y.
- History remaining time: Info-Leiste — Summe `max(0, Dauer − Position)` über **sichtbare** Sort+Suche-Liste (**nicht** voller Verlaufs-Katalog / Clear-Count); Größenlimit-Katalog unverändert; **gespielt** (nicht aktuell) → 0 (Verlauf oft niedrig — korrekt; nützlich für in-progress); unbekannte Dauern ausgelassen (`~`); live Position für aktuelle Episode; Wanduhr (kein Speed); EN/DE a11y.
  History remaining time: info bar — sum `max(0, duration − position)` over **visible** sort+search list (**not** full history catalog / Clear count); size-limit catalog as-is; **played** (not current) → 0 (History totals may often be low — correct; useful for in-progress); unknown durations omitted (`~`); live position for current episode; wall-clock (no speed); EN/DE a11y.
- Feed remaining time: Info-Leiste — Summe `max(0, Dauer − Position)` über **sichtbare** Sort→Chip→Suche-Liste (**nicht** full-feed / Download all / Mark all as played / Add all to queue Eligibility); unbekannte Dauern ausgelassen (`~`); **gespielt** (nicht aktuell) → 0; live Position für aktuelle Episode; Wanduhr (kein Speed); EN/DE a11y.
  Feed remaining time: info bar — sum `max(0, duration − position)` over **visible** sort→chip→search list (**not** full-feed / Download all / Mark all as played / Add all to queue eligibility); unknown durations omitted (`~`); **played** (not current) → 0; live position for current episode; wall-clock (no speed); EN/DE a11y.
- Archived remaining time: Info-Leiste — Summe `max(0, Dauer − Position)` über **sichtbare** Sort+Suche-Liste (**nicht** voller Archiv-Katalog / Restore-all-Count); **archiviert ≠ gespielt** — normale Dauer−Position-Regeln; **gespielt** (nicht aktuell) → 0; unbekannte Dauern ausgelassen (`~`); live Position für aktuelle Episode; Wanduhr (kein Speed); EN/DE a11y.
  Archived remaining time: info bar — sum `max(0, duration − position)` over **visible** sort+search list (**not** full archived catalog / Restore all count); **archived ≠ played** — normal duration−position rules; **played** (not current) → 0; unknown durations omitted (`~`); live position for current episode; wall-clock (no speed); EN/DE a11y.
- Add from Clipboard: nur wenn Zwischenablage eine getrimmte http(s)-URL mit Host hält (erste Zeile); Toolbar + URL-Tab in Add podcast; öffnet bestehende Preview → Confirm Subscribe; **kein** Auto-Abo beim Start; **kein** OPML aus Zwischenablage.
  Add from Clipboard: only when the clipboard holds a trimmed http(s) URL with a host (first line); toolbar + URL tab in Add podcast; opens existing preview → Confirm Subscribe; **no** auto-subscribe on launch; **no** OPML from clipboard.
- Queue lock: Toolbar Lock/Unlock (`lock.fill` / `lock.open`) + Settings → Queue Toggle; persistiert `AppSettings.queueLocked` (Default aus). Gesperrt = kein Edit/Ziehen-Reorder, **kein Mischen (Shuffle)** und kein Move to top/bottom; **Einreihen / Play Next / Remove / Archive-Swipe / Clear queue bleiben** (nur Reihenfolge-Sperre, wie Android `prefQueueLocked`).
  Queue lock: toolbar Lock/Unlock (`lock.fill` / `lock.open`) + Settings → Queue toggle; persists `AppSettings.queueLocked` (default off). Locked = no Edit/drag reorder, **no Shuffle**, and no Move to top/bottom; **enqueue / Play Next / Remove / Archive swipe / Clear queue still work** (reorder lock only, mirrors Android `prefQueueLocked`).
- Queue Shuffle: Toolbar ⋯ → **Mischen** öffnet **immer** `confirmationDialog`; `shuffleQueue` mischt die **volle** `queue` (Fisher–Yates; nicht Chip/Suche); persistiert wie `moveQueue` (`queue` didSet). **Sperre blockiert Shuffle** (Reorder-only, wie Edit/`onMove`); deaktiviert bei `queue.count` < 2. Stoppt Wiedergabe nicht / ändert Fortschritt/Played/Downloads nicht. Aktuell spielende Episode behält **dieselbe Episode-id** und **wandert mit neuer Listenposition** (nicht am gleichen Index fixiert); Continuous-Next weiter über `nextQueueEpisode(after:)` per id. EN/DE a11y.
  Queue Shuffle: toolbar ⋯ → **Shuffle** **always** opens `confirmationDialog`; `shuffleQueue` shuffles the **full** `queue` (Fisher–Yates; not chip/search); persists like `moveQueue` (`queue` didSet). **Lock blocks Shuffle** (reorder-only, same as Edit/`onMove`); disabled when `queue.count` < 2. Does not stop playback / change progress / mark played / delete downloads. Currently playing keeps the **same episode id** and **moves with its new list index** (not pinned at the same index); continuous next still via `nextQueueEpisode(after:)` by id. EN/DE a11y.
- Clear queue confirm: Toolbar ⋯ → Warteschlange leeren öffnet **immer** `confirmationDialog` mit **voller** `queue.count` (nicht Chip/Suche) + Hinweis (kein Stopp der Wiedergabe / kein Fortschritts-/Played-/Download-Löschen); `clearQueue` nur nach Bestätigen; bei leerer Queue deaktiviert; **Sperre blockiert Clear nicht**.
  Clear queue confirm: toolbar ⋯ → Clear queue **always** opens `confirmationDialog` with **full** `queue.count` (not chip/search) + honesty (does not stop playback / change progress / mark played / delete downloads); `clearQueue` only after confirm; disabled when empty; **lock does not block Clear**.
- Queue remove confirm: Queue-Swipe **Remove** und Full-Player Queue-Menü **Aus Warteschlange entfernen** öffnen **immer** `confirmationDialog` mit Episodentitel; `removeFromQueue` nur nach Bestätigen. Honesty: nur Queue-Eintrag — kein Download-Löschen / nicht als gehört / stoppt Wiedergabe nicht (bestehende API). Clear-queue-Confirm unverändert. EN/DE a11y.
  Queue remove confirm: Queue swipe **Remove** and Full Player Queue menu **Remove from queue** **always** open `confirmationDialog` with episode title; `removeFromQueue` only after confirm. Honesty: queue entry only — does not delete download / mark played / stop playback (existing API). Clear queue confirm unchanged. EN/DE a11y.
- Continuous playback: Toggle Standard **an**; aus = Episode-Ende ohne Queue-Advance (Mark played / Progress bleiben); Sleep-Timer Ende der Episode stoppt weiterhin ohne Advance.  
  Continuous playback: toggle default **on**; off = episode end without queue advance (mark played / progress still apply); end-of-episode sleep timer still stops without advance.
- Show remaining time: Settings Toggle Standard **aus**; an = Mini + Full rechts −Restzeit statt Dauer; Links Position; Tippen auf Full-Player-Label toggelt.  
  Show remaining time: Settings toggle default **off**; on = mini + full right −remaining instead of duration; left position; tap full-player label toggles.
- Rewind after pause: Settings → Playback Picker Off/1/2/3/5/10 (Standard **2**); nur nach echter Pause ≥1s der aktuellen Episode — nicht bei Cold-Play / erstem Start; fester Betrag (nicht Android-Zeitstufen).  
  Rewind after pause: Settings → Playback picker Off/1/2/3/5/10 (default **2**); only after a real pause ≥1s of the current item — not cold play / first start; fixed amount (not Android elapsed tiers).
- Smart mark as played: Settings → Playback Picker Off/15/30/60/120 (Standard **30**); Aus (0) = nur natürliches Ende oder manuell als gehört — kein Near-End-Scrub.  
  Smart mark as played: Settings → Playback picker Off/15/30/60/120 (default **30**); Off (0) = only natural end or explicit mark — not near-end scrub.

Siehe auch: [FEATURE-MATRIX.md](FEATURE-MATRIX.md), [ios/README.md](../../ios/README.md).
