# ios/ — AntennaPod for iOS

Fork-only SwiftUI shell. Playback via AVFoundation; networking/downloads via URLSession; persistence native (GRDB or SQLite.swift). Shared logic comes from `shared/kmp` (XCFramework).

## Status (Phase 0)

Scaffold only: placeholder SwiftUI sources and CI that builds the KMP iOS framework on macOS. Full Xcode app target (subscribe → stream/download) follows in Phase 1.

## Layout

```
ios/
├── README.md
└── AntennaPod/
    ├── AntennaPodApp.swift
    └── ContentView.swift
```

## Local setup (Phase 1+)

1. Build the shared framework on a Mac: `./gradlew -p shared/kmp linkDebugFrameworkIosSimulatorArm64`
2. Open / create the Xcode project under `ios/` and link `AntennaPodShared.framework`
3. Run on Simulator

See `docs/ios/PLAN.md` and `docs/ios/FEATURE-MATRIX.md`.
