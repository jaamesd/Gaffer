import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import ImageIO

struct MenuBarView: View {
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // 1. Wallpaper preview (fixed width, variable height from aspect ratio)
            Button(action: { viewModel.selectWallpaperFile() }) {
                WallpaperPreview(
                    image: viewModel.previewImage,
                    aspectRatio: viewModel.previewAspect,
                    cornerRadius: viewModel.cornerStyle.cornerRadius
                )
            }
            .buttonStyle(.plain)
            .help("Click to choose wallpaper")
            .padding(12)

            // 2. Corner size picker
            Picker("", selection: $viewModel.cornerStyle) {
                ForEach(WindowCornerStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .help("Window corner size")

            // 3. Appearance mode picker (for dynamic wallpapers)
            Picker("", selection: $viewModel.appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .help("Appearance mode for dynamic wallpapers")

            // 4. Dynamic wallpaper frame slider (only for multi-frame HEIC)
            if viewModel.dynamicFrameCount > 1 {
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.selectedFrameIndex) },
                            set: { viewModel.selectedFrameIndex = Int($0) }
                        ),
                        in: 0...Double(viewModel.dynamicFrameCount - 1),
                        step: 1
                    )
                    .disabled(viewModel.appearanceMode != .auto)
                    Image(systemName: "sun.max")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .opacity(viewModel.appearanceMode == .auto ? 1.0 : 0.5)
                .help(viewModel.appearanceMode == .auto
                    ? "Dynamic wallpaper: \(viewModel.selectedFrameIndex + 1) of \(viewModel.dynamicFrameCount)"
                    : "Frame locked by appearance mode")
            }

            Divider()

            // 5. Update mode picker (Off / Eco / Smart / Snap)
            Picker("", selection: $viewModel.updateMode) {
                ForEach(UpdateMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .padding(.top, 8)
            .help("Thrifty: saves power, Smarty: balanced, Snappy: responsive")

            Divider()

            // All Spaces toggle
            SettingsToggle(icon: "rectangle.stack", label: "All Spaces", isOn: $viewModel.allSpacesEnabled)
            .help("Automatically apply wallpaper to all spaces")

            Divider()

            // Login Item + Quit row
            HStack(spacing: 0) {
                // Login Item toggle (compact)
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .frame(width: 14)
                        .foregroundColor(.secondary)
                    Text("Login")
                        .font(.system(size: 12))
                    Toggle("", isOn: $viewModel.launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                .padding(.leading, 12)

                Spacer()

                Divider()
                    .frame(height: 20)

                // Quit button
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .frame(width: 14)
                            .foregroundColor(.secondary)
                        Text("Quit")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
        .frame(width: 280)
        .padding(.bottom, 8)
        .onAppear {
            viewModel.updatePreview()
        }
    }
}

struct SettingsButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundColor(.secondary)
                Text(label)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsToggle: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundColor(.secondary)
            Text(label)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct WallpaperPreview: View {
    let image: NSImage?
    let aspectRatio: CGFloat
    let cornerRadius: CGFloat

    // Preview width is ~256 (280 container - 24 padding)
    private let previewWidth: CGFloat = 256

    /// Height based on aspect ratio
    private var previewHeight: CGFloat {
        previewWidth / aspectRatio
    }

    /// Scale corner radius for preview visibility (exaggerated for clarity)
    private var scaledRadius: CGFloat {
        if cornerRadius == 0 {
            return 3  // Minimal rounding for "None"
        }
        // Exaggerate corners: ~3x larger in preview
        let scale = previewWidth / 250
        return max(8, cornerRadius * scale)
    }

    var body: some View {
        ZStack {
            // Black background to show where corners will be masked
            RoundedRectangle(cornerRadius: scaledRadius)
                .fill(Color.black)

            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: previewWidth, height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: scaledRadius))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                    Text("Click to select")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            // Click hint overlay
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 10))
                    Text("Change")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 4)
            }
        }
        .frame(width: previewWidth, height: min(previewHeight, 200))  // Cap height for very tall images
        .clipShape(RoundedRectangle(cornerRadius: scaledRadius))
    }
}

class MenuBarViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var cornerStyle: WindowCornerStyle = .toolbar {
        didSet {
            guard cornerStyle != oldValue else { return }
            AppConfig.shared.cornerStyle = cornerStyle
            AppConfig.shared.save()
            // Auto-regenerate when corner style changes (if not in Off mode)
            if AppConfig.shared.updateMode != .off {
                refresh()
            }
        }
    }
    @Published var appearanceMode: AppearanceMode = .auto {
        didSet {
            guard appearanceMode != oldValue else { return }
            AppConfig.shared.appearanceMode = appearanceMode
            AppConfig.shared.save()
            // Auto-regenerate when appearance mode changes (if not in Off mode)
            if AppConfig.shared.updateMode != .off && dynamicFrameCount > 1 {
                refresh()
            }
        }
    }
    @Published var launchAtLogin: Bool = false {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }

    @Published var allSpacesEnabled: Bool = false {
        didSet {
            guard allSpacesEnabled != oldValue else { return }
            AppConfig.shared.applyToAllSpaces = allSpacesEnabled
            AppConfig.shared.save()
            if allSpacesEnabled {
                // Apply to all spaces immediately when enabled
                applyToAllSpacesNow()
            }
        }
    }

    @Published var updateMode: UpdateMode = .smarty {
        didSet {
            guard updateMode != oldValue else { return }
            AppConfig.shared.updateMode = updateMode
            AppConfig.shared.save()
            MonitorService.shared.restartTimer()
        }
    }
    @Published var currentSourceURL: URL?
    @Published var previewImage: NSImage?
    @Published var previewAspect: CGFloat = 16.0 / 9.0
    @Published var isUsingProcessedWallpaper = false
    @Published var dynamicFrameCount: Int = 0
    @Published var selectedFrameIndex: Int = 0 {
        didSet {
            guard selectedFrameIndex != oldValue, dynamicFrameCount > 1 else { return }
            if let screen = NSScreen.main {
                AppConfig.shared.selectedFrame[screen.localizedName] = selectedFrameIndex
                AppConfig.shared.save()
            }
            // Auto-regenerate when frame changes (if not in Off mode)
            if AppConfig.shared.updateMode != .off {
                refresh()
            }
        }
    }

    // Cache to avoid re-reading HEIC files
    private var cachedFrameCount: [String: Int] = [:]
    private var lastSourcePath: String?

    init() {
        cornerStyle = AppConfig.shared.cornerStyle
        appearanceMode = AppConfig.shared.appearanceMode
        updateMode = AppConfig.shared.updateMode
        allSpacesEnabled = AppConfig.shared.applyToAllSpaces
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        updatePreview()
    }

    func updatePreview() {
        guard let screen = NSScreen.main else {
            currentSourceURL = nil
            isUsingProcessedWallpaper = false
            dynamicFrameCount = 0
            return
        }

        let displayName = screen.localizedName
        let currentWallpaper = NSWorkspace.shared.desktopImageURL(for: screen)

        // Check if current wallpaper is one of our processed versions
        isUsingProcessedWallpaper = currentWallpaper?.path.hasPrefix(CacheManager.shared.basePath.path) ?? false

        // Determine source URL
        let sourceURL: URL?
        if isUsingProcessedWallpaper {
            // Using our processed version - show stored source
            if let sourcePath = AppConfig.shared.sourceWallpaper[displayName] {
                sourceURL = URL(fileURLWithPath: sourcePath)
            } else {
                sourceURL = nil
            }
        } else {
            // Not using processed - show actual current wallpaper
            // Also update stored source if it changed externally
            sourceURL = currentWallpaper
            if let current = currentWallpaper,
               AppConfig.shared.sourceWallpaper[displayName] != current.path {
                AppConfig.shared.sourceWallpaper[displayName] = current.path
                AppConfig.shared.save()
            }
        }

        let sourcePath = sourceURL?.path
        let sourceChanged = sourcePath != lastSourcePath

        if sourceChanged {
            lastSourcePath = sourcePath
            currentSourceURL = sourceURL
            // Clear frame count cache when source changes
            cachedFrameCount.removeAll()

            // Load preview image asynchronously
            if let url = sourceURL {
                Task.detached(priority: .userInitiated) { [weak self] in
                    // Load and downsample for preview (max 512px wide)
                    let image = Self.loadPreviewImage(from: url, maxWidth: 512)
                    let aspect = image.map { $0.size.width / max(1, $0.size.height) } ?? 16.0/9.0
                    await MainActor.run {
                        self?.previewImage = image
                        self?.previewAspect = aspect
                    }
                }
            } else {
                previewImage = nil
                previewAspect = 16.0 / 9.0
            }
        }

        // Check for dynamic wallpaper (multi-frame HEIC) - use cache to avoid disk I/O
        if let url = sourceURL, url.pathExtension.lowercased() == "heic" {
            // Use cached frame count if available
            if let cached = cachedFrameCount[url.path] {
                dynamicFrameCount = cached
            } else {
                let count = getHEICFrameCount(url)
                cachedFrameCount[url.path] = count
                dynamicFrameCount = count
            }
            // Restore saved frame index only on source change
            if sourceChanged {
                let savedIndex = AppConfig.shared.selectedFrame[displayName] ?? 0
                if savedIndex != selectedFrameIndex && savedIndex < dynamicFrameCount {
                    selectedFrameIndex = savedIndex
                }
            }
        } else {
            dynamicFrameCount = 0
        }
    }

    private func getHEICFrameCount(_ url: URL) -> Int {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return 0
        }
        return CGImageSourceGetCount(imageSource)
    }

    /// Load a downsampled preview image for efficient display
    private static func loadPreviewImage(from url: URL, maxWidth: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxWidth,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Fallback to regular loading
            return NSImage(contentsOf: url)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func selectWallpaperFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .heic, .png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select a wallpaper image"
        panel.prompt = "Choose"

        // Start in Pictures folder
        if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            panel.directoryURL = pictures
        }

        if panel.runModal() == .OK, let url = panel.url {
            // Store as source for main display
            if let screen = NSScreen.main {
                AppConfig.shared.sourceWallpaper[screen.localizedName] = url.path
                AppConfig.shared.save()
            }
            currentSourceURL = url
            lastSourcePath = url.path

            // Load preview immediately
            Task.detached(priority: .userInitiated) { [weak self] in
                let image = Self.loadPreviewImage(from: url, maxWidth: 512)
                let aspect = image.map { $0.size.width / max(1, $0.size.height) } ?? 16.0/9.0
                await MainActor.run {
                    self?.previewImage = image
                    self?.previewAspect = aspect
                }
            }

            applyWallpaper()
        }
    }

    func applyWallpaper() {
        isProcessing = true

        // If not already using processed wallpaper, update source to current wallpaper
        if !isUsingProcessedWallpaper {
            if let screen = NSScreen.main,
               let currentWallpaper = NSWorkspace.shared.desktopImageURL(for: screen) {
                AppConfig.shared.sourceWallpaper[screen.localizedName] = currentWallpaper.path
                AppConfig.shared.save()
                currentSourceURL = currentWallpaper
                lastSourcePath = currentWallpaper.path
            }
        }

        Task {
            await WallpaperService.shared.processAllDisplays()
            await MainActor.run {
                isProcessing = false
                updatePreview()
            }
        }
    }

    func refresh() {
        isProcessing = true
        Task {
            await WallpaperService.shared.refresh()
            await MainActor.run {
                isProcessing = false
                updatePreview()
            }
        }
    }

    func restoreOriginals() {
        isProcessing = true
        Task {
            await WallpaperService.shared.restoreOriginals()
            await MainActor.run {
                isProcessing = false
                updatePreview()
            }
        }
    }

    func applyToAllSpacesNow() {
        isProcessing = true
        Task {
            await WallpaperService.shared.applyToAllSpaces()
            await MainActor.run {
                isProcessing = false
                updatePreview()
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to set launch at login: \(error)")
            }
        }
    }
}
