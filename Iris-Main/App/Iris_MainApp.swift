import SwiftUI

@main
struct Iris_MainApp: App {
    init() {
        _ = DatabaseManager.shared
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
