import AppKit
import Combine
import IOKit.ps

class MonitorService {
    static let shared = MonitorService()

    // Debug logging - enabled in debug builds
    #if DEBUG
    private let debugEnabled = true
    #else
    private let debugEnabled = false
    #endif

    private var timer: Timer?
    private var burstTimer: Timer?
    private var spaceObserver: NSObjectProtocol?
    private var displayObserver: NSObjectProtocol?
    private var appearanceObserver: NSKeyValueObservation?
    private var powerObserver: NSObjectProtocol?
    private var lastAppearanceIsDark: Bool?
    private var lastSpaceCount: Int = 0

    // Burst mode: rapid polling after space changes when on AC power
    private var burstModeActive = false
    private var burstModeEndTime: Date?
    private var lastSpaceChangeTime: Date?

    // Sustained mode: moderate polling (1-2Hz) for 60s after successful update
    private var sustainedModeActive = false
    private var sustainedModeEndTime: Date?
    private var sustainedTimer: Timer?

    private init() {}

    private func debugLog(_ message: String) {
        if debugEnabled {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            print("[\(timestamp)] [Monitor] \(message)")
        }
    }

    func startMonitoring() {
        updateSpaceCount()
        setupTimer()
        setupSpaceChangeObserver()
        setupDisplayChangeObserver()
        setupAppearanceObserver()
        setupPowerObserver()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil

        burstTimer?.invalidate()
        burstTimer = nil
        burstModeActive = false

        sustainedTimer?.invalidate()
        sustainedTimer = nil
        sustainedModeActive = false

        if let observer = spaceObserver {
            NotificationCenter.default.removeObserver(observer)
            spaceObserver = nil
        }

        if let observer = displayObserver {
            NotificationCenter.default.removeObserver(observer)
            displayObserver = nil
        }

        if let observer = powerObserver {
            NotificationCenter.default.removeObserver(observer)
            powerObserver = nil
        }

        appearanceObserver?.invalidate()
        appearanceObserver = nil
    }

