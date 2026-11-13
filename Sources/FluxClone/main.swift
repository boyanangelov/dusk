import AppKit

// Debug: `FluxClone --print-schedule [lat lon]` prints today's sun schedule and exits.
if let i = CommandLine.arguments.firstIndex(of: "--print-schedule") {
    Settings.register()
    let args = CommandLine.arguments.dropFirst(i + 1).compactMap(Double.init)
    let loc = args.count >= 2 ? (lat: args[0], lon: args[1]) : (Settings.location ?? (lat: 52.52, lon: 13.40))
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm"
    let sun = SunSchedule.sunTimes(on: Date(), lat: loc.lat, lon: loc.lon)
    print(String(format: "Location %.2f, %.2f", loc.lat, loc.lon))
    print("Sunrise", sun.sunrise.map(fmt.string) ?? "-", " Sunset", sun.sunset.map(fmt.string) ?? "-")
    let start = Calendar.current.startOfDay(for: Date())
    for q in stride(from: 0, to: 24 * 4, by: 1) {
        let d = start.addingTimeInterval(Double(q) * 900)
        let e = SunSchedule.elevation(at: d, lat: loc.lat, lon: loc.lon)
        let f = SunSchedule.nightFactor(at: d, lat: loc.lat, lon: loc.lon)
        let k = 6500 + (Settings.nightKelvin - 6500) * f
        print(String(format: "%@  elev %6.1f°  night %.2f  %4.0fK", fmt.string(from: d), e, f, k))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
