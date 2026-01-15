import AppKit

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let screen: NSScreen
    let name: String
    let physicalRes: CGSize
    let virtualRes: CGSize
    let scaleFactor: CGFloat
    let hasNotch: Bool
    let menuBarHeight: CGFloat
    let safeAreaInsets: NSEdgeInsets

    init(screen: NSScreen) {
        self.screen = screen
        self.id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        self.name = screen.localizedName
        self.virtualRes = screen.frame.size
        self.scaleFactor = screen.backingScaleFactor
        self.physicalRes = CGSize(
            width: virtualRes.width * scaleFactor,
            height: virtualRes.height * scaleFactor
        )

        if #available(macOS 12.0, *) {
            self.safeAreaInsets = screen.safeAreaInsets
            self.hasNotch = safeAreaInsets.top > 0
        } else {
            self.safeAreaInsets = NSEdgeInsets()
            self.hasNotch = false
        }

        // Calculate menu bar height accounting for notch
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        let rawMenuBarHeight = fullFrame.maxY - visibleFrame.maxY

        // Convert to physical pixels and round to nearest pixel
        if hasNotch {
            self.menuBarHeight = round(max(rawMenuBarHeight, safeAreaInsets.top) * scaleFactor)
        } else if rawMenuBarHeight > 0 {
            self.menuBarHeight = round(rawMenuBarHeight * scaleFactor)
        } else {
            self.menuBarHeight = round(24 * scaleFactor)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        lhs.id == rhs.id
    }
}
