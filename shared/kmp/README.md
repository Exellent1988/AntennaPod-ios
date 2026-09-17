# shared/kmp — AntennaPod Shared Core (Kotlin Multiplatform)

Fork-only. Not part of the Upstream Android Gradle tree (`settings.gradle` unchanged).

## Purpose

Platform-neutral Kotlin for:

- Domain models (copy of `:model`, not a replace)
- Feed parsing, OPML, discovery/sync protocol clients
- Pure business rules (filter, queue policy, auto-download candidates)

iOS consumes an XCFramework / Swift-friendly binary. Android may depend on this module later (Phase 6); until then Upstream Java stays authoritative for the Android app.

## Layout

```
shared/kmp/
├── settings.gradle.kts
├── build.gradle.kts
├── src/commonMain/kotlin/…
└── src/commonTest/kotlin/…
```

## Build

From the repository root (uses the root Gradle wrapper):

```bash
./gradlew -p shared/kmp jvmTest
```

iOS frameworks (requires macOS + Xcode):

```bash
./gradlew -p shared/kmp linkDebugFrameworkIosSimulatorArm64
```

## Rules

- No Android-only APIs in `commonMain`
- Do not delete or rewrite Upstream `:model` / `:parser:feed` for iOS
- Golden feed fixtures live in `shared/specs/`; tests should load them from there
