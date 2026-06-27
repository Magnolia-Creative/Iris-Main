# Natural-Language Editor UI Pipeline

## Desired Outcome

Build a natural-language pipeline that lets a user describe how they want the video editor interface to change, then maps that request onto the editor's existing component library, component states, and rendering paths.

The goal is not to invent new UI primitives or generate SwiftUI. The system should interpret a prompt, resolve it into valid choices from the existing editor component library, validate those choices against the editor's layout rules, apply them through a single UI state path, and let the current SwiftUI rendering code display the result.

Example prompts include:

- "Make the timeline bigger"
- "Hide the parameter controls"
- "Give me more room to preview the video"
- "Set me up for color correction"
- "Make the interface less cluttered"
- "Focus on editing clips"
- "Make everything bigger"
- "Make this easier to use"

Some prompts should resolve directly to one component state change. Others should resolve to a coordinated workspace arrangement that changes several existing components together.

## Component Library As Source Of Truth

The editor component library under `Iris-Main/Features/Editor/Library` should be treated as the source of truth for available UI primitives and their supported states.

The pipeline should use existing concepts such as:

- `EditorComponentID`
- `EditorComponentSize`
- `EditorComponentCategory`
- `EditorComponentRegistry`
- `EditorBottomChromePlan`
- `EditorBottomChromeDensity`
- `EditorParameterGroup`
- Existing context/action adapter types such as `EditorTimelineContext`, `EditorPlaybackContext`, and related action structs

The resolver should not output arbitrary layout instructions, view hierarchies, frame values, or generated SwiftUI. It should only select from existing component identifiers, supported component states, editor spaces, parameter groups, tool/chrome concepts, and any explicit layout concepts introduced for this pipeline.

## Rendering Direction

The existing JIT workspace code can be used as reference, but it should not be assumed to be the final rendering foundation for this work.

The desired direction is a library-native rendering pipeline:

```text
Resolved editor UI intent
-> validated library layout/state model
-> editor UI state coordinator
-> renderer that instantiates existing Library components
-> current SwiftUI component rendering
```

The renderer should reuse the existing component primitives rather than recreate them. If a new renderer is needed, it should be responsible only for arranging and configuring the existing library components from validated state.

## Prompt Pipeline

The final system should have separable stages:

```text
User prompt
-> capture compact editor/UI context
-> local direct-command resolution
-> remote/model-backed resolution when needed
-> deterministic validation and normalization
-> apply through the existing editor UI state path
-> render using existing components
```

The local resolver should handle clear direct commands before involving the backend. The remote resolver should be hidden behind a protocol or service boundary so the app is not coupled to a specific model provider.

The backend should receive a compact, purpose-built context rather than the entire application state. Useful context includes active editor space, selected clip/caption state, active parameter group, visible components, current component states, available components and states, screen class/orientation, review mode, caption chrome state, and relevant editor capabilities.

## Resolution Categories

Resolver output should classify requests as:

- `direct`: a clear component and state were specified.
- `contextual`: the request can be resolved using current editor context.
- `workspace`: the user described a broader working goal requiring several UI changes.
- `ambiguous`: multiple plausible interpretations exist.
- `unsupported`: the requested behavior cannot be represented with existing components.

Direct and high-confidence contextual/workspace requests may execute immediately after validation. Ambiguous requests should return structured clarification options. Unsupported requests should explain which part of the request cannot be represented by the current UI system.

## Validation Requirements

Before applying any resolved layout or component state, validation must confirm:

- Every referenced component exists in the component registry.
- Every requested state is supported by that component.
- The resulting combination is renderable.
- Required UI affordances remain reachable.
- Tool, parameter group, and panel choices are valid in the current editor context.
- The proposal does not conflict with existing layout and interaction rules.

Model output should never be trusted to enforce layout correctness. Validation and normalization must be deterministic.

## State Application And Reversibility

Prompt-driven UI changes should terminate in the same state mutation path used by manual UI interactions wherever possible.

The resolver should produce data only. It should not instantiate views or directly modify SwiftUI hierarchy. A coordinator or equivalent state owner should apply the validated result, publish state changes, and let the renderer update.

UI changes should be reversible as a single operation, even when a prompt changes several component states together. This UI-layout undo/history should remain distinct from timeline media-edit undo unless the app later introduces a unified editor history.

## Backend Role

The backend should provide structured model-backed interpretation for vague or workspace-level requests. It should return decodable data using the same component/state vocabulary as the client.

The backend should not return SwiftUI, arbitrary layout instructions, or unsupported component names. Any backend response should still be validated client-side before application.

## Testing Expectations

The first implementation should include focused tests for:

- "Make the timeline bigger"
- "Hide the parameter controls"
- "Give me more room to preview the video"
- "Set me up for color correction"
- "Make the workspace less cluttered"
- "Make everything bigger"
- "Make this better"
- A request naming a component or state that does not exist

Tests should cover local resolution, backend/remote boundary behavior with fakes, deterministic validation, ambiguity handling, and final state application into the renderer path.

## Progress Notes

This section should be continuously updated as the project evolves.

### 2026-06-19

- Initial repository inspection found that the editor currently has both a legacy/live shell path and a JIT workspace path.
- The component library under `Iris-Main/Features/Editor/Library` is the intended source of reusable UI primitives.
- The existing JIT workspace renderer is useful reference material, but the desired pipeline likely needs a library-native layout model and renderer or significant changes to the current render flow.
- Current known live entry points include `EditorContainerView`, `EditorCanvasView`, `JITWorkspaceCoordinator`, and `JITWorkspaceLayoutRenderer`.
- Existing backend infrastructure includes a UI workspace planning endpoint and planner service, but the final design should align backend output with the component library's real component/state vocabulary.

### 2026-06-27

- The live editor canvas now routes through `EditorJITRenderView`, with playback, timeline, bottom dock, and bottom action chrome driven by `EditorJITRenderState`.
- The normal prompt input and voice/text entry live in the JIT-native `IntelligenceComponent`.
- The timeline is intentionally back on native JIT primitives (`TimelineOrganizerComponent` / `TimelineTrackComponent`) rather than the older `TimelineSectionView` adapter. This preserves the goal that the editor UI is composed from the JIT/component-library primitives.
- Still not JIT-native: header/home/project title chrome, import panel content, export panel content, captions editing chrome, prompt edit review approval controls, agent cut review bar, aspect settings overlay, and system photo/file import sheets.
- Current fidelity discrepancy: the native JIT timeline primitives are visually and behaviorally lower-fidelity than the older live editor timeline. Native JIT follow-up work is still needed for the full legacy interaction set such as rich scrubbing behavior, drag/drop insertion fidelity, trim/move affordances, review dimming, prompt preview overlays, and caption-specific timeline polish.
- Current fidelity discrepancy: auxiliary chrome for import/export/captions/prompt review is mounted above the JIT canvas so the flows remain reachable, but those panels are not yet expressed as JIT render-state components.
- Current blocker: manual testing of prompt-driven layout changes is limited by the prompt server connection error documented in `docs/jit-editor-follow-ups.md`.
