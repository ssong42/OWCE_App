@preconcurrency import WatchConnectivity
import Foundation

@MainActor
final class WatchConnectivityBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var isSupported = WCSession.isSupported()
    @Published private(set) var isActivated = false
    private var pendingValues: [String: Any] = [:]
    private var lastPublishAt = Date.distantPast

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(_ values: [String: Any], force: Bool = false) {
        pendingValues = values
        guard WCSession.isSupported(), isActivated else { return }
        guard force || Date().timeIntervalSince(lastPublishAt) >= 1 else { return }
        lastPublishAt = Date()
        do {
            try WCSession.default.updateApplicationContext(pendingValues)
        } catch {
            NSLog("OWCE Watch context update failed: %@", error.localizedDescription)
        }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(pendingValues, replyHandler: nil) { error in
                NSLog("OWCE Watch message failed: %@", error.localizedDescription)
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isActivated = activationState == .activated
            if self.isActivated { self.publish(self.pendingValues, force: true) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
