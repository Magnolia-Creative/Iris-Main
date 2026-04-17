struct ImportRequest: Equatable {
    let kind: TrackKind
    let source: ImportSource
}

enum ImportSource: Equatable {
    case photos
    case files
    case textBox
    case caption
}
