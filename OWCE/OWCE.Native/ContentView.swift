import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bluetooth: BoardBluetoothManager
    @EnvironmentObject private var rideRecorder: RideRecorder
    @EnvironmentObject private var watchBridge: WatchConnectivityBridge
    @AppStorage("owce.metricDisplay") private var metricDisplay = false
    @AppStorage("owce.autoRideRecording") private var autoRideRecording = false
    @State private var selectedRideMode: (name: String, value: Int)?
    @State private var showingRideModeConfirmation = false

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
            .confirmationDialog("Change ride mode?", isPresented: $showingRideModeConfirmation, titleVisibility: .visible) {
                if let selectedRideMode {
                    Button("Change to \(selectedRideMode.name)") { bluetooth.changeRideMode(to: selectedRideMode.value) }
                }
                Button("Cancel", role: .cancel) { selectedRideMode = nil }
            } message: {
                Text("Only change ride mode while stopped. Verify the board display before riding.")
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
            if identifier != nil, autoRideRecording, !rideRecorder.isRecording {
                rideRecorder.start(currentSpeedMph: bluetooth.speed)
            } else if identifier == nil, autoRideRecording, rideRecorder.isRecording {
                rideRecorder.stop(currentSpeedMph: bluetooth.speed)
            }
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
                                        selectedRideMode = mode
                                        showingRideModeConfirmation = true
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
