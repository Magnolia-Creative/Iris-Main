import ClerkKit
import ClerkKitUI
import SwiftUI
import UIKit

/// Routes between Clerk sign-in and the main app based on session state.
struct AuthenticatedRootView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.clerkTheme) private var clerkTheme

    var body: some View {
        Group {
            if clerk.user != nil {
                HomeView()
            } else {
                signedOutExperience
            }
        }
    }

    private var signedOutExperience: some View {
        GeometryReader { proxy in
            let top = verticalCenteringPadding(proxy: proxy)
            let bg = clerkTheme.colors.background
            VStack(spacing: 0) {
                Rectangle()
                    .fill(bg)
                    .frame(height: top)

                Image("Iris_Outline")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(Color.ds.text)
                    .frame(maxHeight: 56)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .background(bg)

                AuthView(isDismissable: false)
                    .clerkAppIcon(Self.collapsedClerkLogoPlaceholder)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(clerkTheme.colors.background.ignoresSafeArea())
        .prefetchClerkImages()
    }

    /// Wide transparent image so Clerk’s `AppLogoView` (`scaledToFit` + `maxHeight: 44`) uses almost no height,
    /// letting the real Iris mark live in the row above `AuthView`.
    private static let collapsedClerkLogoPlaceholder: Image = {
        let size = CGSize(width: 800, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        let uiImage = renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return Image(uiImage: uiImage)
    }()

    /// Approximate height of Clerk’s first auth screen (header, field, continue, divider, social, footer).
    private func estimatedAuthFormHeight(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall, .small, .medium:
            return 440
        case .large:
            return 460
        case .xLarge, .xxLarge:
            return 500
        case .xxxLarge:
            return 540
        case .accessibility1, .accessibility2:
            return 580
        case .accessibility3, .accessibility4, .accessibility5:
            return 640
        @unknown default:
            return 480
        }
    }

    private func verticalCenteringPadding(proxy: GeometryProxy) -> CGFloat {
        // External logo row (~56 + 12) and collapsed in-scroll logo vs the old full-height slot (~+24 net).
        let signedOutChromeAdjustment: CGFloat = 24
        let estimate = estimatedAuthFormHeight(for: dynamicTypeSize) + signedOutChromeAdjustment
        let raw = (proxy.size.height - estimate) / 2
        return max(0, raw)
    }
}
