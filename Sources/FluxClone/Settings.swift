import Foundation

enum Settings {
    private static let d = UserDefaults.standard

    static func register() {
        d.register(defaults: ["enabled": true, "nightKelvin": 3400.0, "nightBrightness": 1.0])
    }

    static var enabled: Bool {
        get { d.bool(forKey: "enabled") }
        set { d.set(newValue, forKey: "enabled") }
    }

    static var nightKelvin: Double {
        get { d.double(forKey: "nightKelvin") }
        set { d.set(newValue, forKey: "nightKelvin") }
    }

    static var nightBrightness: Double {
        get { d.double(forKey: "nightBrightness") }
        set { d.set(newValue, forKey: "nightBrightness") }
    }

    static var pausedUntil: Date? {
        get { d.object(forKey: "pausedUntil") as? Date }
        set { d.set(newValue, forKey: "pausedUntil") }
    }

    static var location: (lat: Double, lon: Double)? {
        get {
            guard d.object(forKey: "lat") != nil, d.object(forKey: "lon") != nil else { return nil }
            return (d.double(forKey: "lat"), d.double(forKey: "lon"))
        }
        set {
            d.set(newValue?.lat, forKey: "lat")
            d.set(newValue?.lon, forKey: "lon")
        }
    }
}
