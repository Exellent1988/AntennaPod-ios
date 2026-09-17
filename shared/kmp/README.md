# shared/kmp — AntennaPod Shared Core (Kotlin Multiplatform)

Fork-only. Not part of the Upstream Android Gradle tree (`settings.gradle` unchanged).

## Purpose

Platform-neutral Kotlin for:

- Domain models under `shared.model` (Kotlin copy of `:model` fields needed for parsing/UI, not a replace)
- Feed parsing via `FeedParser` (RSS 2 / Atom; ksoup XML)
- Later: OPML, discovery/sync protocol clients, business rules

iOS consumes an XCFramework / Swift-friendly binary. Android may depend on this module later (Phase 6); until then Upstream Java stays authoritative for the Android app.

## Layout

```
shared/kmp/
├── settings.gradle.kts
├── build.gradle.kts
├── src/commonMain/kotlin/…/model/…
├── src/commonMain/kotlin/…/parser/FeedParser.kt
├── src/commonTest/kotlin/…
└── src/jvmTest/kotlin/…/GoldenFeedParserTest.kt
```

## Build

From the repository root (uses the root Gradle wrapper):

```bash
./gradlew -p shared/kmp jvmTest
```

Golden fixtures are read from `shared/specs/feeds/golden/` (path relative to `shared/kmp` when tests run).

iOS frameworks (requires macOS + Xcode):

```bash
./gradlew -p shared/kmp linkDebugFrameworkIosSimulatorArm64
```

## Rules

- No Android-only APIs in `commonMain`
- Do not delete or rewrite Upstream `:model` / `:parser:feed` for iOS
- Golden feed fixtures live in `shared/specs/`; JVM golden tests load them from there
