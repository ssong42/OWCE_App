import Charts
import MapKit
import SwiftUI
import UIKit

struct RideHistoryScreen: View {
    @EnvironmentObject private var recorder: RideRecorder
    @AppStorage("owce.metricDisplay") private var metricDisplay = false
    @State private var rideToRename: RideRecord?
    @State private var renameText = ""
    @State private var rideToDelete: RideRecord?

    var body: some View {
        List {
            if recorder.isRecording {
                Section("CURRENT RIDE") {
                    Label("Recording · \(duration(recorder.elapsed))", systemImage: "record.circle.fill")
                        .foregroundStyle(.orange)
                    Text("\(distance(recorder.distanceMeters)) · max \(speed(recorder.maximumSpeedMph))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if recorder.rides.isEmpty {
                ContentUnavailableView("No past rides", systemImage: "figure.outdoor.cycle", description: Text("Record a ride from the Board tab to see it here."))
                    .listRowBackground(Color.clear)
            } else {
                Section("PAST RIDES") {
                    ForEach(recorder.rides) { ride in
                        NavigationLink {
                            RideDetailsScreen(ride: ride)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(ride.name ?? "Ride on \(ride.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.headline).lineLimit(1)
                                Text("\(duration(ride.duration)) · \(distance(ride.distanceMeters)) · max \(speed(ride.maximumSpeedMph))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                rideToRename = ride
                                renameText = ride.name ?? "Ride on \(ride.startedAt.formatted(date: .abbreviated, time: .shortened))"
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { rideToDelete = ride }
                        }
                    }
                }
            }
        }
        .navigationTitle("Past Rides")
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.055, green: 0.067, blue: 0.082))
        .alert("Rename ride", isPresented: Binding(get: { rideToRename != nil }, set: { if !$0 { rideToRename = nil } })) {
            TextField("Ride name", text: $renameText)
            Button("Save") { if let rideToRename { recorder.rename(rideToRename, to: renameText) }; rideToRename = nil }
            Button("Cancel", role: .cancel) { rideToRename = nil }
        }
        .confirmationDialog("Delete this ride?", isPresented: Binding(get: { rideToDelete != nil }, set: { if !$0 { rideToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete ride", role: .destructive) { if let rideToDelete { recorder.delete(rideToDelete) }; rideToDelete = nil }
            Button("Cancel", role: .cancel) { rideToDelete = nil }
        }
    }

    private func distance(_ meters: Double) -> String {
        metricDisplay ? String(format: "%.2f km", meters / 1000) : String(format: "%.2f mi", meters / 1609.344)
    }
    private func speed(_ mph: Double) -> String {
        metricDisplay ? String(format: "%.1f km/h", mph * 1.60934) : String(format: "%.1f mph", mph)
    }
    private func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
    }
}

struct RideDetailsScreen: View {
    let ride: RideRecord
    @AppStorage("owce.metricDisplay") private var metricDisplay = false

    private var samples: [RideTelemetrySample] { ride.samples ?? [] }
    private var route: [RideLocation] { ride.route ?? [] }
    private var rawEvents: [RideRawEvent] { ride.rawEvents ?? [] }
    private var routeCoordinates: [CLLocationCoordinate2D] { route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
    private var routeRegion: MKCoordinateRegion {
        let latitudes = route.map(\.latitude)
        let longitudes = route.map(\.longitude)
        let minLatitude = latitudes.min() ?? 0
        let maxLatitude = latitudes.max() ?? 0
        let minLongitude = longitudes.min() ?? 0
        let maxLongitude = longitudes.max() ?? 0
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2), span: MKCoordinateSpan(latitudeDelta: max(0.002, (maxLatitude - minLatitude) * 1.4), longitudeDelta: max(0.002, (maxLongitude - minLongitude) * 1.4)))
    }
    @State private var showingShare = false
    @State private var csvURL: URL?

    var body: some View {
        List {
            Section("SUMMARY") {
                LabeledContent("Started", value: ride.startedAt.formatted(date: .complete, time: .shortened))
                LabeledContent("Duration", value: duration(ride.duration))
                LabeledContent("Distance", value: metricDisplay ? String(format: "%.2f km", ride.distanceMeters / 1000) : String(format: "%.2f mi", ride.distanceMeters / 1609.344))
                LabeledContent("Maximum speed", value: metricDisplay ? String(format: "%.1f km/h", ride.maximumSpeedMph * 1.60934) : String(format: "%.1f mph", ride.maximumSpeedMph))
                LabeledContent("Telemetry samples", value: "\(samples.count)")
                LabeledContent("GPS points", value: "\(route.count)")
            }
            Section("RIDE DATA") {
                LabeledContent("Raw BLE events", value: "\(rawEvents.count)")
                if rawEvents.isEmpty {
                    Text("This ride has no raw BLE event log to export or submit.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    NavigationLink("Submit ride to OWCE") { RideSubmissionScreen(ride: ride) }
                    Button("Export raw log as CSV", systemImage: "square.and.arrow.up") {
                        csvURL = RideExport.writeCSV(ride)
                        showingShare = csvURL != nil
                    }
                    .disabled(rawEvents.isEmpty)
                }
            }
            if routeCoordinates.count > 1 {
                Section("ROUTE") {
                    Map(initialPosition: .region(routeRegion)) {
                        MapPolyline(coordinates: routeCoordinates).stroke(.cyan, lineWidth: 4)
                    }
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets())
                }
            }
            if samples.contains(where: { $0.speedMph != nil }) {
                Section("SPEED") {
                    Chart(samples) { sample in
                        if let speed = sample.speedMph {
                            LineMark(x: .value("Time", sample.time), y: .value("Speed", metricDisplay ? speed * 1.60934 : speed))
                                .foregroundStyle(.cyan)
                        }
                    }
                    .frame(height: 180)
                    .chartYAxisLabel(metricDisplay ? "km/h" : "mph")
                }
            }
            Section("TELEMETRY") {
                if samples.isEmpty {
                    Text("No raw telemetry was recorded for this ride.").foregroundStyle(.secondary)
                } else {
                    ForEach(samples.reversed()) { sample in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(sample.time.formatted(date: .omitted, time: .standard)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(sampleSummary(sample)).font(.caption).textSelection(.enabled)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle(ride.name ?? "Ride Details")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.055, green: 0.067, blue: 0.082))
        .sheet(isPresented: $showingShare) {
            if let csvURL { ActivityViewController(items: [csvURL]) }
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
    }
    private func sampleSummary(_ sample: RideTelemetrySample) -> String {
        let speed = sample.speedMph.map { String(format: "%.1f %@", metricDisplay ? $0 * 1.60934 : $0, metricDisplay ? "km/h" : "mph") } ?? "—"
        let battery = sample.batteryPercent.map { "\($0)%" } ?? "—"
        let voltage = sample.batteryVoltage.map { String(format: "%.1f V", $0) } ?? "—"
        let current = sample.currentAmps.map { String(format: "%.1f A", $0) } ?? "—"
        let temps = "M \(sample.motorTemperature.map(String.init) ?? "—")° · C \(sample.controllerTemperature.map(String.init) ?? "—")°"
        return "\(speed) · \(battery) · \(voltage) · \(current) · \(temps) · \(sample.rideMode ?? "—")"
    }
}

struct RideSubmissionScreen: View {
    let ride: RideRecord
    @State private var rideName = ""
    @State private var aftermarketBattery = false
    @State private var batteryType = ""
    @State private var removeIdentifiers = true
    @State private var allowPublicly = false
    @State private var additionalNotes = ""
    @State private var isSubmitting = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showingPreview = false

    private var events: [RideRawEvent] { ride.rawEvents ?? [] }

    var body: some View {
        Form {
            Section("RIDE") {
                TextField("Ride name", text: $rideName)
                Toggle("Aftermarket battery", isOn: $aftermarketBattery)
                if aftermarketBattery { TextField("Battery type", text: $batteryType) }
            }
            Section("PRIVACY") {
                Toggle("Remove board and battery serial numbers", isOn: $removeIdentifiers)
                Text("When enabled, serial-number event data is replaced with zeros before upload. Keep this on unless you specifically need identifiers included.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Allow this ride to be public", isOn: $allowPublicly)
                Text("A public ride may be replayed by people using OWCE. This choice is sent with the submission.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("NOTES") {
                TextField("Additional notes", text: $additionalNotes, axis: .vertical).lineLimit(3...8)
            }
            Section {
                Button("Preview data that will be submitted") { showingPreview = true }
                Button {
                    Task { await submitRide() }
                } label: {
                    if isSubmitting { ProgressView("Submitting ride…") }
                    else { Text("Submit ride") }
                }
                .disabled(isSubmitting || events.isEmpty)
            } footer: {
                Text("\(events.count) raw BLE events · \(removeIdentifiers ? "serial numbers will be removed" : "serial numbers will be included")")
            }
        }
        .navigationTitle("Submit Ride")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.055, green: 0.067, blue: 0.082))
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                List {
                    Section("UPLOAD SUMMARY") {
                        Text("Ride: \(rideName.isEmpty ? (ride.name ?? "Untitled ride") : rideName)")
                        Text("BLE events: \(events.count)")
                        Text("Identifiers: \(removeIdentifiers ? "redacted" : "included")")
                        Text("Public: \(allowPublicly ? "yes" : "no")")
                    }
                    Section("FIRST RAW EVENTS") {
                        ForEach(events.prefix(100)) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(RideExport.characteristicName(event.uuid)) · \(event.uuid)").font(.caption.weight(.semibold))
                                Text(event.data.map { String(format: "%02X", $0) }.joined(separator: " "))
                                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                }
                .navigationTitle("Submission Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingPreview = false } } }
            }
        }
        .alert("Ride submission", isPresented: $showingAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
        .onAppear { rideName = ride.name ?? "Ride on \(ride.startedAt.formatted(date: .abbreviated, time: .shortened))" }
    }

    @MainActor private func submitRide() async {
        guard !events.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let requestBody = RideSubmissionRequest(rideName: rideName, aftermarketBattery: aftermarketBattery, batteryType: batteryType, removeIdentifiers: removeIdentifiers, allowPublicly: allowPublicly, additionalNotes: additionalNotes)
            var request = URLRequest(url: URL(string: "https://api.owce.app/v1/ride/submit")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("OWCE-iOS-Native/1.0", forHTTPHeaderField: "User-Agent")
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw RideSubmissionError.server("OWCE could not accept this ride right now.")
            }
            let upload = try JSONDecoder().decode(RideSubmissionResponse.self, from: responseData)
            guard let uploadURL = URL(string: upload.uploadURL), uploadURL.scheme == "https" else {
                throw RideSubmissionError.server("The upload service returned an invalid URL.")
            }
            let binaryData = RideExport.protobufEvents(for: ride, removingIdentifiers: removeIdentifiers)
            var uploadRequest = URLRequest(url: uploadURL)
            uploadRequest.httpMethod = "PUT"
            uploadRequest.setValue("binary/octet-stream", forHTTPHeaderField: "Content-Type")
            uploadRequest.httpBody = binaryData
            let (_, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
            guard let uploadHTTP = uploadResponse as? HTTPURLResponse, (200..<300).contains(uploadHTTP.statusCode) else {
                throw RideSubmissionError.server("The ride was prepared, but the data upload failed. Please try again.")
            }
            alertMessage = "Thanks for submitting your ride."
            showingAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
}

private struct RideSubmissionRequest: Encodable {
    var rideName: String
    var aftermarketBattery: Bool
    var batteryType: String
    var removeIdentifiers: Bool
    var allowPublicly: Bool
    var additionalNotes: String
    enum CodingKeys: String, CodingKey {
        case rideName = "ride_name"
        case aftermarketBattery = "aftermarket_battery"
        case batteryType = "battery_type"
        case removeIdentifiers = "remove_identifiers"
        case allowPublicly = "allow_publicly"
        case additionalNotes = "additional_notes"
    }
}

private struct RideSubmissionResponse: Decodable {
    var id: String
    var uploadURL: String
    enum CodingKeys: String, CodingKey { case id; case uploadURL = "upload_url" }
}

private enum RideSubmissionError: LocalizedError {
    case server(String)
    var errorDescription: String? { if case .server(let message) = self { return message }; return nil }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct RideLogsScreen: View {
    @EnvironmentObject private var recorder: RideRecorder

    private var allSamples: [(ride: RideRecord, sample: RideTelemetrySample)] {
        recorder.rides.flatMap { ride in (ride.samples ?? []).map { (ride, $0) } }.sorted { $0.sample.time > $1.sample.time }
    }

    var body: some View {
        List {
            if allSamples.isEmpty {
                ContentUnavailableView("No ride logs", systemImage: "list.bullet.rectangle", description: Text("Recorded board telemetry will appear here after a ride."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(allSamples.prefix(500), id: \.sample.id) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.ride.name ?? item.ride.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption.weight(.semibold))
                        Text(item.sample.time.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary)
                        Text("Speed \(item.sample.speedMph.map { String(format: "%.1f mph", $0) } ?? "—") · Battery \(item.sample.batteryPercent.map { "\($0)%" } ?? "—") · Voltage \(item.sample.batteryVoltage.map { String(format: "%.1f V", $0) } ?? "—")")
                            .font(.caption).textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Ride Logs")
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.055, green: 0.067, blue: 0.082))
    }
}

struct BoardDetailsScreen: View {
    @EnvironmentObject private var bluetooth: BoardBluetoothManager

    private var characteristicRows: [(uuid: String, value: String)] {
        bluetooth.characteristicValues.map { ($0.key, $0.value) }.sorted { $0.uuid < $1.uuid }
    }

    var body: some View {
        List {
            Section("BOARD") {
                LabeledContent("Model", value: bluetooth.boardType)
                LabeledContent("Hardware revision", value: bluetooth.hardwareRevision.map(String.init) ?? "—")
                LabeledContent("Firmware revision", value: bluetooth.firmwareRevision.map(String.init) ?? "—")
                LabeledContent("Board serial", value: bluetooth.serialNumber.map(String.init) ?? "—")
                LabeledContent("Battery serial", value: bluetooth.batterySerialNumber.map(String.init) ?? "—")
                LabeledContent("Ride mode", value: bluetooth.rideMode ?? "—")
            }
            Section("BATTERY") {
                LabeledContent("Charge", value: bluetooth.batteryPercent.map { "\($0)%" } ?? "—")
                LabeledContent("Voltage", value: bluetooth.batteryVoltage.map { String(format: "%.2f V", $0) } ?? "—")
                LabeledContent("Cell voltage readings", value: "\(bluetooth.batteryCellVoltages.count)")
                ForEach(bluetooth.batteryCellVoltages.keys.sorted(), id: \.self) { cell in
                    LabeledContent("Cell \(cell)", value: String(format: "%.3f V", bluetooth.batteryCellVoltages[cell] ?? 0))
                }
            }
            Section("LIGHTS & SAFETY") {
                LabeledContent("Front light mode", value: bluetooth.frontLightMode.map(String.init) ?? "—")
                LabeledContent("Rear light mode", value: bluetooth.rearLightMode.map(String.init) ?? "—")
                LabeledContent("Safety headroom", value: bluetooth.safetyHeadroom.map(String.init) ?? "—")
                LabeledContent("Status code", value: bluetooth.characteristicValues["E659F30F-EA98-11E3-AC10-0800200C9A66"] ?? "—")
            }
            Section("RAW CHARACTERISTICS · HEX") {
                if characteristicRows.isEmpty {
                    Text("No characteristic values received.").foregroundStyle(.secondary)
                } else {
                    ForEach(characteristicRows, id: \.uuid) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(RideExport.characteristicName(row.uuid)).font(.caption.weight(.semibold))
                            Text(row.uuid).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            Text(row.value).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Board Details")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.055, green: 0.067, blue: 0.082))
    }
}

struct AppSettingsScreen: View {
    @AppStorage("owce.metricDisplay") private var metricDisplay = false

    var body: some View {
        Form {
            Section("RIDE DISPLAY") {
                Toggle("Metric units (km/h, km)", isOn: $metricDisplay)
            }
            Section("RECORDING") {
                Text("Rides start only when you tap Start ride recording on the Board tab. Location permission is required for distance and route tracking.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("PRIVACY") {
                Label("Ride data is stored locally on this iPhone.", systemImage: "lock.shield")
                Text("Ride submission and cloud features are not enabled in this native build.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.055, green: 0.067, blue: 0.082))
    }
}

struct AboutScreen: View {
    var body: some View {
        List {
            Section {
                Text("OWCE").font(.largeTitle.bold())
                Text("Onewheel Community Edition").foregroundStyle(.secondary)
                Text("An independent community project; not endorsed by or affiliated with Future Motion.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("PROJECT") {
                LabeledContent("Native client", value: "SwiftUI")
                LabeledContent("Minimum iOS", value: "17.0")
                Link("OWCE source repository", destination: URL(string: "https://github.com/OWCEApp/OWCE")!)
            }
            Section("BOARD SUPPORT") {
                Text("BLE and ride-mode support are being validated against physical boards. Firmware may limit the data a board exposes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About OWCE")
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.055, green: 0.067, blue: 0.082))
    }
}