    private func setupTimer() {
        timer?.invalidate()

        let mode = AppConfig.shared.updateMode

        // Off mode: no polling at all
        if mode == .off {
            print("Update mode: OFF - no polling")
            return
        }

        // Determine base interval based on mode and power state
        let interval = getNormalInterval(mode: mode)

        print("Update mode: \(mode.displayName) - interval: \(Int(interval))s (AC: \(isOnACPower()), battery: \(getBatteryLevel())%)")

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.performCheck()
        }
    }

    func restartTimer() {
        setupTimer()
    }

    // MARK: - Polling Parameters

    /// Normal polling interval based on mode and power state
    private func getNormalInterval(mode: UpdateMode) -> TimeInterval {
        let onAC = isOnACPower()
        let battery = getBatteryLevel()

        switch mode {
        case .off:
            return 0  // Not used
        case .snappy:
            // Snappy: very responsive
            if onAC {
                return 1.0  // 1Hz on AC
            } else if battery > 20 {
                return 5.0   // 5s on battery
            } else {
                return 15.0  // 15s on low battery
            }
        case .smarty:
            // Smarty: balanced approach
            if onAC {
                return 10.0  // 10s on AC
            } else if battery > 50 {
                return 30.0  // 30s on good battery
            } else if battery > 20 {
                return 60.0  // 1min on moderate battery
            } else {
                return 120.0 // 2min on low battery
            }
        case .thrifty:
            // Thrifty: power-conscious
            if onAC {
                return 60.0  // 1min on AC
            } else if battery > 30 {
                return 300.0 // 5min on battery
            } else {
                return 600.0 // 10min on low battery
            }
        }
    }

    /// Burst mode parameters based on mode and power state
    private func getBurstParams(mode: UpdateMode) -> (interval: TimeInterval, duration: TimeInterval) {
        let onAC = isOnACPower()

        switch mode {
        case .snappy:
            // Snappy: very aggressive burst
            return onAC ? (0.025, 8.0) : (0.05, 5.0)  // 40Hz/8s on AC, 20Hz/5s on battery
        case .smarty:
            // Smarty: moderate burst
            return onAC ? (0.05, 5.0) : (0.1, 3.0)   // 20Hz/5s on AC, 10Hz/3s on battery
        case .thrifty:
            // Thrifty: 5Hz on AC, minimal on battery
            return onAC ? (0.2, 3.0) : (0.5, 2.0)    // 5Hz/3s on AC, 2Hz/2s on battery
        default:
            return (1.0, 1.0)  // Off: minimal
        }
    }

    /// Sustained mode parameters based on mode and power state
    private func getSustainedParams(mode: UpdateMode) -> (interval: TimeInterval, duration: TimeInterval) {
        let onAC = isOnACPower()
        let battery = getBatteryLevel()

        switch mode {
        case .snappy:
            // Snappy: aggressive sustained
            if onAC {
                return (0.1, 180.0)  // 10Hz for 3min on AC
            } else {
                return (0.25, 90.0)  // 4Hz for 90s on battery
            }
        case .smarty:
            // Smarty: balanced sustained
            if onAC {
                return (0.25, 120.0) // 4Hz for 2min on AC
            } else if battery > 50 {
                return (0.5, 60.0)   // 2Hz for 1min on good battery
            } else {
                return (1.0, 30.0)   // 1Hz for 30s on low battery
            }
        case .thrifty:
            // Thrifty: 2Hz on AC, minimal on battery
            if onAC {
                return (0.5, 60.0)   // 2Hz for 1min on AC
            } else {
                return (2.0, 30.0)   // 0.5Hz for 30s on battery
            }
        default:
            return (5.0, 10.0)  // Off: minimal
        }
    }

    private func setupSpaceChangeObserver() {
        spaceObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSpaceChange()
        }
    }

    private func handleSpaceChange() {
        lastSpaceChangeTime = Date()
        updateSpaceCount()

        // Immediately perform a check
        performCheck()

        let mode = AppConfig.shared.updateMode
        guard mode != .off else { return }

        // If in sustained mode, extend it and trigger burst
        if sustainedModeActive {
            let params = getSustainedParams(mode: mode)
            sustainedModeEndTime = Date().addingTimeInterval(params.duration)
            debugLog("Extended sustained mode for \(Int(params.duration))s due to space change")
        }

        // Exit sustained and enter burst for rapid updates
        if sustainedModeActive {
            sustainedTimer?.invalidate()
            sustainedTimer = nil
            sustainedModeActive = false
        }
        enterBurstMode()
    }

    private func enterBurstMode() {
        let mode = AppConfig.shared.updateMode
        guard mode != .off else { return }

        let params = getBurstParams(mode: mode)

        if burstModeActive {
            // Already in burst mode, extend the end time
            burstModeEndTime = Date().addingTimeInterval(params.duration)
            debugLog("Extended burst mode for \(params.duration)s")
            return
        }

        burstModeActive = true
        burstModeEndTime = Date().addingTimeInterval(params.duration)

        debugLog("Entering burst mode: \(Int(1/params.interval))Hz for \(params.duration)s")

        // Cancel normal timer during burst mode
        timer?.invalidate()

        burstTimer = Timer.scheduledTimer(withTimeInterval: params.interval, repeats: true) { [weak self] _ in
            self?.burstModeCheck()
        }
    }

    private func burstModeCheck() {
        guard burstModeActive else {
            exitBurstMode()
            return
        }

        // Check if burst mode should end
        if let endTime = burstModeEndTime, Date() > endTime {
            exitBurstMode()
            return
        }

        // Perform rapid check
        performCheck()
    }

    private func exitBurstMode() {
        guard burstModeActive else { return }

        burstModeActive = false
        burstModeEndTime = nil

        burstTimer?.invalidate()
        burstTimer = nil

        // After burst mode, enter sustained mode for continued monitoring
        let mode = AppConfig.shared.updateMode
        if mode != .off {
            enterSustainedMode()
        } else {
            debugLog("Exiting burst mode, resuming normal polling")
            setupTimer()
        }
    }

    private func enterSustainedMode() {
        let mode = AppConfig.shared.updateMode
        let params = getSustainedParams(mode: mode)

        if sustainedModeActive {
            // Already in sustained mode, extend the end time
            sustainedModeEndTime = Date().addingTimeInterval(params.duration)
            debugLog("Extended sustained mode for \(Int(params.duration))s")
            return
        }

        sustainedModeActive = true
        sustainedModeEndTime = Date().addingTimeInterval(params.duration)

        debugLog("Entering sustained mode: \(1/params.interval)Hz for \(Int(params.duration))s")

        // Cancel normal timer during sustained mode
        timer?.invalidate()

        sustainedTimer = Timer.scheduledTimer(withTimeInterval: params.interval, repeats: true) { [weak self] _ in
            self?.sustainedModeCheck()
        }
    }

    private func sustainedModeCheck() {
        guard sustainedModeActive else {
            exitSustainedMode()
            return
        }

        // Check if sustained mode should end
        if let endTime = sustainedModeEndTime, Date() > endTime {
            exitSustainedMode()
            return
        }

        // Perform moderate-speed check
        performCheck()
    }

    private func exitSustainedMode() {
        guard sustainedModeActive else { return }

        sustainedModeActive = false
        sustainedModeEndTime = nil

        sustainedTimer?.invalidate()
        sustainedTimer = nil

        debugLog("Exiting sustained mode, resuming normal polling")

        // Resume normal timer
        setupTimer()
    }

    private func setupDisplayChangeObserver() {
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplayChange()
        }
    }

    private func handleDisplayChange() {
        debugLog("Display configuration changed")

        // Short delay to let the system settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.performCheck()

            let mode = AppConfig.shared.updateMode
            guard mode != .off else { return }

            // Exit sustained mode if active
            if self?.sustainedModeActive == true {
                self?.sustainedTimer?.invalidate()
                self?.sustainedTimer = nil
                self?.sustainedModeActive = false
            }

            // Enter burst mode with slightly longer duration for display changes
            self?.enterBurstMode()
        }
    }

    private func setupAppearanceObserver() {
        // Track initial state
        lastAppearanceIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Observe changes to effective appearance
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.handleAppearanceChange()
        }
    }

    private func handleAppearanceChange() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Only act if appearance actually changed
        guard isDark != lastAppearanceIsDark else { return }
        lastAppearanceIsDark = isDark

        // Only refresh if appearance mode is "auto"
        guard AppConfig.shared.appearanceMode == .auto else { return }

        print("System appearance changed to \(isDark ? "dark" : "light"), refreshing wallpapers...")

        Task {
            await WallpaperService.shared.refresh()
        }
    }

    private func performCheck() {
        Task {
            await WallpaperService.shared.processAllDisplays()

            // If "All Spaces" is enabled, apply to all spaces after processing
            if AppConfig.shared.applyToAllSpaces {
                await WallpaperService.shared.applyToAllSpaces()
            }
        }
    }

    // MARK: - Space Tracking

    private func updateSpaceCount() {
        let script = "tell application \"System Events\" to return count of desktops"
        var error: NSDictionary?
        if let result = NSAppleScript(source: script)?.executeAndReturnError(&error) {
            let count = Int(result.int32Value)
            if count != lastSpaceCount {
                print("Space count changed: \(lastSpaceCount) → \(count)")
                lastSpaceCount = count
                AppConfig.shared.spaceCount = count
                AppConfig.shared.save()
            }
        }
    }

    private func setupPowerObserver() {
        // Observe power source changes to adjust polling
        powerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "NSProcessInfoPowerStateDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handlePowerChange()
        }
    }

    private func handlePowerChange() {
        print("Power state changed, reconfiguring timer...")
        setupTimer()
    }

    // MARK: - Battery Status

    private func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return true  // Assume AC if we can't determine
        }

        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let powerSource = description[kIOPSPowerSourceStateKey as String] as? String {
                return powerSource == kIOPSACPowerValue as String
            }
        }
        return true
    }

    private func getBatteryLevel() -> Int {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return 100  // Assume full if we can't determine
        }

        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let capacity = description[kIOPSCurrentCapacityKey as String] as? Int {
                return capacity
            }
        }
        return 100
    }
}
