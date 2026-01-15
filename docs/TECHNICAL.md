# Gaffer - Technical Documentation

## Overview

A macOS menubar app that applies black corner masks to wallpapers, matching the rounded window corners in macOS Tahoe. The app processes wallpapers to add black fills in the corners, ensuring they look correct with the system's rounded window aesthetic.

## Architecture

### Core Components

1. **MenuBarView** - SwiftUI view for the menubar popover
2. **AppConfig** - Persistent configuration storage
3. **WallpaperService** - Core wallpaper processing logic
4. **MonitorService** - Background monitoring and polling
5. **ImageProcessor** - Image manipulation for corner masking
6. **CacheManager** - Manages generated wallpaper cache
7. **DisplayService** - Multi-monitor display detection

### Data Flow

```
User selects wallpaper
    -> Store as source in AppConfig
    -> Generate cache key (display + corner + frame + appearance + source hash)
    -> Check cache for existing processed version
    -> If not cached: process image with ImageProcessor
    -> Apply processed wallpaper via NSWorkspace
    -> Optionally apply to all spaces via AppleScript
```

## Key Technical Decisions

### Cache Invalidation

Cache keys include multiple factors to ensure correct invalidation:
- Display name (for multi-monitor setups)
- Corner style (None/Small/Medium/Large)
- Menubar height (varies by display, accounts for notch)
- Frame index (for dynamic HEIC wallpapers)
- Appearance mode (Dark/Light/Auto)
- Display resolution (prevents aspect ratio mismatches)
- Source file hash (to detect when source changes)

Example filename: `Built-in_Display_c2_m65_f0_a0_3456x2234_1234567890.heic`

### Dynamic Wallpaper Support

macOS dynamic wallpapers (like Solar Gradients) are multi-frame HEIC files:
- Frame 0: typically the darkest (night) version
- Frame N-1: typically the lightest (day) version
- Use `CGImageSourceCreateWithURL` and `CGImageSourceGetCount` to detect frame count
- Extract specific frames with `CGImageSourceCreateImageAtIndex`

### Multi-Space Support

AppleScript is used to apply wallpapers across all virtual desktops:

```applescript
tell application "System Events"
    repeat with d in desktops
        set dispNum to display number of d
        if dispNum is 1 then
            set picture of d to "/path/to/wallpaper.heic"
        end if
    end repeat
end tell
```

### Event-Driven Architecture

The app uses an event-driven model instead of constant polling:

#### Event Sources
1. **File Monitor** - Watches `~/Library/Preferences/com.apple.wallpaper.plist` (modern macOS) or `~/Library/Application Support/Dock/desktoppicture.db` (legacy) for external wallpaper changes
2. **Space Change** - `NSWorkspace.activeSpaceDidChangeNotification` via workspace notification center
3. **Display Change** - `NSApplication.didChangeScreenParametersNotification` for monitor connect/disconnect
4. **Appearance Change** - `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` for dark/light mode

#### Burst Mode
Triggered by events to catch macOS settling:
- Immediate check, then retries at 50ms, 150ms (space change) or 100ms, 500ms, 1.5s (file change)
- Short burst of rapid polling (2-5 seconds) to ensure wallpaper is detected

| Mode    | AC Interval   | AC Duration | Battery Interval | Battery Duration |
|---------|---------------|-------------|------------------|------------------|
| Snappy  | 25ms (40Hz)   | 5s          | 50ms (20Hz)      | 3s               |
| Smarty  | 50ms (20Hz)   | 3s          | 100ms (10Hz)     | 2s               |
| Thrifty | 200ms (5Hz)   | 2s          | 500ms (2Hz)      | 1s               |

#### No Background Polling
Between events, the app is completely idle - no timers, no CPU usage. This maximizes battery life.

### Power Management

The app uses IOKit to detect power state and adjust burst mode parameters:
- `IOPSCopyPowerSourcesInfo()` - get power source snapshot
- `IOPSCopyPowerSourcesList()` - enumerate power sources
- `IOPSGetPowerSourceDescription()` - check AC vs battery, charge level

### Image Scaling (Aspect Fill)

When the source wallpaper has a different aspect ratio than the display, the app uses aspect-fill scaling:
- Scale uniformly to fill the entire display (preserves aspect ratio)
- Center the image and crop overflow
- Prevents stretching/squashing of wallpaper content

```swift
let scale = max(scaleX, scaleY)  // Fill, not fit
let drawRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)
```

### Dimension Validation

Before applying a cached wallpaper, the app verifies dimensions match the current display:
- Prevents stretched wallpapers when moving spaces between displays
- Automatically regenerates if resolution mismatch detected

## Configuration

Config stored at: `~/Library/Application Support/Gaffer/config.json`

```json
{
  "cornerStyle": 2,
  "sourceWallpaper": {
    "Built-in Display": "/path/to/source.heic"
  },
  "selectedFrame": {},
  "updateMode": 3,
  "appearanceMode": 2,
  "applyToAllSpaces": false,
  "lastBuildHash": "...",
  "spaceCount": 4
}
```

## Cache Location

Generated wallpapers stored at: `~/Library/Application Support/Gaffer/`

## Building

```bash
./build-app.sh
```

Output: `Gaffer.app`

## Dependencies

- Swift 5.9+
- macOS 13.0+
- Frameworks: AppKit, SwiftUI, ImageIO, IOKit
