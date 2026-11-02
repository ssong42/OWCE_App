import SwiftUI

@main
struct OWCEApp: App {
    @StateObject private var bluetooth = BoardBluetoothManager()
    @StateObject private var rideRecorder = RideRecorder()
    @StateObject private var watchBridge = WatchConnectivityBridge()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetooth)
                .environmentObject(rideRecorder)
                .environmentObject(watchBridge)
                .preferredColorScheme(.dark)
        }
    }
}
