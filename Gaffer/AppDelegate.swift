import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var monitorService: MonitorService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMonitor()
        applyWallpapersOnStartup()
    }

    private func applyWallpapersOnStartup() {
        Task {
            // Clean up any references to old cache location
            WallpaperService.shared.cleanupLegacyCache()

            // Check if we need to regenerate (build changed or cache missing)
            if CacheManager.shared.needsRegeneration() {
                print("Build changed, clearing cache and regenerating...")
                CacheManager.shared.clearGenerated()
            }

            // Process all displays
            await WallpaperService.shared.processAllDisplays()

            // Mark cache as valid for this build
            CacheManager.shared.markCacheValid()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Gaffer")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 320)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: MenuBarView())
    }

    private func setupMonitor() {
        monitorService = MonitorService.shared
        monitorService?.startMonitoring()
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
