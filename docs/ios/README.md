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
