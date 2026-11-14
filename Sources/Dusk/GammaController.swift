import CoreGraphics
import Foundation

/// Tints all displays by scaling their gamma tables (the same mechanism f.lux uses).
final class GammaController {
    private typealias Table = (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue])
    private var originals: [CGDirectDisplayID: Table] = [:]

    private(set) var kelvin: Double = 6500
    private(set) var brightness: Double = 1
    /// Whether we currently have a tint applied (so we only restore ColorSync on the transition).
    private var tinted = false

    init() {
        // Start from a clean state (in case a previous run left a tint) before capturing tables.
        CGDisplayRestoreColorSyncSettings()
    }

    /// Tanner Helland blackbody approximation, normalised so 6500K == (1, 1, 1).
    static func rgb(forKelvin k: Double) -> (r: Double, g: Double, b: Double) {
        func raw(_ k: Double) -> (Double, Double, Double) {
            let t = k / 100
            let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
            let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661
                            : 288.1221695283 * pow(t - 60, -0.0755148492)
            let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
            return (min(max(r, 0), 255), min(max(g, 0), 255), min(max(b, 0), 255))
        }
        let ref = raw(6500)
        let v = raw(k)
        return (min(v.0 / ref.0, 1), min(v.1 / ref.1, 1), min(v.2 / ref.2, 1))
    }

    var isNeutral: Bool { kelvin >= 6499 && brightness >= 0.999 }

    func apply(kelvin: Double, brightness: Double) {
        self.kelvin = kelvin
        self.brightness = brightness
        reapply()
    }

    /// Push the current values to every online display (also used after wake / display changes).
    func reapply() {
        if isNeutral {
            if tinted { CGDisplayRestoreColorSyncSettings() }
            tinted = false
            return
        }
        tinted = true
        let c = Self.rgb(forKelvin: kelvin)
        let mr = Float(c.r * brightness), mg = Float(c.g * brightness), mb = Float(c.b * brightness)
        for id in Self.onlineDisplays() {
            let o = original(for: id)
            let r = o.r.map { $0 * mr }, g = o.g.map { $0 * mg }, b = o.b.map { $0 * mb }
            CGSetDisplayTransferByTable(id, UInt32(r.count), r, g, b)
        }
    }

    func reset() {
        kelvin = 6500
        brightness = 1
        tinted = false
        CGDisplayRestoreColorSyncSettings()
    }

    private func original(for id: CGDirectDisplayID) -> Table {
        if let t = originals[id] { return t }
        let cap = Int(CGDisplayGammaTableCapacity(id))
        var table: Table
        if cap > 0 {
            var r = [CGGammaValue](repeating: 0, count: cap)
            var g = r, b = r
            var count: UInt32 = 0
            CGGetDisplayTransferByTable(id, UInt32(cap), &r, &g, &b, &count)
            let n = Int(count)
            table = n > 1 ? (Array(r[..<n]), Array(g[..<n]), Array(b[..<n])) : Self.linear()
        } else {
            table = Self.linear()
        }
        originals[id] = table
        return table
    }

    private static func linear() -> Table {
        let v = (0..<256).map { CGGammaValue($0) / 255 }
        return (v, v, v)
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }
        return Array(ids[..<Int(count)])
    }
}
