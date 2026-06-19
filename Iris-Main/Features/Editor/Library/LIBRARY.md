# Editor Component Library

Reusable SwiftUI primitives for building a dynamic Iris editor UI. The first pass validates components in isolation via the home-screen **Component Library** showcase; it does not modify live editor assembly.

## Structure

- `Shared/` — component specs, parameter bounds, context/action adapters
- `Timeline/` — ruler, tracks, surface, layout presets
- `Tools/` — tool chrome, parameter controls, clip/caption tool compositions
- `Playback/` — viewer, transport, section composition
- `Navigation/` — bottom navigation
- `Chrome/` — glass shell, collection-based toolbar
- `Showcase/` — sample data and preview screen

## Deferred integration

The following are intentionally unchanged in this pass:

- `EditorCanvasView`
- `EditorTabBar`
- `TimelineSectionView`
- `EditorContainerView` bottom chrome wiring
- Legacy `Features/Editor/Workspace` JIT layout code (reference only; do not build new primitives against it)

After showcase validation, wire library components into those integration points.

## Bottom chrome primitives

New tiered bottom chrome lives under `Library/Chrome/`:

- `EditorBottomChromePlan` — tiers, actions, parameter groups, density
- `EditorBottomChromeStack` — glass subchrome + dock slot
- `EditorParameterTierView` — chip-selected parameter groups
- `EditorImmediateActionsRow` — dynamic action buttons
- `EditorSpatialParameterTierView` — placeholder for future 2D controls

Validate in **Component Library → Chrome → Bottom Chrome Preview Lab** before live editor wiring.

## Design principles

- Prefer enum-backed configuration (`EditorComponentSize`, `EditorComponentAxis`) over free-form numeric layout parameters.
- Parameter controls accept a `Binding` plus optional bounds; domain keys (e.g. `temperature`, `volumeGain`) belong in adapters, not in reusable controls.
- Toolbars render a **collection** of `EditorToolbarItem` values supplied by the caller; they do not encode every combination as a variant enum.
- Zero nested menus: use flat pills, segmented controls, and inline expansion instead.

## Showcase

Open **Component Library** from the home hero card to browse categories, size variants, and interactive demo bindings.
