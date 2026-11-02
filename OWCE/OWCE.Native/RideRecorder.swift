@preconcurrency import CoreLocation
import Foundation

struct RideRecord: Codable, Identifiable {
    var id = UUID()
    var name: String?
    var startedAt: Date
    var duration: TimeInterval
    var distanceMeters: Double
    var maximumSpeedMph: Double
    var samples: [RideTelemetrySample]? = []
    var route: [RideLocation]? = []
    var rawEvents: [RideRawEvent]? = []
}

struct RideRawEvent: Codable, Identifiable {
    var id = UUID()
    var timestamp: Int64
    var uuid: String
    var data: Data
}

struct RideTelemetrySample: Codable, Identifiable {
    var id = UUID()
    var time: Date
    var speedMph: Double?
    var batteryPercent: Int?
    var batteryVoltage: Double?
    var currentAmps: Double?
    var motorTemperature: Int?
    var controllerTemperature: Int?
    var rideMode: String?
}

struct RideLocation: Codable, Identifiable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    var time: Date
}

@MainActor
final class RideRecorder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var locationAvailable = false
    @Published private(set) var locationStatus = "Location is used to record ride distance."
    @Published private(set) var rides: [RideRecord] = []
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var maximumSpeedMph: Double = 0

    private let locationManager = CLLocationManager()
    private var startedAt: Date?
    private var previousLocation: CLLocation?
    private var timer: Timer?
    private var activeSamples: [RideTelemetrySample] = []
    private var activeRawEvents: [RideRawEvent] = []
    private var activeRoute: [RideLocation] = []
    private var lastSampleAt: Date?
    private var pendingStartAfterAuthorization = false
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .otherNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        rides = (try? JSONDecoder().decode([RideRecord].self, from: Data(contentsOf: Self.ridesURL))) ?? []
    }

    func start(currentSpeedMph: Double?) {
        guard CLLocationManager.locationServicesEnabled() else {
            locationStatus = "Turn on Location Services to record rides."
            return
        }
        if locationManager.authorizationStatus == .notDetermined {
            locationStatus = "Allow location access to record rides."
            pendingStartAfterAuthorization = true
            locationManager.requestWhenInUseAuthorization()
            return
        }
        guard locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse else {
            pendingStartAfterAuthorization = false
            locationStatus = "Allow location access in Settings to record rides."
            return
        }
        pendingStartAfterAuthorization = false
        startedAt = Date()
        previousLocation = nil
        distanceMeters = 0
        elapsed = 0
        maximumSpeedMph = currentSpeedMph ?? 0
        activeSamples = []
        activeRawEvents = []
        activeRoute = []
        lastSampleAt = nil
        isRecording = true
        locationStatus = "Recording ride with GPS."
        locationManager.startUpdatingLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateElapsed() }
        }
    }

    func stop(currentSpeedMph: Double?) {
        guard isRecording, let startedAt else { return }
        updateMaximumSpeed(currentSpeedMph)
        let record = RideRecord(startedAt: startedAt, duration: Date().timeIntervalSince(startedAt), distanceMeters: distanceMeters, maximumSpeedMph: maximumSpeedMph, samples: activeSamples, route: activeRoute, rawEvents: activeRawEvents)
        rides.insert(record, at: 0)
        isRecording = false
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        self.startedAt = nil
        locationStatus = "Ride saved on this iPhone."
        save()
    }

    func updateMaximumSpeed(_ speed: Double?) {
        guard isRecording, let speed, speed.isFinite else { return }
        maximumSpeedMph = max(maximumSpeedMph, speed)
    }

    func captureTelemetry(speedMph: Double?, batteryPercent: Int?, batteryVoltage: Double?, currentAmps: Double?, motorTemperature: Int?, controllerTemperature: Int?, rideMode: String?, rawUUID: String?, rawData: Data?) {
        guard isRecording else { return }
        let now = Date()
        if let rawUUID, let rawData {
            activeRawEvents.append(RideRawEvent(timestamp: Int64(now.timeIntervalSince1970 * 1000), uuid: rawUUID.uppercased(), data: rawData))
        }
        guard lastSampleAt.map({ now.timeIntervalSince($0) >= 1 }) ?? true else { return }
        activeSamples.append(RideTelemetrySample(time: now, speedMph: speedMph, batteryPercent: batteryPercent, batteryVoltage: batteryVoltage, currentAmps: currentAmps, motorTemperature: motorTemperature, controllerTemperature: controllerTemperature, rideMode: rideMode))
        lastSampleAt = now
    }

    func rename(_ ride: RideRecord, to name: String) {
        guard let index = rides.firstIndex(where: { $0.id == ride.id }) else { return }
        rides[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
        save()
    }

    func delete(_ ride: RideRecord) {
        rides.removeAll { $0.id == ride.id }
        save()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAvailable = manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse
        if locationAvailable, pendingStartAfterAuthorization, startedAt == nil {
            pendingStartAfterAuthorization = false
            start(currentSpeedMph: nil)
        }
        if !locationAvailable && (manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted) {
            pendingStartAfterAuthorization = false
            locationStatus = "Allow location access in Settings to record rides."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRecording else { return }
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 50 {
            if let previousLocation, location.timestamp > previousLocation.timestamp {
                let segment = location.distance(from: previousLocation)
                if segment.isFinite && segment < 100 { distanceMeters += segment }
            }
            previousLocation = location
            activeRoute.append(RideLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, time: location.timestamp))
        }
    }

    private func updateElapsed() {
        guard let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rides) else { return }
        try? data.write(to: Self.ridesURL, options: .atomic)
    }

    private static var ridesURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("rides.json")
    }
}
