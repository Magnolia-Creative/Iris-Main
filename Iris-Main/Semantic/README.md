# Semantic Feature Notes

This feature uses `swift-mobileclip` with the `s2` encoder URI from `AppConfiguration.semanticMobileCLIPEncoderURI`.

## Model setup

- Download MobileCLIP CoreML packages (for example from the Apple Hugging Face release).
- Compile them to `.modelc`.
- Ensure the `s2` text/image model artifacts are accessible to the app runtime.
- If loading from a custom location, update `semanticMobileCLIPEncoderURI` from `s2://` to an `s2:///absolute/path` form expected by `swift-mobileclip`.

## Runtime behavior

- Coarse index samples one frame every 2 seconds.
- Fine search samples 5 fps around top coarse candidates.
- Query text is embedded with MobileCLIP text encoder and compared with cosine similarity.
