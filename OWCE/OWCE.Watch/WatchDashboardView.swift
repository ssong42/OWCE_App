import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject private var state: WatchDashboardState

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle().fill(state.isConnected ? .green : .gray).frame(width: 7, height: 7)
                    Text(state.boardName.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1)
                }
                Text(state.speedMph.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text("MPH").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "battery.100")
                    Text(state.batteryPercent.map { "\($0)%" } ?? "—")
                }
                .font(.headline).foregroundStyle(.green)
                Text(state.rideMode).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !state.isConnected {
                    Text("Open OWCE on iPhone to connect").font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .containerBackground(Color(red: 0.055, green: 0.067, blue: 0.082).gradient, for: .navigation)
    }
}
