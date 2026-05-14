import ClerkKit
import ClerkKitUI
import SwiftUI

/// Routes between Clerk sign-in and the main app based on session state.
struct AuthenticatedRootView: View {
    @Environment(Clerk.self) private var clerk

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
        NavigationStack {
            AuthView()
                .navigationTitle("Welcome")
                .navigationBarTitleDisplayMode(.inline)
        }
        .prefetchClerkImages()
    }
}
