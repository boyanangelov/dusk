import CoreLocation
import Foundation

/// Gets a coarse location once (and on refresh), caching it so the app works offline / if denied later.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onUpdate: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// `DUSK_LOCATION="48.86,2.35"` pins the location (for testing and demos) and skips CoreLocation.
    private let pinned: (lat: Double, lon: Double)? = {
        let parts = (ProcessInfo.processInfo.environment["DUSK_LOCATION"] ?? "")
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }()

    var isApproximate: Bool { pinned == nil && Settings.location == nil }

    /// Cached real location, or a rough guess from the time zone (lat 45°, lon from UTC offset).
    var coordinate: (lat: Double, lon: Double) {
        if let loc = pinned ?? Settings.location { return loc }
        let tz = TimeZone.current
        let standardOffset = Double(tz.secondsFromGMT()) - tz.daylightSavingTimeOffset()
        return (45, standardOffset / 3600 * 15)
    }

    func refresh() {
        guard pinned == nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if s == .authorizedAlways { manager.requestLocation() }
        onUpdate?()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Settings.location = (c.latitude, c.longitude)
        onUpdate?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep using the cached / approximate location.
    }
}
