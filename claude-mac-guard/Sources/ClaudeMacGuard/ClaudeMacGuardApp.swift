import SwiftUI

@main
struct ClaudeMacGuardApp: App {
    var body: some Scene {
        WindowGroup {
            MonitorView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 780, height: 680)
    }
}
