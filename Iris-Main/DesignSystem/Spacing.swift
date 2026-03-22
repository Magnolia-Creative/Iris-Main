import SwiftUI

enum Spacing: CGFloat {
    case sp0 = 0
    case sp1 = 4
    case sp2 = 8
    case sp3 = 12
    case sp4 = 16
    case sp5 = 20
    case sp6 = 24
    case sp7 = 32
    case sp8 = 40
    case sp9 = 48
    case sp10 = 64
    
    var value: CGFloat {
        return self.rawValue
    }
}

extension View {
    func padding(_ spacing: Spacing) -> some View {
        self.padding(spacing.value)
    }
    
    func padding(_ edges: Edge.Set, _ spacing: Spacing) -> some View {
        self.padding(edges, spacing.value)
    }
}

extension CGFloat {
    static func spacing(_ spacing: Spacing) -> CGFloat {
        return spacing.value
    }
}
