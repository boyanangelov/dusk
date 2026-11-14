import Foundation

/// Local sun-position math (sunrise equation / NOAA-style approximations). No network needed.
enum SunSchedule {
    static let dayKelvin = 6500.0
    /// Fully "night" below this sun elevation (civil twilight).
    static let nightElevation = -6.0
    /// Fully "day" above this sun elevation.
    static let dayElevation = 3.0

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }
    private static func julian(_ date: Date) -> Double { date.timeIntervalSince1970 / 86400 + 2440587.5 }
    private static func date(julian j: Double) -> Date { Date(timeIntervalSince1970: (j - 2440587.5) * 86400) }

    /// Solar transit, declination and the hour angle at sunrise for the solar day nearest `j`.
    private static func solarDay(nearJulian j: Double, lat: Double, lon: Double)
        -> (transit: Double, decl: Double, omega0: Double?, cosOmega: Double)
    {
        let n = (j - 2451545.0 + lon / 360).rounded()
        let jStar = n - lon / 360
        let m = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
        let c = 1.9148 * sin(rad(m)) + 0.02 * sin(rad(2 * m)) + 0.0003 * sin(rad(3 * m))
        let lambda = (m + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2451545.0 + jStar + 0.0053 * sin(rad(m)) - 0.0069 * sin(rad(2 * lambda))
        let decl = asin(sin(rad(lambda)) * sin(rad(23.4397)))
        let cosW = (sin(rad(-0.833)) - sin(rad(lat)) * sin(decl)) / (cos(rad(lat)) * cos(decl))
        let omega0: Double? = abs(cosW) <= 1 ? deg(acos(cosW)) : nil
        return (transit, decl, omega0, cosW)
    }

    /// Sun elevation above the horizon in degrees.
    static func elevation(at date: Date, lat: Double, lon: Double) -> Double {
        let j = julian(date)
        let s = solarDay(nearJulian: j, lat: lat, lon: lon)
        let hourAngle = rad((j - s.transit) * 360)
        let sinAlt = sin(rad(lat)) * sin(s.decl) + cos(rad(lat)) * cos(s.decl) * cos(hourAngle)
        return deg(asin(max(-1, min(1, sinAlt))))
    }

    /// Sunrise and sunset for the local calendar day containing `date` (nil in polar day/night).
    static func sunTimes(on date: Date, lat: Double, lon: Double) -> (sunrise: Date?, sunset: Date?) {
        var cal = Calendar.current
        cal.timeZone = .current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let s = solarDay(nearJulian: julian(noon), lat: lat, lon: lon)
        guard let w = s.omega0 else { return (nil, nil) }
        return (Self.date(julian: s.transit - w / 360), Self.date(julian: s.transit + w / 360))
    }

    /// Next sunrise strictly after `date`.
    static func nextSunrise(after date: Date, lat: Double, lon: Double) -> Date? {
        for offset in 0...2 {
            let day = date.addingTimeInterval(Double(offset) * 86400)
            if let rise = sunTimes(on: day, lat: lat, lon: lon).sunrise, rise > date { return rise }
        }
        return nil
    }

    /// 0 = full day, 1 = full night. Linear across twilight, so the change is gradual (~1h).
    static func nightFactor(at date: Date, lat: Double, lon: Double) -> Double {
        let e = elevation(at: date, lat: lat, lon: lon)
        let f = (dayElevation - e) / (dayElevation - nightElevation)
        return min(max(f, 0), 1)
    }
}
