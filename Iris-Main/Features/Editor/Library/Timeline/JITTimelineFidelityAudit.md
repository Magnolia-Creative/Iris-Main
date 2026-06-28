# JIT Timeline Fidelity Audit

Captured on iPhone 17 (`D0A53C1B-AA2F-435D-AA76-E748EDF287B4`) after commit `d00b782`, using the editor header `JIT / Legacy` comparator switch.

## Setup

- Created a fresh project with `Import & Edit`.
- Added a 0:57 video through the timeline add menu: `Add` -> `Video Photos` -> system Photos picker -> selected video -> `Add`.
- Verified the imported clip renders in the preview and timeline in both modes.

## Confirmed Part A Behavior

- JIT is the default editor mode.
- The debug-only segmented switch appears in the editor header and toggles between `JIT` and `Legacy`.
- Legacy mode composes the old `PlaybackSectionView` and `TimelineSectionView`; it renders the imported clip and supports playback/scrubbing.
- Switching modes preserves the imported timeline state.

## Observed Gaps To Carry Into Primitive Work

- Legacy layout is visually taller than JIT: the preview expands substantially and the JIT bottom chrome disappears in comparator mode.
- Legacy switching resets the visible scroll/readout back near the start, while JIT had been scrubbed to the mid-timeline. This makes A/B comparisons possible but indicates scroll position handoff is not symmetric.
- JIT playback advances preview/readout and auto-follows, but jumps aggressively during playback; the first play advanced from the start to roughly `00:15` quickly.
- JIT slow scrubbing over the ruler updates current time and preview. Scrubbing over the clip body is less reliable: a slow drag moved only slightly, and a fast drag over the clip body did not advance.
- JIT ruler scrubbing is effective: a leftward ruler drag moved from roughly `00:29` to `00:34` and updated the preview.
- Legacy ruler scrubbing behaves similarly on the same imported clip, moving from roughly `00:31` to `00:36` and updating the preview.
- The import panel video tile preview plays correctly, but dragging the imported media tile into the timeline did not insert during this run; direct `Video Photos` from the timeline add menu did insert successfully.
- The timeline `Add` button remains visible over clips in both modes, including while the imported clip is present.

## Argent Artifacts

- JIT empty-timeline baseline screenshot: `/var/folders/fb/4qbfwq6s5wvdvrmnmcddw3_c0000gn/T/simserver-TjdtA3/media/317796000-1782672467318.png`
- Legacy empty-timeline diff output: `/tmp/iris-main-ui-refinement-argent`
- JIT imported-video frame around `00:34`: `/var/folders/fb/4qbfwq6s5wvdvrmnmcddw3_c0000gn/T/simserver-TjdtA3/media/12281000-1782672713020.png`
- Legacy imported-video diff output: `/tmp/iris-main-ui-refinement-argent`
