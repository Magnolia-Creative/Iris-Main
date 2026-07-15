# AGENTS.md

## Cursor Cloud specific instructions

### Role

Native **iOS 26.2** SwiftUI client for Iris. Talks to **Iris-Backend** at `http://127.0.0.1:8000` (`AppConfiguration.backendBaseURL`). Requires **Clerk** sign-in.

### macOS required

This repo **cannot** be built or run on Linux cloud VMs (no Xcode, CocoaPods, or Simulator). Development happens on a Mac:

```bash
cd Iris-Main   # repo root containing Podfile
pod install
open Iris-Main.xcworkspace
```

Then Run from Xcode (simulator or device).

### Backend dependency

For end-to-end flows, run Iris-Backend locally (see `Iris-Backend/AGENTS.md`): Postgres, Redis, FastAPI on port 8000.

### Packages

Do not add Swift packages or CocoaPods yourself; ask the user to add dependencies per `user-managed-package-additions` rule.

### Tests

Prefer non-UI unit tests. Do not run Xcode Simulator UI tests unless explicitly requested.
