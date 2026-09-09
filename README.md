# Iris

**Iris** is a native iOS video-editing app built around natural-language interaction. It combines a timeline editor, transcript-aware workflows, semantic media search, realtime voice input, and AI-assisted editing intents in a SwiftUI experience.

> This is the iOS client for Iris. Its API, data, and agent layer live in [Iris-Backend](https://github.com/Magnolia-Creative/Iris-Backend).

## Highlights

- Build and edit video projects on a native timeline
- Create and review structured edits from natural-language prompts
- Search source media semantically and through transcribed dialogue
- Generate, view, and edit captions tied to clip timing
- Import and process source media with project-scoped organization
- Use realtime voice transcription and voice-driven intents
- Preview rendering, effects, and output aspect-ratio choices

## Tech stack

- SwiftUI with a feature-oriented app structure
- Clerk for authentication
- VideoLab for video-processing and rendering primitives
- MobileCLIP for on-device semantic indexing support
- A FastAPI companion service for media processing, agent runs, and cloud search

## Project structure

```text
Iris-Main/
├── App/                    # App entry point, authenticated root, and developer tools
├── Features/               # Editor, home, import, agent, captions, and search workflows
├── Shared/                 # Domain models, services, components, and design system
└── Assets.xcassets/        # App assets

Iris-MainTests/             # Unit tests
```

## Getting started

**Requirements:** Xcode with the iOS 18 SDK or later, CocoaPods, and an Iris backend available locally or in a configured environment.

```bash
git clone https://github.com/Magnolia-Creative/Iris-Main.git
cd Iris-Main
pod install
open Iris-Main.xcworkspace
```

Choose the `Iris-Main` scheme and run it on a simulator or device. Debug builds point to `http://127.0.0.1:8000`; start the companion backend locally before exercising backend-powered flows.

## Backend setup

The app works with the [Iris-Backend](https://github.com/Magnolia-Creative/Iris-Backend) repository. For local development:

```bash
git clone https://github.com/Magnolia-Creative/Iris-Backend.git
cd Iris-Backend
# Follow the backend README to configure the environment and start the API.
```

App endpoints and debug/production configuration are centralized in `Iris-Main/Shared/Infrastructure/Configuration/AppConfiguration.swift`.

## Semantic search models

The semantic feature can use MobileCLIP Core ML models. See [Features/Semantic/README.md](Iris-Main/Features/Semantic/README.md) for model setup and expected runtime behavior.

## Testing

Run the `Iris-MainTests` target from Xcode, or use:

```bash
xcodebuild test \
  -workspace Iris-Main.xcworkspace \
  -scheme Iris-Main \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Iris repositories

| Repository | Purpose |
| --- | --- |
| [Iris-Main](https://github.com/Magnolia-Creative/Iris-Main) | The native SwiftUI iOS application. |
| [Iris-Backend](https://github.com/Magnolia-Creative/Iris-Backend) | FastAPI API, AI agent workflows, data persistence, and media-processing services. |

## License

Copyright 2026 Magnolia Creative. This project is licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution information.
