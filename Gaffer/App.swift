import SwiftUI

@main
struct GafferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "rectangle.topthird.inset.filled")
        }
        .menuBarExtraStyle(.window)
    }
}
