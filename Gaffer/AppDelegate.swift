import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        MonitorService.shared.startMonitoring()
        applyWallpapersOnStartup()
    }

    private func applyWallpapersOnStartup() {
        Task {
            WallpaperService.shared.cleanupLegacyCache()

            if CacheManager.shared.needsRegeneration() {
                print("Build changed, clearing cache and regenerating...")
                CacheManager.shared.clearGenerated()
            }

            await WallpaperService.shared.processAllDisplays()
            CacheManager.shared.markCacheValid()
        }
    }
}
