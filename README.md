# Gaffer

A macOS menubar app that applies black corner masks to wallpapers, matching the rounded window corners in macOS Tahoe.

## What it does

macOS Tahoe introduced rounded window corners, but the desktop wallpaper still has sharp corners. Gaffer processes your wallpaper to add black fills in the corners, creating a seamless look where the wallpaper appears to have the same rounded corners as your windows.

## Features

- **Corner size options**: None, Small, Medium, Large (matching different window styles)
- **Dynamic wallpaper support**: Works with multi-frame HEIC wallpapers (like Solar Gradients)
- **Appearance modes**: Dark, Light, or Auto (follows system appearance)
- **Multi-display support**: Handles each display independently with correct aspect ratios
- **Multi-space support**: Apply to all virtual desktops with one click
- **Event-driven updates**: Responds instantly to space/display changes without constant polling
- **Power-aware**: Adjusts burst mode frequency based on AC/battery status
- **Start on login**: Optional login item support

## Installation

1. Download `Gaffer.app` from Releases
2. Move to `/Applications`
3. Right-click and select "Open" (required for first launch)
4. Click "Open" in the dialog

After the first launch, you can open normally.

## Building from source

```bash
./build-app.sh
```

This creates `Gaffer.app` in the project directory.

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

## How it works

Gaffer monitors your wallpaper and processes it to add black corners. The processed wallpapers are cached in `~/Library/Application Support/Gaffer/` for fast switching between spaces.

## License

MIT
