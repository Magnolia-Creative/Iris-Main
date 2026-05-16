import ClerkKit
import ClerkKitUI
import SwiftUI

/// Routes between Clerk sign-in and the main app based on session state.
struct AuthenticatedRootView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.clerkTheme) private var clerkTheme

    var body: some View {
        Group {
            if clerk.user != nil {
                HomeView()
                    .transition(.opacity)
            } else {
                signedOutExperience
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: clerk.user != nil)
    }

    private var signedOutExperience: some View {
        GeometryReader { proxy in
            AuthView(isDismissable: false)
                .clerkAppIcon(Image("Iris_Outline").renderingMode(.template))
                .contentMargins(.top, topScrollPadding(proxy: proxy), for: .scrollContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(clerkTheme.colors.background.ignoresSafeArea())
        .prefetchClerkImages()
    }

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

    private func topScrollPadding(proxy: GeometryProxy) -> CGFloat {
        let estimate = estimatedAuthFormHeight(for: dynamicTypeSize)
        let raw = (proxy.size.height - estimate) / 2
        return max(0, raw * 0.65)
    }
}
