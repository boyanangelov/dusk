import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let gamma = GammaController()
    private let location = LocationProvider()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private let nowLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let sunLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let locationLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var enabledItem: NSMenuItem!
    private var pauseHourItem: NSMenuItem!
    private var pauseSunriseItem: NSMenuItem!
    private var resumeItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var warmthSlider: NSSlider!
    private var warmthLabel: NSTextField!
    private var brightSlider: NSSlider!
    private var brightLabel: NSTextField!

    private var timers: [Timer] = []
    private var animTimer: Timer?
    private var previewing = false
    private var signalSources: [DispatchSourceSignal] = []

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.register()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        statusItem.menu = menu

        location.onUpdate = { [weak self] in self?.update(animated: true) }
        location.refresh()
        observeSystem()

        addTimer(every: 30) { [weak self] in self?.update(animated: false) }
        addTimer(every: 6 * 3600) { [weak self] in self?.location.refresh() }
        update(animated: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        gamma.reset()
    }

    private func addTimer(every seconds: TimeInterval, _ block: @escaping () -> Void) {
        let t = Timer(timeInterval: seconds, repeats: true) { _ in block() }
        RunLoop.main.add(t, forMode: .common)  // keep firing while the menu is open
        timers.append(t)
    }

    // MARK: Core logic

    /// Current time; `DUSK_FAKE_HOUR=21.5` overrides it for testing.
    private func now() -> Date {
        if let s = ProcessInfo.processInfo.environment["DUSK_FAKE_HOUR"], let h = Double(s) {
            let start = Calendar.current.startOfDay(for: Date())
            return start.addingTimeInterval(h * 3600)
        }
        return Date()
    }

    private var isPaused: Bool {
        guard let p = Settings.pausedUntil else { return false }
        return p > now()
    }

    private func nightFactor(at date: Date) -> Double {
        let c = location.coordinate
        return SunSchedule.nightFactor(at: date, lat: c.lat, lon: c.lon)
    }

    private func target(at date: Date) -> (kelvin: Double, brightness: Double) {
        guard Settings.enabled, !isPaused else { return (SunSchedule.dayKelvin, 1) }
        let f = nightFactor(at: date)
        let k = SunSchedule.dayKelvin + (Settings.nightKelvin - SunSchedule.dayKelvin) * f
        let b = 1 + (Settings.nightBrightness - 1) * f
        return (k, b)
    }

    private func update(animated: Bool) {
        if let p = Settings.pausedUntil, p <= now() { Settings.pausedUntil = nil }
        refreshMenu()
        guard !previewing else { return }
        let t = target(at: now())
        if animated {
            animate(toKelvin: t.kelvin, brightness: t.brightness)
        } else if animTimer == nil {
            gamma.apply(kelvin: t.kelvin, brightness: t.brightness)
        }
    }

    /// Smooth ~0.8s fade so toggles don't snap.
    private func animate(toKelvin k: Double, brightness b: Double) {
        animTimer?.invalidate()
        let k0 = gamma.kelvin, b0 = gamma.brightness
        if abs(k0 - k) < 1 && abs(b0 - b) < 0.001 {
            animTimer = nil
            gamma.apply(kelvin: k, brightness: b)
            return
        }
        let steps = 24
        var i = 0
        let t = Timer(timeInterval: 0.8 / Double(steps), repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            i += 1
            let p = Double(i) / Double(steps)
            let e = p * p * (3 - 2 * p)  // smoothstep
            self.gamma.apply(kelvin: k0 + (k - k0) * e, brightness: b0 + (b - b0) * e)
            if i >= steps {
                timer.invalidate()
                self.animTimer = nil
            }
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    // MARK: System events (macOS may reset gamma tables)

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(self, selector: #selector(systemChanged), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { me.systemChanged() }
        }, Unmanaged.passUnretained(self).toOpaque())

        // Make sure the screen is restored if we're killed.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                self?.gamma.reset()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    @objc private func systemChanged() {
        // Re-apply now and again shortly after; macOS sometimes resets tables late.
        for delay in [0.0, 1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.animTimer == nil else { return }
                self.gamma.reapply()
            }
        }
    }

    // MARK: Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        for item in [nowLine, sunLine, locationLine] { item.isEnabled = false; menu.addItem(item) }
        menu.addItem(.separator())

        enabledItem = item("Enabled", #selector(toggleEnabled), key: "e")
        menu.addItem(enabledItem)
        menu.addItem(.separator())

        var s = sliderItem(title: "", min: 1900, max: 6500, value: Settings.nightKelvin, action: #selector(warmthChanged))
        warmthSlider = s.slider; warmthLabel = s.label
        menu.addItem(s.item)
        s = sliderItem(title: "", min: 0.1, max: 1.0, value: Settings.nightBrightness, action: #selector(brightnessChanged))
        brightSlider = s.slider; brightLabel = s.label
        menu.addItem(s.item)
        menu.addItem(.separator())

        pauseHourItem = item("Disable for an hour", #selector(pauseHour))
        pauseSunriseItem = item("Disable until sunrise", #selector(pauseSunrise))
        resumeItem = item("Resume", #selector(resume))
        [pauseHourItem, pauseSunriseItem, resumeItem].forEach { menu.addItem($0!) }
        menu.addItem(.separator())

        loginItem = item("Start at Login", #selector(toggleLogin))
        menu.addItem(loginItem)
        menu.addItem(item("Quit Dusk", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func sliderItem(title: String, min: Double, max: Double, value: Double, action: Selector)
        -> (item: NSMenuItem, slider: NSSlider, label: NSTextField)
    {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 48))
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: 28, width: 324, height: 16)
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.isContinuous = true
        slider.frame = NSRect(x: 18, y: 4, width: 326, height: 22)
        view.addSubview(label)
        view.addSubview(slider)
        let item = NSMenuItem()
        item.view = view
        return (item, slider, label)
    }

    private func refreshMenu() {
        let date = now()
        let c = location.coordinate
        let night = nightFactor(at: date)
        let active = Settings.enabled && !isPaused

        // Icon
        let symbol = night > 0.5 ? (active ? "moon.fill" : "moon") : (active ? "sun.max.fill" : "sun.max")
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Dusk")
        img?.isTemplate = true
        statusItem.button?.image = img

        // Status lines
        let k = Int(gamma.kelvin.rounded())
        var now = "Now: \(k)K"
        if gamma.brightness < 0.999 { now += " · \(Int((gamma.brightness * 100).rounded()))% brightness" }
        if !Settings.enabled { now += " (off)" }
        if let p = Settings.pausedUntil, isPaused { now += " (paused until \(timeFormatter.string(from: p)))" }
        nowLine.title = now

        let sun = SunSchedule.sunTimes(on: date, lat: c.lat, lon: c.lon)
        if let rise = sun.sunrise, let set = sun.sunset {
            sunLine.title = "Sunrise \(timeFormatter.string(from: rise)) · Sunset \(timeFormatter.string(from: set))"
        } else {
            sunLine.title = night > 0.5 ? "Polar night" : "Midnight sun"
        }
        locationLine.title = location.isApproximate
            ? "Location: approximate (allow in Settings › Privacy)"
            : String(format: "Location: %.2f°, %.2f°", c.lat, c.lon)

        enabledItem.state = Settings.enabled ? .on : .off
        warmthLabel.stringValue = "Night colour: \(Int(Settings.nightKelvin))K"
        brightLabel.stringValue = String(format: "Night brightness: %.1f%%", Settings.nightBrightness * 100)
        pauseHourItem.isHidden = !Settings.enabled || isPaused
        pauseSunriseItem.isHidden = !Settings.enabled || isPaused
        resumeItem.isHidden = !isPaused
        loginItem.state = LoginItem.isEnabled ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        warmthSlider.doubleValue = Settings.nightKelvin
        brightSlider.doubleValue = Settings.nightBrightness
        refreshMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        if previewing {
            previewing = false
            update(animated: true)
        }
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        Settings.enabled.toggle()
        if Settings.enabled { Settings.pausedUntil = nil }
        update(animated: true)
    }

    @objc private func warmthChanged() {
        Settings.nightKelvin = (warmthSlider.doubleValue / 10).rounded() * 10
        preview()
    }

    @objc private func brightnessChanged() {
        Settings.nightBrightness = (brightSlider.doubleValue * 1000).rounded() / 1000
        preview()
    }

    /// While dragging, show the full night setting so it can be judged (even in daytime).
    private func preview() {
        previewing = true
        animTimer?.invalidate()
        animTimer = nil
        gamma.apply(kelvin: Settings.nightKelvin, brightness: Settings.nightBrightness)
        refreshMenu()
    }

    @objc private func pauseHour() {
        Settings.pausedUntil = now().addingTimeInterval(3600)
        update(animated: true)
    }

    @objc private func pauseSunrise() {
        let c = location.coordinate
        Settings.pausedUntil = SunSchedule.nextSunrise(after: now(), lat: c.lat, lon: c.lon)
            ?? now().addingTimeInterval(12 * 3600)
        update(animated: true)
    }

    @objc private func resume() {
        Settings.pausedUntil = nil
        update(animated: true)
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.set(!LoginItem.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Start at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        refreshMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
