# Merge-Playbook (Fork ↔ Upstream)

Ziel: `AntennaPod/AntennaPod` (`develop`) regelmäßig in diesen Fork holen, ohne iOS/KMP-Arbeit zu zerstören und ohne Upstream-Module für iOS umzubauen.

## Fork-only-Pfade

Diese Pfade existieren nur im Fork und sollen bei Upstream-Merges **nicht** kollidieren:

- `docs/ios/`
- `shared/`
- `ios/`
- `.github/workflows/ios.yml`
- `.github/workflows/shared-kmp.yml`

Alles unter `app/`, `model/`, `parser/`, `net/`, `playback/`, `storage/`, `ui/`, `system/`, `event/` behandelt wie Upstream: keine iOS-bedingten Änderungen.

## Remotes (einmalig)

```bash
git remote add upstream https://github.com/AntennaPod/AntennaPod.git
git fetch upstream
```

## Regelmäßiger Sync

```bash
git checkout develop
git fetch upstream
git merge upstream/develop
# Bei Konflikten: Upstream in Android-Pfaden bevorzugen;
# Fork-only-Pfade behalten.
git push origin develop
```

Feature-Arbeit immer auf Branches vom aktuellen `develop`, z. B. `cursor/…`.

## Konflikt-Heuristik

| Pfad | Vorgehen |
|------|----------|
| Upstream-Android-Module | Upstream übernehmen; eigene Edits dort vermeiden |
| `shared/`, `ios/`, `docs/ios/` | Fork behalten |
| Root-Dateien (`settings.gradle`, CI) | Nur ergänzen, Upstream-Logik nicht umbiegen |

`settings.gradle` der Android-App **nicht** zwingend um KMP erweitern. `shared/kmp` ist ein eigenständiges Gradle-Projekt (siehe `shared/kmp/README.md`), damit `:app:assembleDebug` Upstream-gleich bleibt.

## CI

| Workflow | Zweck |
|----------|--------|
| Bestehende Android-Workflows | Unverändert; Upstream-Parität |
| `shared-kmp.yml` | KMP `commonTest` / Compile auf Linux |
| `ios.yml` | macOS-Runner: XCFramework-Anbindung + `xcodebuild` (wenn Xcode-Projekt vorhanden) |

Ein grünes `:app:assembleDebug` ist die Merge-Gate für Android. iOS/KMP-Rot blockiert Upstream-Sync nicht, blockiert aber iOS-Feature-Merges.

## Checkliste vor Upstream-Merge-PR in den Fork

- [ ] `./gradlew :app:assembleDebug` lokal oder CI grün
- [ ] Keine Diffs in Android-Modulen außer dem Upstream-Merge selbst
- [ ] Fork-only-Ordner noch vorhanden und referenziert
- [ ] FEATURE-MATRIX Status nur anfassen, wenn Features wirklich landeten
