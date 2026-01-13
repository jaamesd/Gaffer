import Foundation
import CryptoKit

class CacheManager {
    static let shared = CacheManager()

    let basePath: URL

    /// Hash of current binary - changes when app is rebuilt
    let buildHash: String

    private init() {
        // Use Application Support for cache storage
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        basePath = appSupport.appendingPathComponent("Gaffer")

        // Compute hash of the binary to detect rebuilds
        buildHash = Self.computeBuildHash()

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: basePath, withIntermediateDirectories: true)
    }

    private static func computeBuildHash() -> String {
        // Use binary modification date as a simple "hash"
        guard let execURL = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return "unknown"
        }
        // Include corner radius and extension factor so code changes invalidate cache
        let params = "\(modDate.timeIntervalSince1970)_\(ImageProcessor.shared.baseCornerRadius)_ext1.29"
        return String(params.hashValue)
    }

    func generatedURL(display: DisplayInfo, source: URL, ext: String, frameIndex: Int? = nil) -> URL {
        let corner = AppConfig.shared.cornerStyle.rawValue
        let menubar = Int(display.menuBarHeight)
        // Use provided frameIndex (actual frame to render) or default to 0
        let frame = frameIndex ?? 0
        // Include appearance mode so changing mode invalidates cache
        let mode = AppConfig.shared.appearanceMode.rawValue
        // Include source path hash so changing wallpaper invalidates cache
        let sourceHash = abs(source.path.hashValue)
        // Include display resolution to detect aspect ratio mismatches (squished wallpapers)
        let resW = Int(display.physicalRes.width)
        let resH = Int(display.physicalRes.height)
        // Cache key includes: display, corner, menubar, frame, mode, resolution, and source hash
        let filename = "\(display.name.replacingOccurrences(of: " ", with: "_"))_c\(corner)_m\(menubar)_f\(frame)_a\(mode)_\(resW)x\(resH)_\(sourceHash).\(ext)"
        return basePath.appendingPathComponent(filename)
    }

    func clearGenerated() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil) else { return }

        for file in files {
            let ext = file.pathExtension.lowercased()
            if ["heic", "png", "jpg", "jpeg", "tiff"].contains(ext) {
                try? fm.removeItem(at: file)
            }
        }
    }

    /// Check if cache needs regeneration (build changed)
    func needsRegeneration() -> Bool {
        let storedHash = AppConfig.shared.lastBuildHash
        return storedHash != buildHash
    }

    func markCacheValid() {
        AppConfig.shared.lastBuildHash = buildHash
        AppConfig.shared.save()
    }
}
