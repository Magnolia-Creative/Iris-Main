import ClerkKit
import ClerkKitUI
import SwiftUI

@main
struct Iris_MainApp: App {
    init() {
        _ = DatabaseManager.shared
        Clerk.configure(publishableKey: AppConfiguration.clerkPublishableKey)
    }

    var body: some Scene {
        WindowGroup {
            AuthenticatedRootView()
                .environment(Clerk.shared)
                .environment(\.clerkTheme, .iris)
                .preferredColorScheme(.dark)
        }
    }
}
