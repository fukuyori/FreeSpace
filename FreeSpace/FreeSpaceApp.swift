import SwiftUI

@main
struct FreeSpaceApp: App {
    @StateObject private var monitor = DiskMonitor(path: "/")

    var body: some Scene {
        MenuBarExtra(monitor.menuTitle) {
            ContentView(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
