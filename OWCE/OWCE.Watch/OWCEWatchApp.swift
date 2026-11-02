import SwiftUI

@main
struct OWCEWatchApp: App {
    @StateObject private var watchState = WatchDashboardState()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(watchState)
        }
    }
}
