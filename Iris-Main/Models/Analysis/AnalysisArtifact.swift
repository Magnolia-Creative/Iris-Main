import Foundation

struct AnalysisArtifact: Codable, Identifiable {
    let artifactId: String
    let createdAt: Date
    let type: ArtifactType
    let sourceMediaId: String
    let timebase: String
    let algorithmVersion: String
    var payload: [String: AnyCodable]

    var id: String { artifactId }

    init(
        artifactId: String = UUID().uuidString,
        createdAt: Date = Date(),
        type: ArtifactType,
        sourceMediaId: String,
        timebase: String = "microseconds",
        algorithmVersion: String,
        payload: [String: AnyCodable]
    ) {
        self.artifactId = artifactId
        self.createdAt = createdAt
        self.type = type
        self.sourceMediaId = sourceMediaId
        self.timebase = timebase
        self.algorithmVersion = algorithmVersion
        self.payload = payload
    }
}

enum ArtifactType: String, Codable {
    case beatMap = "beat_map"
    case silenceRegions = "silence_regions"
    case transcript
}
