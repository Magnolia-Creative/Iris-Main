import Foundation

struct VectorSearchHit<Payload> {
    let payload: Payload
    let score: Double
}

struct VectorEntry<Payload> {
    let vector: [Float]
    let payload: Payload
}

struct LocalVectorIndex<Payload> {
    private(set) var entries: [VectorEntry<Payload>] = []

    mutating func reset() {
        entries.removeAll(keepingCapacity: false)
    }

    mutating func add(vector: [Float], payload: Payload) {
        entries.append(VectorEntry(vector: vector, payload: payload))
    }

    func topK(query: [Float], limit: Int) -> [VectorSearchHit<Payload>] {
        guard !entries.isEmpty, limit > 0 else { return [] }

        return entries
            .compactMap { entry in
                let score = cosineSimilarity(query, entry.vector)
                guard score.isFinite else { return nil }
                return VectorSearchHit(payload: entry.payload, score: score)
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}

func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
    guard lhs.count == rhs.count, !lhs.isEmpty else {
        return -.infinity
    }

    var dot: Double = 0
    var lhsNorm: Double = 0
    var rhsNorm: Double = 0

    for (l, r) in zip(lhs, rhs) {
        let ld = Double(l)
        let rd = Double(r)
        dot += ld * rd
        lhsNorm += ld * ld
        rhsNorm += rd * rd
    }

    guard lhsNorm > 0, rhsNorm > 0 else {
        return -.infinity
    }

    return dot / (sqrt(lhsNorm) * sqrt(rhsNorm))
}
