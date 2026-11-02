import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bluetooth: BoardBluetoothManager
    @EnvironmentObject private var rideRecorder: RideRecorder
    @EnvironmentObject private var watchBridge: WatchConnectivityBridge
    @AppStorage("owce.metricDisplay") private var metricDisplay = false
    @State private var selectedRideMode: RideModeSelection?

    var body: some View {
        TabView {
          NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let board = bluetooth.connectedBoard {
                        connectedCard(for: board)
                    } else {
                        scanCard
                        boardList
                    }
                    rideHistory
                    Text("OWCE is an independent community project and is not affiliated with Future Motion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(Color(red: 0.055, green: 0.067, blue: 0.082).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: bluetooth.speed) { _, speed in rideRecorder.updateMaximumSpeed(speed) }
            .sheet(item: $selectedRideMode) { mode in
                RideModeInfoSheet(modeName: mode.name, boardType: bluetooth.boardType) {
                    bluetooth.changeRideMode(to: mode.value)
                }
            }
          }
          .tabItem { Label("Board", systemImage: "speedometer") }
          NavigationStack { RideHistoryScreen() }
            .tabItem { Label("Rides", systemImage: "figure.outdoor.cycle") }
          NavigationStack { RideLogsScreen() }
            .tabItem { Label("Logs", systemImage: "list.bullet.rectangle") }
          NavigationStack { AppSettingsScreen() }
            .tabItem { Label("Settings", systemImage: "gearshape") }
          NavigationStack { AboutScreen() }
            .tabItem { Label("About", systemImage: "info.circle") }
        }
        .tint(.cyan)
        .onChange(of: bluetooth.telemetryValuesReceived) { _, _ in
            rideRecorder.captureTelemetry(speedMph: bluetooth.speed, batteryPercent: bluetooth.batteryPercent, batteryVoltage: bluetooth.batteryVoltage, currentAmps: bluetooth.currentAmps, motorTemperature: bluetooth.motorTemperature, controllerTemperature: bluetooth.controllerTemperature, rideMode: bluetooth.rideMode, rawUUID: bluetooth.latestCharacteristicUUID, rawData: bluetooth.latestCharacteristicData)
            publishToWatch()
        }
        .onChange(of: bluetooth.connectedBoard?.identifier) { _, identifier in
            publishToWatch(force: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OWCE").font(.system(size: 34, weight: .black, design: .rounded)).tracking(2)
            Text("ONEWHEEL COMMUNITY EDITION").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("BOARD CONNECTION", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.bold)).tracking(1).foregroundStyle(.cyan)
            Text(bluetooth.status).font(.headline)
            Button {
                bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.scan()
            } label: {
                Label(bluetooth.isScanning ? "Stop scanning" : "Scan for boards", systemImage: bluetooth.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private var boardList: some View {
        if !bluetooth.boards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("NEARBY BOARDS").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                ForEach(bluetooth.boards, id: \.identifier) { board in
                    Button { bluetooth.connect(to: board) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "figure.skateboarding").font(.title2).foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(board.name ?? "Onewheel").font(.headline).foregroundStyle(.primary)
                                Text("Tap to connect").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func connectedCard(for board: CBPeripheral) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("CONNECTED", systemImage: "checkmark.circle.fill").font(.caption.weight(.bold)).tracking(1).foregroundStyle(.green)
                    Spacer()
                    Button("Disconnect", role: .destructive) { bluetooth.disconnect() }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(board.name ?? "Onewheel").font(.title2.bold())
                    Text(bluetooth.boardType).font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        metric(title: "SPEED · \(metricDisplay ? "KM/H" : "MPH")", value: bluetooth.speed.map { String(format: "%.1f", metricDisplay ? $0 * 1.60934 : $0) } ?? "—", icon: "speedometer")
                        metric(title: "BATTERY", value: bluetooth.batteryPercent.map { "\($0)%" } ?? "—", icon: "battery.100")
                    }
                    HStack(spacing: 12) {
                        metric(title: "TRIP · \(metricDisplay ? "KM" : "MI")", value: bluetooth.tripDistance.map { String(format: "%.2f", metricDisplay ? $0 : $0 * 0.621371) } ?? "—", icon: "point.topleft.down.to.point.bottomright.curvepath")
                        metric(title: "RIDE MODE", value: bluetooth.rideMode ?? "—", icon: "figure.outdoor.cycle")
                    }
                }
                if !bluetooth.rideModes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RIDE MODES · CHANGE ONLY WHILE STOPPED")
                            .font(.caption2.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(bluetooth.rideModes, id: \.value) { mode in
                                    Button {
                                        selectedRideMode = RideModeSelection(name: mode.name, value: mode.value)
                                    } label: {
                                        Text(mode.name)
                                            .font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 14).padding(.vertical, 10)
                                            .background(bluetooth.rideModeNumber == mode.value ? Color.cyan : Color.white.opacity(0.08), in: Capsule())
                                            .foregroundStyle(bluetooth.rideModeNumber == mode.value ? .black : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Button {
                    if rideRecorder.isRecording {
                        rideRecorder.stop(currentSpeedMph: bluetooth.speed)
                    } else {
                        rideRecorder.start(currentSpeedMph: bluetooth.speed)
                    }
                } label: {
                    Label(rideRecorder.isRecording ? "Stop & save ride" : "Start ride recording", systemImage: rideRecorder.isRecording ? "stop.fill" : "record.circle")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(rideRecorder.isRecording ? .orange : .cyan)
                .foregroundStyle(.black)
                if rideRecorder.isRecording {
                    Text("Recording · \(formattedDuration(rideRecorder.elapsed)) · \(String(format: "%.2f", rideRecorder.distanceMeters / (metricDisplay ? 1000 : 1609.344))) \(metricDisplay ? "km" : "mi")")
                        .font(.footnote.monospacedDigit()).foregroundStyle(.orange)
                } else if !rideRecorder.locationAvailable && rideRecorder.locationStatus != "Location is used to record ride distance." {
                    Text(rideRecorder.locationStatus).font(.footnote).foregroundStyle(.secondary)
                }
                Text(bluetooth.status).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 14) {
                Text("BOARD TELEMETRY").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                Text(bluetooth.telemetryStatus).font(.footnote).foregroundStyle(bluetooth.telemetryValuesReceived > 0 ? .green : .secondary)
                Text(bluetooth.keepAliveStatus).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    metric(title: "VOLTAGE", value: bluetooth.batteryVoltage.map { String(format: "%.1f V", $0) } ?? "—", icon: "bolt.fill")
                    metric(title: "CURRENT", value: bluetooth.currentAmps.map { String(format: "%.1f A", $0) } ?? "—", icon: "arrow.left.arrow.right")
                }
                HStack(spacing: 12) {
                    metric(title: "MOTOR TEMP", value: bluetooth.motorTemperature.map { "\($0)°" } ?? "—", icon: "thermometer.medium")
                    metric(title: "CONTROLLER", value: bluetooth.controllerTemperature.map { "\($0)°" } ?? "—", icon: "cpu")
                }
                HStack(spacing: 12) {
                    metric(title: "BATTERY TEMP", value: bluetooth.batteryTemperature.map { "\($0)°" } ?? "—", icon: "thermometer")
                    metric(title: "SAFETY", value: bluetooth.safetyHeadroom.map { "\($0)" } ?? "—", icon: "shield")
                }
                HStack(spacing: 12) {
                    metric(title: "HARDWARE REV", value: bluetooth.hardwareRevision.map(String.init) ?? "—", icon: "cpu")
                    metric(title: "FIRMWARE REV", value: bluetooth.firmwareRevision.map(String.init) ?? "—", icon: "gearshape.2")
                }
                HStack(spacing: 12) {
                    metric(title: "LIFETIME · \(metricDisplay ? "KM" : "MI")", value: bluetooth.lifetimeDistance.map { String(format: "%.1f", metricDisplay ? $0 : $0 * 0.621371) } ?? "—", icon: "road.lanes")
                    Spacer(minLength: 0)
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))

            NavigationLink {
                BoardDetailsScreen()
            } label: {
                Label("Board details and raw characteristics", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var rideHistory: some View {
        if !rideRecorder.rides.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("RECENT RIDES").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                ForEach(rideRecorder.rides.prefix(8)) { ride in
                    HStack(spacing: 12) {
                        Image(systemName: "figure.outdoor.cycle").foregroundStyle(.cyan)
                            .frame(width: 38, height: 38).background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ride.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                            Text("\(formattedDuration(ride.duration)) · \(String(format: "%.2f", ride.distanceMeters / 1609.344)) mi")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("MAX \(String(format: "%.1f", ride.maximumSpeedMph)) mph").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    if ride.id != rideRecorder.rides.prefix(8).last?.id { Divider().overlay(.white.opacity(0.08)) }
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    private func publishToWatch(force: Bool = false) {
        watchBridge.publish([
            "connected": bluetooth.connectedBoard != nil,
            "boardName": bluetooth.connectedBoard?.name ?? bluetooth.boardType,
            "speedMph": bluetooth.speed ?? -1,
            "batteryPercent": bluetooth.batteryPercent ?? -1,
            "rideMode": bluetooth.rideMode ?? "—"
        ], force: force)
    }

    private func metric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.caption2.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct RideModeSelection: Identifiable {
    let name: String
    let value: Int
    var id: Int { value }
}

private struct RideModeInfoSheet: View {
    let modeName: String
    let boardType: String
    let onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("owce.metricDisplay") private var metricDisplay = false

    private var summary: String {
        let summaries: [String: String] = [
            "Redwood": "A mellow, forgiving Pint profile for relaxed cruising.",
            "Pacific": "A balanced all-around Pint profile for everyday riding.",
            "Elevated": "A nose-up stance that can help on climbs and uneven terrain.",
            "Skyline": "The most responsive, performance-oriented Pint profile.",
            "Sequoia": "A mellow, lower-speed profile for relaxed riding.",
            "Cruz": "A relaxed profile intended for casual cruising.",
            "Mission": "A balanced, versatile profile for everyday riding.",
            "Delirium": "A more assertive, responsive profile for experienced riders.",
            "Bay": "A mellow GT profile for relaxed cruising.",
            "Roam": "A smooth, easygoing GT profile for casual rides.",
            "Flow": "A balanced GT profile focused on fluid everyday riding.",
            "Highline": "A sportier, more responsive GT profile.",
            "Apex": "An assertive, performance-oriented GT profile.",
            "Custom": "A customizable profile; its exact feel depends on your board's configuration.",
            "Classic": "A standard, balanced profile for the original Onewheel.",
            "Extreme": "A more assertive profile for experienced riders."
        ]
        return summaries[modeName] ?? "Ride profile characteristics depend on the board model and firmware."
    }

    private var characteristics: [String] {
        switch modeName {
        case "Redwood": ["Gentler response", "Lower-speed character", "Good for relaxed rides"]
        case "Pacific": ["Balanced response", "Versatile for general cruising", "More lively than Redwood"]
        case "Elevated": ["More nose-up board angle", "Useful on inclines", "May feel different on level ground"]
        case "Skyline", "Delirium", "Apex", "Extreme": ["Sharper, more assertive feel", "Intended for confident riders", "Keep a generous safety margin"]
        case "Sequoia": ["Mellow response", "Lower-speed character", "Calmer cruising option"]
        case "Cruz", "Bay", "Roam": ["Easygoing response", "Relaxed cruising character", "A calmer profile"]
        case "Mission", "Flow", "Classic": ["Balanced, general-purpose feel", "Versatile for everyday riding", "A good all-around profile"]
        case "Highline": ["Sportier response", "More assertive ride feel", "Leave room for terrain and battery changes"]
        case "Custom": ["Characteristics vary with custom settings", "Check the board configuration", "Start cautiously after changes"]
        default: ["Characteristics vary by board and firmware", "Start cautiously with an unfamiliar profile"]
        }
    }

    private var advertisedMaxSpeedMPH: Int? {
        switch (boardType, modeName) {
        case ("Pint", "Redwood"), ("Pint X", "Redwood"): 12
        case ("Pint", "Pacific"), ("Pint", "Elevated"), ("Pint", "Skyline"): 16
        case ("Pint X", "Pacific"), ("Pint X", "Elevated"), ("Pint X", "Skyline"): 18
        case ("XR", "Sequoia"), ("Plus", "Sequoia"): 12
        case ("XR", "Cruz"), ("Plus", "Cruz"): 15
        case ("XR", "Mission"), ("XR", "Elevated"), ("XR", "Delirium"), ("XR", "Custom"),
             ("Plus", "Mission"), ("Plus", "Elevated"), ("Plus", "Delirium"), ("Plus", "Custom"): 19
        case ("V1", "Classic"): 12
        case ("V1", "Extreme"), ("V1", "Elevated"): 15
        default: nil
        }
    }

    private var feelRange: (lower: CGFloat, upper: CGFloat) {
        let ranges: [String: (CGFloat, CGFloat)] = [
            "Redwood": (0.04, 0.28), "Sequoia": (0.06, 0.30), "Cruz": (0.18, 0.43),
            "Bay": (0.17, 0.43), "Roam": (0.22, 0.49), "Pacific": (0.31, 0.59),
            "Mission": (0.37, 0.66), "Flow": (0.37, 0.65), "Classic": (0.34, 0.65),
            "Elevated": (0.40, 0.73), "Highline": (0.59, 0.86), "Skyline": (0.74, 0.98),
            "Delirium": (0.73, 0.97), "Apex": (0.77, 0.99), "Extreme": (0.70, 0.95),
            "Custom": (0.30, 0.72)
        ]
        let range = ranges[modeName] ?? (0.30, 0.70)
        return (range.0, range.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule().fill(.white.opacity(0.25)).frame(width: 38, height: 5).frame(maxWidth: .infinity).padding(.top, 10)
            HStack(spacing: 12) {
                Image(systemName: "speedometer").font(.title2.weight(.semibold)).foregroundStyle(.cyan)
                    .frame(width: 48, height: 48).background(.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(modeName).font(.title2.bold())
                    Text(boardType).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            Text(summary).font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("RIDE FEEL").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                    Spacer()
                    Text("Qualitative guide").font(.caption2).foregroundStyle(.tertiary)
                }
                GeometryReader { geometry in
                    let inset: CGFloat = 9
                    let usableWidth = max(0, geometry.size.width - inset * 2)
                    let startX = inset + usableWidth * feelRange.lower
                    let bandWidth = usableWidth * (feelRange.upper - feelRange.lower)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14)).frame(height: 6).padding(.horizontal, inset)
                        Capsule()
                            .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: bandWidth, height: 8)
                            .offset(x: startX)
                        HStack(spacing: 0) {
                            Rectangle().fill(.white.opacity(0.9)).frame(width: 2, height: 15)
                            Spacer(minLength: 0)
                            Rectangle().fill(.white.opacity(0.9)).frame(width: 2, height: 15)
                        }
                        .frame(width: bandWidth)
                        .offset(x: startX)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 20)
                HStack {
                    Text("Mellow / forgiving")
                    Spacer()
                    Text("More aggressive")
                }
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                Text("Relative character only—not a safety rating or recommended speed.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(13)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "speedometer").font(.title3).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MODE MAX SPEED").font(.caption2.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
                    Text("Published mode maximum; not a safe riding target.").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                if let advertisedMaxSpeedMPH {
                    Text(String(format: metricDisplay ? "%.0f km/h" : "%d mph", metricDisplay ? Double(advertisedMaxSpeedMPH) * 1.60934 : Double(advertisedMaxSpeedMPH)))
                        .font(.title3.bold().monospacedDigit())
                } else {
                    Text("—").font(.title3.bold()).foregroundStyle(.secondary)
                }
            }
            .padding(13)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 11) {
                ForEach(characteristics, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill").font(.subheadline)
                }
            }
            Label("Only switch while stopped. Ride modes do not guarantee a safe speed.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button("Select \(modeName)") { onSelect(); dismiss() }
                    .buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 22).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(red: 0.055, green: 0.067, blue: 0.082))
    }
}
