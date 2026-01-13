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
- Menubar height (varies by display)
- Frame index (for dynamic HEIC wallpapers)
- Appearance mode (Dark/Light/Auto)
- Source file hash (to detect when source changes)

Example filename: `Built-in_Display_c2_m24_f0_a2_1234567890.heic`

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

### Power Management

The app uses IOKit to detect power state and adjust polling behavior:
- `IOPSCopyPowerSourcesInfo()` - get power source snapshot
- `IOPSCopyPowerSourcesList()` - enumerate power sources
- `IOPSGetPowerSourceDescription()` - check AC vs battery, charge level

### Polling Modes

#### Normal Mode
| Mode    | AC Power | Battery >50% | Battery 20-50% | Battery <20% |
|---------|----------|--------------|----------------|--------------|
| Snappy  | 1s       | 5s           | 5s             | 15s          |
| Smarty  | 10s      | 30s          | 60s            | 120s         |
| Thrifty | 60s      | 300s         | 300s           | 600s         |
| Off     | --       | --           | --             | --           |

#### Burst Mode (on space/display change)
Triggers immediately after space change or display configuration change.

| Mode    | AC Interval   | AC Duration | Battery Interval | Battery Duration |
|---------|---------------|-------------|------------------|------------------|
| Snappy  | 25ms (40Hz)   | 8s          | 50ms (20Hz)      | 5s               |
| Smarty  | 50ms (20Hz)   | 5s          | 100ms (10Hz)     | 3s               |
| Thrifty | 200ms (5Hz)   | 3s          | 500ms (2Hz)      | 2s               |

#### Sustained Mode (after burst)
Continues after burst mode ends, extended on each space change.

| Mode    | AC Interval   | AC Duration | Battery >50%     | Battery <50%     |
|---------|---------------|-------------|------------------|------------------|
| Snappy  | 100ms (10Hz)  | 180s        | 250ms (4Hz) / 90s| 250ms / 90s      |
| Smarty  | 250ms (4Hz)   | 120s        | 500ms (2Hz) / 60s| 1s (1Hz) / 30s   |
| Thrifty | 500ms (2Hz)   | 60s         | 2s (0.5Hz) / 30s | 2s / 30s         |

#### Mode Transitions
```
Space/Display Change
    └──> Burst Mode (high frequency, short duration)
            └──> Sustained Mode (moderate frequency, extended on changes)
                    └──> Normal Mode (polling based on UpdateMode)

Space change during Sustained Mode:
    └──> Extends sustained timer
    └──> Immediately enters Burst Mode
```

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
