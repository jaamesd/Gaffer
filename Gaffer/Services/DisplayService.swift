import AppKit

class DisplayService {
    static let shared = DisplayService()

    private init() {}

    func getAllDisplays() -> [DisplayInfo] {
        NSScreen.screens.map { DisplayInfo(screen: $0) }
    }

    func getMainDisplay() -> DisplayInfo? {
        guard let main = NSScreen.main else { return nil }
        return DisplayInfo(screen: main)
    }

    func getDisplay(for screen: NSScreen) -> DisplayInfo {
        DisplayInfo(screen: screen)
    }
}
