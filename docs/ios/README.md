# AntennaPod iOS (Fork)

Dokumentation für den iOS-Port mit schmalem KMP-Kern. Liegt nur im Fork; Upstream-Android-Module bleiben unberührt.

| Dokument | Inhalt |
|----------|--------|
| [PLAN.md](PLAN.md) | Architektur-Empfehlung, Phasen, Risiken |
| [FEATURE-MATRIX.md](FEATURE-MATRIX.md) | Feature-Parität mit Gewichten und Status |
| [MERGE-PLAYBOOK.md](MERGE-PLAYBOOK.md) | Upstream mergen, Fork-only-Pfade, CI |
| [BETA-TESTING.md](BETA-TESTING.md) | Beta-Checkliste (DE/EN) für manuelle Tests |

Download errors (iOS): Die Fehleransicht exportiert den vollständigen persistierten Ringpuffer in Store-Reihenfolge (neueste zuerst) als Plain Text — Copy in die Zwischenablage oder ShareLink mit lokalisiertem Header. Suche und OPML sind nicht Teil dieses Exports.

Download errors (iOS): The error screen exports the full persisted ring buffer in store order (newest first) as plain text — Copy to the pasteboard or ShareLink with a localized header. Search and OPML are not part of this export.

Podcast chapters URL (iOS): Open / Copy / Share acts on the feed-provided remote URL; ShareLink uses an openable http(s) URL when available and otherwise the raw string. This is not the in-app chapter TOC export.
Podcast chapters URL (iOS): Open / Copy / Share nutzt nur die entfernte, vom Feed gelieferte URL; ShareLink verwendet eine öffnende http(s)-URL, sonst den Rohstring. Das ist nicht der In-App-Kapitel-TOC-Export.

Verwandte Ordner: `shared/kmp/`, `shared/specs/`, `ios/`.

Downloads Archive all (iOS): The Downloads toolbar menu archives only non-archived completed downloads from the full catalog, ignoring chip/podcast/search/sort filters. It writes the `archivedAtById` side map in one batch; archived ≠ played and no files, queue entries, playback state, or auto-delete-after-playing behavior are changed.
Downloads Alle archivieren (iOS): Das Downloads-Menü archiviert nur nicht archivierte, abgeschlossene Downloads aus dem vollständigen Katalog und ignoriert Chip-/Podcast-/Such-/Sortierfilter. Die `archivedAtById`-Map wird gesammelt geschrieben; archiviert ≠ gehört, Dateien, Queue, Wiedergabestatus und Auto-Löschen nach Wiedergabe bleiben unverändert.

Inbox Archive all (iOS): The Inbox toolbar menu confirms before archiving only non-archived episodes from the full Inbox catalog in newest-first store order, ignoring podcast/episode-type/search/sort filters. It uses the existing batched `archivedAtById` write; archived ≠ played and playback, downloads, and queue entries are unchanged.
Inbox Alle archivieren (iOS): Das Inbox-Menü fragt vor dem Archivieren nur nicht archivierter Episoden aus dem vollständigen Posteingangs-Katalog in der neuesten Reihenfolge nach. Podcast-/Episodentyp-/Such-/Sortierfilter werden ignoriert; die bestehende gesammelte `archivedAtById`-Map wird verwendet. Archiviert ≠ gehört, Wiedergabe, Downloads und Queue bleiben unverändert.
Inbox Mark all as unplayed (iOS): The Inbox toolbar confirms marking played episodes from the full stored feed catalog behind Inbox as unplayed, including archived episodes; podcast/episode-type/search/sort filters are ignored. It uses per-episode `markUnplayed` and does not delete downloads, clear the queue, stop playback, or unarchive.
Inbox Alle als ungehört markieren (iOS): Das Inbox-Menü bestätigt, gehörte Episoden aus dem vollständigen gespeicherten Feed-Katalog hinter dem Posteingang als ungehört zu markieren, einschließlich archivierter Episoden; Podcast-/Episodentyp-/Such-/Sortierfilter werden ignoriert. Pro Episode wird `markUnplayed` verwendet; Downloads, Queue und Archivierung bleiben unverändert.
Inbox Add all unplayed to queue (iOS): The Inbox toolbar confirms appending unplayed, non-archived, not-yet-queued episodes from the full current Inbox catalog in newest-first store order, ignoring podcast/episode-type/search/sort filters. Inbox is normally already unplayed-only, so this can match Add all to queue in practice; it remains a distinct action and uses `enqueue` without being blocked by Queue lock.
Inbox Alle ungehörten zur Warteschlange (iOS): Das Inbox-Menü bestätigt das Einreihen ungehörter, nicht archivierter und noch nicht eingereihter Episoden aus dem vollständigen aktuellen Inbox-Katalog in neuester Reihenfolge; Podcast-/Episodentyp-/Such-/Sortierfilter werden ignoriert. Da der Inbox normalerweise nur ungehörte Episoden enthält, kann dies praktisch Alle zur Warteschlange entsprechen; es bleibt eine eigene Aktion und nutzt `enqueue`, ohne durch die Warteschlangen-Sperre blockiert zu werden.

Queue Mark all as played (iOS): The Queue toolbar menu confirms marking unplayed, non-archived episodes in the full persisted queue as played, ignoring played/podcast/search filters. It snapshots IDs and calls `markPlayed` per episode, so the marked entries leave Queue under existing semantics; archived unplayed entries are skipped, auto-delete-after-playing may apply, and Queue lock does not block the action.
Queue Alle als gehört markieren (iOS): Das Queue-Menü bestätigt, ungehörte, nicht archivierte Episoden aus der vollständigen gespeicherten Warteschlange als gehört zu markieren; Played-/Podcast-/Suchfilter werden ignoriert. IDs werden vorab erfasst und pro Episode mit `markPlayed` verarbeitet, daher verlassen markierte Einträge die Warteschlange gemäß der bestehenden Semantik; archivierte ungehörte Einträge werden übersprungen, Auto-Löschen kann greifen und die Queue-Sperre blockiert die Aktion nicht.
Queue Mark all as unplayed (iOS): The Queue toolbar menu confirms marking played episodes in the full persisted queue as unplayed, including archived episodes; played/podcast/search filters are ignored. It snapshots IDs and calls `markUnplayed` per episode, so entries stay in Queue without deleting downloads, stopping playback, or unarchiving; Queue lock does not block the action.
Queue Alle als ungehört markieren (iOS): Das Queue-Menü bestätigt, gehörte Episoden aus der vollständigen gespeicherten Warteschlange als ungehört zu markieren, einschließlich archivierter Episoden; Played-/Podcast-/Suchfilter werden ignoriert. IDs werden vorab erfasst und pro Episode mit `markUnplayed` verarbeitet, daher bleiben Einträge in der Warteschlange; Downloads, Wiedergabe und Archivierung bleiben unverändert, und die Warteschlangen-Sperre blockiert die Aktion nicht.
