@preconcurrency import WatchConnectivity
import Foundation

@MainActor
final class WatchDashboardState: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var isConnected = false
    @Published private(set) var boardName = "OWCE"
    @Published private(set) var speedMph: Double?
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var rideMode = "—"
    @Published private(set) var updatedAt: Date?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        apply(WCSession.default.receivedApplicationContext)
    }

    private func apply(_ context: [String: Any]) {
        if let connected = context["connected"] as? Bool { isConnected = connected }
        if let name = context["boardName"] as? String { boardName = name }
        if let speed = context["speedMph"] as? Double { speedMph = speed >= 0 ? speed : nil }
        if let battery = context["batteryPercent"] as? Int { batteryPercent = battery >= 0 ? battery : nil }
        if let mode = context["rideMode"] as? String { rideMode = mode }
        updatedAt = Date()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }

}
