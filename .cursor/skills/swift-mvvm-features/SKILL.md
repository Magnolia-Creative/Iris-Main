---
name: swift-mvvm-features
description: Build Swift feature code using MVVM structure with clear View, ViewModel, and Model boundaries. Use when implementing new iOS features, adding screens, or expanding existing Swift app functionality.
---

# Swift MVVM Features

## Purpose

Use MVVM as the default architecture when building or extending Swift features.

## Apply When

- Implementing a new SwiftUI or UIKit feature
- Adding a new screen, flow, or module
- Expanding feature behavior with state, networking, or business rules

## Core Rules

1. Keep UI code in `View` types only.
2. Put presentation logic and UI state in `ViewModel`.
3. Keep domain/data entities in `Model` types or services.
4. Inject dependencies into `ViewModel` (services, repositories, clients).
5. Keep `View` passive: bind to state and forward user intents.
6. Allow non-MVVM structure only when there is a clear reason; explain rationale in code comments or PR notes.

## Feature Build Workflow

1. Define feature models and service interfaces.
2. Create a `ViewModel` with:
   - observable UI state
   - intent-handling methods (for example, `load()`, `submit()`, `retry()`)
   - async/error handling and mapping into view-friendly state
3. Build the `View`:
   - render from `ViewModel` state
   - route user actions to `ViewModel` intents
4. Add previews/tests where practical:
   - `ViewModel` tests for state transitions and error handling
   - snapshot/UI checks as needed for the view layer

## Design Constraints

- No networking or persistence directly inside `View`.
- No direct UI framework types in pure model/service layers.
- Prefer protocol-based dependencies for testability.
- Prefer one primary `ViewModel` per screen or tightly-coupled subflow.

## Exception Policy (Balanced)

MVVM is the default. Small helper views or trivial one-off states can stay local to a `View` if creating a full `ViewModel` adds unnecessary complexity. When deviating, document why.
