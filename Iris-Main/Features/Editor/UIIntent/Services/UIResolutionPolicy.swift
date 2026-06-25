import Foundation

struct UIResolutionPolicy: Equatable {
    var decisiveDirectScore: Double = 0.88
    var localResolutionThreshold: Double = 0.72
    var embeddingAcceptThreshold: Double = 0.62
    var ambiguityBand: Double = 0.08
    var noOpPenalty: Double = 0.18
    var explicitTargetBoost: Double = 0.08
    var explicitStateBoost: Double = 0.08
    var contextBoost: Double = 0.08

    static let `default` = UIResolutionPolicy()
}
