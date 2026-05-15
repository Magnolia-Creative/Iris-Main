# VideoLab preview verification

After changing the VideoLab bridge or compositor patches, confirm playback without the full editor:

1. Open **Iris-Main.xcworkspace** (required for CocoaPods / `VideoLab`).
2. Run the app, navigate to **DevTools → Rendering** (`RenderingDemoView`).
3. Add a short **.mov** via the Photos picker and press play; scrub the slider.
4. In **Console**, filter subsystem `Iris-Main`, category `VideoLabPreview` for Iris-side logs, or search for `[VideoLab]` for pod DEBUG prints (LayerCompositor / VideoCompositor).

CLI compile (generic iOS, no signing):

```bash
cd Iris-Main
pod install
xcodebuild -workspace Iris-Main.xcworkspace -scheme Iris-Main \
  -destination 'generic/platform=iOS' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

Then repeat the same asset in the **editor** preview (`PreviewSection` + `TimelineRenderBridge`).
