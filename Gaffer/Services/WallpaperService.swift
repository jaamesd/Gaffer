import AppKit
import ImageIO

class WallpaperService {
    static let shared = WallpaperService()

    private let workspace = NSWorkspace.shared
    private let imageProcessor = ImageProcessor.shared

    /// Old cache location that needs cleanup
    private let legacyCachePath: URL

    /// Track when we last set wallpaper (per display) to avoid fighting with external changes
    private var lastSetTime: [String: Date] = [:]

    /// Cooldown period after we set a wallpaper - ignore file monitor events during this time
    private let setCooldown: TimeInterval = 2.0

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        legacyCachePath = home.appendingPathComponent(".gaffer-legacy")
    }

    /// Clean up any references to old cache location
    func cleanupLegacyCache() {
        // Check if current wallpaper points to old cache
        for screen in NSScreen.screens {
            if let currentURL = workspace.desktopImageURL(for: screen),
               currentURL.path.hasPrefix(legacyCachePath.path) {
                // Restore to source or clear the reference
                let displayName = screen.localizedName
                if let sourcePath = AppConfig.shared.sourceWallpaper[displayName] {
                    let sourceURL = URL(fileURLWithPath: sourcePath)
                    if FileManager.default.fileExists(atPath: sourceURL.path) {
                        try? workspace.setDesktopImageURL(sourceURL, for: screen, options: [:])
                    }
                }
            }
        }

        // Remove old cache directory
        try? FileManager.default.removeItem(at: legacyCachePath)
    }

    func getCurrentWallpaper(for screen: NSScreen) -> URL? {
        workspace.desktopImageURL(for: screen)
    }

    /// Get dimensions of an image file without loading the full image
    private func getImageDimensions(_ url: URL) -> CGSize? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    func setWallpaper(_ url: URL, for screen: NSScreen) throws {
        lastSetTime[screen.localizedName] = Date()
        try workspace.setDesktopImageURL(url, for: screen, options: [:])
    }

    /// Check if we recently set the wallpaper for this display (within cooldown period)
    func isInCooldown(for displayName: String) -> Bool {
        guard let lastSet = lastSetTime[displayName] else { return false }
        return Date().timeIntervalSince(lastSet) < setCooldown
    }

    /// Process wallpaper for all displays
    func processAllDisplays() async {
        for display in DisplayService.shared.getAllDisplays() {
            await processDisplay(display)
        }
    }

    /// Check if a URL points to one of our generated images
    func isGeneratedImage(_ url: URL) -> Bool {
        return url.path.hasPrefix(CacheManager.shared.basePath.path)
    }

    /// Process wallpaper for a single display
    func processDisplay(_ display: DisplayInfo) async {
        // Check current wallpaper
        guard let currentURL = getCurrentWallpaper(for: display.screen) else {
            print("[\(display.name)] No wallpaper set")
            return
        }

        let isCurrentProcessed = isGeneratedImage(currentURL)

        // If we're in cooldown and current wallpaper is NOT our generated image,
        // the user likely just changed wallpaper externally - let it settle
        if isInCooldown(for: display.name) && !isCurrentProcessed {
            print("[\(display.name)] In cooldown, skipping to let external change settle")
            return
        }

        print("[\(display.name)] Current: \(currentURL.lastPathComponent) (processed: \(isCurrentProcessed))")

        // Determine the source wallpaper first (needed for cache key)
        let sourceURL: URL
        if isCurrentProcessed {
            // Currently using a generated version, get stored source
            guard let sourcePath = AppConfig.shared.sourceWallpaper[display.name] else {
                print("[\(display.name)] No stored source - cannot process")
                return
            }
            let storedSource = URL(fileURLWithPath: sourcePath)
            // Safety check: ensure stored source is not also a generated image
            if isGeneratedImage(storedSource) {
                print("[\(display.name)] ⚠️ Stored source is a generated image - clearing to prevent loop")
                AppConfig.shared.sourceWallpaper.removeValue(forKey: display.name)
                AppConfig.shared.save()
                return
            }
            sourceURL = storedSource
            print("[\(display.name)] Using stored source: \(sourceURL.lastPathComponent)")
        } else {
            // Using original wallpaper, store it as source
            // But only if it's not one of our generated images!
            if isGeneratedImage(currentURL) {
                print("[\(display.name)] ⚠️ Current wallpaper appears to be generated - skipping")
                return
            }
            sourceURL = currentURL
            let wasStored = AppConfig.shared.sourceWallpaper[display.name]
            if wasStored != currentURL.path {
                print("[\(display.name)] New source detected, storing: \(sourceURL.lastPathComponent)")
                AppConfig.shared.sourceWallpaper[display.name] = currentURL.path
                // User changed wallpaper externally - disable "All Spaces" auto-apply
                if AppConfig.shared.applyToAllSpaces {
                    print("[\(display.name)] External wallpaper change detected - disabling All Spaces")
                    AppConfig.shared.applyToAllSpaces = false
                }
                AppConfig.shared.save()
            }
        }

        // Determine frame index FIRST (needed for cache key)
        let frameIndex = getFrameIndex(for: display, source: sourceURL)

        // Get the expected output URL for this display (includes frame index and source hash)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let outputURL = CacheManager.shared.generatedURL(display: display, source: sourceURL, ext: ext, frameIndex: frameIndex)

        // If already using our generated wallpaper with correct settings, skip
        // But only if the file actually exists!
        if currentURL.path == outputURL.path {
            if FileManager.default.fileExists(atPath: currentURL.path) {
                print("[\(display.name)] Already using correct processed version")
                return
            } else {
                print("[\(display.name)] Current wallpaper file missing, will regenerate")
            }
        }

        // Check if generated file already exists and has correct dimensions
        if FileManager.default.fileExists(atPath: outputURL.path) {
            // Verify cached image dimensions match display resolution
            if let cachedSize = getImageDimensions(outputURL),
               Int(cachedSize.width) == Int(display.physicalRes.width),
               Int(cachedSize.height) == Int(display.physicalRes.height) {
                do {
                    try setWallpaper(outputURL, for: display.screen)
                    print("[\(display.name)] ✓ Applied cached: \(outputURL.lastPathComponent)")
                } catch {
                    print("[\(display.name)] ✗ Failed to apply cached: \(error)")
                }
                return
            } else {
                // Dimensions mismatch - delete stale cache and regenerate
                print("[\(display.name)] ⚠️ Cached image dimensions mismatch, regenerating...")
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        print("[\(display.name)] Generating new processed wallpaper (frame: \(frameIndex ?? 0))...")
        guard let processedURL = await imageProcessor.processWallpaper(
            source: sourceURL,
            output: outputURL,
            display: display,
            frameIndex: frameIndex
        ) else {
            print("Failed to process wallpaper for: \(display.name)")
            return
        }

        // Apply the processed wallpaper
        do {
            try setWallpaper(processedURL, for: display.screen)
            print("Applied new wallpaper for: \(display.name)")
        } catch {
            print("Failed to set wallpaper: \(error)")
        }
    }

    /// Determine the frame index based on appearance mode and wallpaper type
    private func getFrameIndex(for display: DisplayInfo, source: URL) -> Int? {
        // Only applies to HEIC files (dynamic wallpapers)
        guard source.pathExtension.lowercased() == "heic" else { return nil }

        // Get total frame count
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 1 else { return nil }  // Static HEIC, no frame selection needed

        switch AppConfig.shared.appearanceMode {
        case .dark:
            return 0  // Dark frame is typically first
        case .light:
            return frameCount - 1  // Light frame is typically last
        case .auto:
            // Use saved preference or determine by system appearance
            if let saved = AppConfig.shared.selectedFrame[display.name] {
                return saved
            }
            // Fallback: use system appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? 0 : frameCount - 1
        }
    }

    /// Restore original wallpapers
    func restoreOriginals() async {
        let displays = DisplayService.shared.getAllDisplays()
        print("Restoring originals for \(displays.count) displays")

        for display in displays {
            print("  Display: \(display.name)")

            guard let sourcePath = AppConfig.shared.sourceWallpaper[display.name] else {
                print("    No stored source - skipping")
                continue
            }

            let sourceURL = URL(fileURLWithPath: sourcePath)
            print("    Source: \(sourceURL.lastPathComponent)")

            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                print("    Source file missing - clearing stored source")
                AppConfig.shared.sourceWallpaper.removeValue(forKey: display.name)
                AppConfig.shared.save()
                continue
            }

            do {
                try setWallpaper(sourceURL, for: display.screen)
                print("    ✓ Restored")
            } catch {
                print("    ✗ Failed: \(error)")
            }
        }
    }

    /// Force refresh - clear cache and reprocess
    func refresh() async {
        CacheManager.shared.clearGenerated()
        await processAllDisplays()
    }

    /// Apply wallpaper to all spaces using AppleScript
    func applyToAllSpaces() async {
        // First process all displays to ensure we have the processed files
        await processAllDisplays()

        // Build a mapping of display index to wallpaper path
        let displays = DisplayService.shared.getAllDisplays()
        var displayPaths: [(index: Int, path: String)] = []

        for (index, display) in displays.enumerated() {
            guard let sourcePath = AppConfig.shared.sourceWallpaper[display.name] else { continue }
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let frameIndex = getFrameIndex(for: display, source: sourceURL)
            let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
            let outputURL = CacheManager.shared.generatedURL(display: display, source: sourceURL, ext: ext, frameIndex: frameIndex)

            guard FileManager.default.fileExists(atPath: outputURL.path) else { continue }
            displayPaths.append((index: index + 1, path: outputURL.path))  // AppleScript uses 1-based index
        }

        guard !displayPaths.isEmpty else {
            print("No wallpapers to apply")
            return
        }

        // Build AppleScript that sets wallpaper for each display on all spaces
        var scriptLines = ["tell application \"System Events\""]
        scriptLines.append("    repeat with d in desktops")
        scriptLines.append("        set dispNum to display number of d")

        for (index, path) in displayPaths {
            // Escape quotes and backslashes in path for AppleScript
            let escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\")
                                  .replacingOccurrences(of: "\"", with: "\\\"")
            if index == displayPaths.first?.index {
                scriptLines.append("        if dispNum is \(index) then")
            } else {
                scriptLines.append("        else if dispNum is \(index) then")
            }
            scriptLines.append("            set picture of d to \"\(escapedPath)\"")
        }

        scriptLines.append("        end if")
        scriptLines.append("    end repeat")
        scriptLines.append("end tell")

        let script = scriptLines.joined(separator: "\n")
        print("Executing AppleScript:\n\(script)")

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
                // Common error: -1743 means no permission
                if let errorNumber = error[NSAppleScript.errorNumber] as? Int, errorNumber == -1743 {
                    print("⚠️ Automation permission denied. Grant access in System Settings > Privacy & Security > Automation")
                }
            } else {
                print("Applied wallpapers to all spaces (result: \(result))")
            }
        }
    }
}
