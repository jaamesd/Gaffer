# Design Considerations & Motivations

This document captures the design rationale and user considerations that shaped Gaffer.

## Core Philosophy

The app should be **unobtrusive** - it helps macOS look better with Tahoe's rounded corners, but shouldn't be something users have to think about constantly.

## Update Modes

### The Problem
Users don't want to manually refresh wallpapers every time something changes, but aggressive polling wastes battery.

### The Solution: Four Modes

1. **Off** - Do nothing. App is idle. Users who just want a one-time fix can use this.

2. **Thrifty** - Maximum power savings. For users who:
   - Rarely change spaces
   - Rarely change wallpapers
   - Prioritize battery over responsiveness
   - Base: 1 minute on AC, 5 minutes on battery, 10 minutes on low battery

3. **Snappy** - Aggressive polling for users who:
   - Switch spaces frequently
   - Change wallpapers often
   - Are usually plugged in
   - Base: 1 second on AC, 5s on battery

4. **Smarty** - Smart heuristics that adapt to:
   - Power source (AC vs battery)
   - Battery level (>50%, 20-50%, <20%)
   - Scales from 10s on AC to 2 minutes on low battery

## No Reset/Revert

### The Decision
When the app is disabled (Off mode or toggle off), it should NOT revert wallpapers to originals.

### Benefits
- Simpler UX - users understand "off means off"
- No surprise wallpaper changes
- Users can use System Settings to change wallpaper if needed
- Avoids edge cases where original is missing

## Source Image Protection

### The Problem
If the app uses a generated (corner-masked) image as a source, it could create progressively worse results (mask on mask on mask).

### The Solution
1. Never store a generated image path as a source
2. Detect if stored source is actually generated, clear it
3. Log warnings when this is detected

## All Spaces Behavior

### Auto-Disable on External Change
When the user changes wallpaper via System Settings (external change), the "All Spaces" toggle should automatically turn off.

### Benefits
- Respects user intent (they chose a new wallpaper)
- Prevents overwriting user's choice
- User must explicitly re-enable to apply everywhere

## Corner Style Options

### Four Options: None, Small, Medium, Large

| Style  | Radius | Use Case                      |
|--------|--------|-------------------------------|
| None   | 0pt    | No masking                    |
| Small  | 16pt   | Terminal, System Info windows |
| Medium | 21pt   | Compact toolbar windows       |
| Large  | 26pt   | Finder, Safari, most apps     |

The "None" option exists for:
- Users who want no corner rounding
- Debugging/testing
- Future flexibility

## UI Consistency

### Picker Widths
All segmented pickers should have the same width for visual consistency:
- Corner style: None / Small / Medium / Large
- Appearance: Dark / Light / Auto
- Update mode: Off / Thrifty / Snappy / Smarty

All pickers use `.frame(maxWidth: .infinity)` with consistent padding.

## Multi-Display & Multi-Space Complexity

### Observations
- Each display can have different wallpapers
- Each space can have different wallpapers per display
- System Settings changes only affect current space
- Our app needs to track and manage all combinations

### Implementation Notes
- Source wallpapers stored per display name
- Frame selections stored per display name
- AppleScript used to enumerate and set all desktops
- Space count tracked for monitoring optimization
