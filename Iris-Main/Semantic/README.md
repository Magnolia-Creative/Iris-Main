# Semantic Feature Notes

This feature uses `swift-mobileclip` with the `s2` encoder URI from `AppConfiguration.semanticMobileCLIPEncoderURI`.

## Model setup

- Download MobileCLIP CoreML packages (for example from the Apple Hugging Face release).
- Compile them to `.modelc`.
- Ensure the `s2` text/image model artifacts are accessible to the app runtime.
- If loading from a custom location, update `semanticMobileCLIPEncoderURI` from `s2://` to an `s2:///absolute/path` form expected by `swift-mobileclip`.

## Runtime behavior

- Single-pass chunk index uses 4-second chunks with 0.5-second overlap.
- One center frame is embedded per chunk and reused at query time (no query-time frame embedding pass).
- Query text is embedded with MobileCLIP text encoder and compared with cosine similarity.
