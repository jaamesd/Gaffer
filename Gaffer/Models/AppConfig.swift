import Foundation

/// Appearance mode for dynamic wallpapers
enum AppearanceMode: Int, CaseIterable, Codable {
    case dark = 0
    case light = 1
    case auto = 2

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .auto: return "Auto"
        }
    }
}

/// Update mode for monitoring and refreshing wallpapers
enum UpdateMode: Int, CaseIterable, Codable {
    case off = 0      // Do nothing - app is idle
    case thrifty = 1  // Power-conscious, minimal polling
    case snappy = 2   // Aggressive polling, very responsive
    case smarty = 3   // Balanced - uses heuristics for optimal balance

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .thrifty: return "Thrifty"
        case .snappy: return "Snappy"
        case .smarty: return "Smarty"
        }
    }
}

/// macOS Tahoe window corner styles with different radii
enum WindowCornerStyle: Int, CaseIterable, Codable {
    case none = 0           // No corner masking
    case titlebar = 1       // Smaller corners (Terminal, System Info)
    case compactToolbar = 2 // Medium corners
    case toolbar = 3        // Larger corners (Finder, Safari)

    var displayName: String {
        switch self {
        case .none: return "None"
        case .titlebar: return "Small"
        case .compactToolbar: return "Medium"
        case .toolbar: return "Large"
        }
    }

    /// Corner radius in points (from Apple HIG for Tahoe)
    var cornerRadius: CGFloat {
        switch self {
        case .none: return 0            // No rounding
        case .titlebar: return 16       // TitleBar windows (Terminal, System Info)
        case .compactToolbar: return 21 // Compact toolbar estimate
        case .toolbar: return 26        // Toolbar windows (Finder, Safari)
        }
    }
}

class AppConfig: ObservableObject {
    static let shared = AppConfig()

    @Published var cornerStyle: WindowCornerStyle = .toolbar {
        didSet {
            ImageProcessor.shared.baseCornerRadius = cornerStyle.cornerRadius
        }
    }

    // Source wallpaper path per display name
    @Published var sourceWallpaper: [String: String] = [:]

    // Selected frame index for dynamic wallpapers (per display)
    @Published var selectedFrame: [String: Int] = [:]

    // Update mode for monitoring
    @Published var updateMode: UpdateMode = .smarty

    // Appearance mode for dynamic wallpapers
    @Published var appearanceMode: AppearanceMode = .auto

    // Apply wallpaper to all spaces automatically
    @Published var applyToAllSpaces: Bool = false

    // Track build hash to detect when regeneration needed
    var lastBuildHash: String = ""

    // Space tracking: last update time per display
    var lastSpaceUpdate: [String: Date] = [:]
    var spaceCount: Int = 0

    private let configURL: URL

    private init() {
        // Use Application Support for config storage
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Gaffer")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        configURL = appDir.appendingPathComponent("config.json")
        load()
        ImageProcessor.shared.baseCornerRadius = cornerStyle.cornerRadius
    }

    func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }

        do {
            let data = try Data(contentsOf: configURL)
            let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)
            cornerStyle = WindowCornerStyle(rawValue: decoded.cornerStyle) ?? .toolbar
            sourceWallpaper = decoded.sourceWallpaper
            selectedFrame = decoded.selectedFrame ?? [:]
            updateMode = UpdateMode(rawValue: decoded.updateMode ?? 3) ?? .smarty
            appearanceMode = AppearanceMode(rawValue: decoded.appearanceMode ?? 2) ?? .auto
            applyToAllSpaces = decoded.applyToAllSpaces ?? false
            lastBuildHash = decoded.lastBuildHash ?? ""
            spaceCount = decoded.spaceCount ?? 0
        } catch {
            print("Failed to load config: \(error)")
        }
    }

    func save() {
        let config = ConfigFile(
            cornerStyle: cornerStyle.rawValue,
            sourceWallpaper: sourceWallpaper,
            selectedFrame: selectedFrame,
            updateMode: updateMode.rawValue,
            appearanceMode: appearanceMode.rawValue,
            applyToAllSpaces: applyToAllSpaces,
            lastBuildHash: lastBuildHash,
            spaceCount: spaceCount
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configURL)
        } catch {
            print("Failed to save config: \(error)")
        }
    }
}

private struct ConfigFile: Codable {
    let cornerStyle: Int
    let sourceWallpaper: [String: String]
    let selectedFrame: [String: Int]?
    let updateMode: Int?
    let appearanceMode: Int?
    let applyToAllSpaces: Bool?
    let lastBuildHash: String?
    let spaceCount: Int?
}
