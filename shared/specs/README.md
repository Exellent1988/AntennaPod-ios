# shared/specs — Verhaltens- und Golden-Tests

Plattformneutrale Fixtures und erwartete Snapshots. Sowohl KMP-`commonTest` als auch spätere iOS-Tests sollen dieselben Dateien lesen.

## Layout

```
shared/specs/
├── feeds/golden/     # RSS/Atom Fixtures (portiert aus :parser:feed Tests)
└── README.md
```

## Regeln

- Fixtures hier hinzufügen, nicht nur unter `parser/feed/src/test/resources/` duplizieren ohne Verweis
- Erwartete Parser-Ergebnisse als JSON/Snapshot neben der Fixture oder in KMP-Tests dokumentieren
- Schema-/Migrationsverträge für Persistenz kommen später unter `shared/specs/schema/`
