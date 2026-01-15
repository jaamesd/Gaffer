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

    private var burstTimer: Timer?
    private var spaceObserver: NSObjectProtocol?
    private var displayObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var powerObserver: NSObjectProtocol?
    private var lastAppearanceIsDark: Bool?
    private var lastSpaceCount: Int = 0

    // File system monitoring for wallpaper changes
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    // Burst mode: rapid checking after events
    private var burstModeActive = false
    private var burstModeEndTime: Date?
    private var lastSpaceChangeTime: Date?

    private init() {}

    private func debugLog(_ message: String) {
        if debugEnabled {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            print("[\(timestamp)] [Monitor] \(message)")
        }
    }

    func startMonitoring() {
        debugLog("Starting monitoring")
        updateSpaceCount()
        setupFileMonitor()
        setupSpaceChangeObserver()
        setupDisplayChangeObserver()
        setupAppearanceObserver()
        setupPowerObserver()
    }

    func stopMonitoring() {
        // Stop file monitor
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        burstTimer?.invalidate()
        burstTimer = nil
        burstModeActive = false

        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
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

        if let observer = appearanceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appearanceObserver = nil
        }
    }

    // MARK: - File System Monitoring

    private func setupFileMonitor() {
        // Watch for wallpaper changes - try multiple locations for compatibility
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Modern macOS (Ventura+): plist in Preferences
        let plistPath = home.appendingPathComponent("Library/Preferences/com.apple.wallpaper.plist")
        // Legacy macOS: SQLite database in Dock folder
        let dbPath = home.appendingPathComponent("Library/Application Support/Dock/desktoppicture.db")

        let pathToWatch: URL
        if FileManager.default.fileExists(atPath: plistPath.path) {
            pathToWatch = plistPath
        } else if FileManager.default.fileExists(atPath: dbPath.path) {
            pathToWatch = dbPath
        } else {
            print("No wallpaper config file found - file monitor disabled")
            print("  Tried: \(plistPath.path)")
            print("  Tried: \(dbPath.path)")
            return
        }

        fileDescriptor = open(pathToWatch.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Failed to open wallpaper config for monitoring: \(pathToWatch.path)")
            return
        }

        fileMonitorSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: .main
        )

        fileMonitorSource?.setEventHandler { [weak self] in
            self?.handleWallpaperFileChange()
        }

        fileMonitorSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        fileMonitorSource?.resume()
        print("File monitor started on: \(pathToWatch.lastPathComponent)")
    }

    private func handleWallpaperFileChange() {
        debugLog("Desktop picture database changed")

        // Check immediately for quick response
        performCheck()

        // Retry with increasing delays to catch macOS settling
        // Longer delays help detect external wallpaper changes reliably
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.performCheck()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.performCheck()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.performCheck()
        }

        // Enter burst mode for continued monitoring
        let mode = AppConfig.shared.updateMode
        if mode != .off {
            enterBurstMode()
        }
    }

    /// Burst mode parameters based on mode and power state
    private func getBurstParams(mode: UpdateMode) -> (interval: TimeInterval, duration: TimeInterval) {
        let onAC = isOnACPower()

        switch mode {
        case .snappy:
            return onAC ? (0.025, 5.0) : (0.05, 3.0)  // 40Hz/5s on AC, 20Hz/3s on battery
        case .smarty:
            return onAC ? (0.05, 3.0) : (0.1, 2.0)    // 20Hz/3s on AC, 10Hz/2s on battery
        case .thrifty:
            return onAC ? (0.2, 2.0) : (0.5, 1.0)     // 5Hz/2s on AC, 2Hz/1s on battery
        default:
            return (1.0, 1.0)
        }
    }

    private func setupSpaceChangeObserver() {
        // Must use workspace notification center for workspace notifications
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            self?.handleSpaceChange()
        }
    }

    private func handleSpaceChange() {
        lastSpaceChangeTime = Date()
        updateSpaceCount()

        // Check immediately, then retry after short delays to catch macOS settling
        // The space transition timing is variable, so we check multiple times
        performCheck()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.performCheck()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.performCheck()
        }

        let mode = AppConfig.shared.updateMode
        guard mode != .off else { return }

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

        debugLog("Exiting burst mode")
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

            self?.enterBurstMode()
        }
    }

    private func setupAppearanceObserver() {
        lastAppearanceIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // accessibilityDisplayOptionsDidChangeNotification is more reliable than KVO -
        // catches system-wide changes including auto dark/light switching
        appearanceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
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
        // Observe power source changes - burst mode parameters adapt automatically
        powerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "NSProcessInfoPowerStateDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.debugLog("Power state changed")
        }
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
