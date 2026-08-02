import SwiftUI

@main
struct BaselineApp: App {
    var body: some Scene {
        WindowGroup {
            AppShell()
                .preferredColorScheme(.dark)
        }
    }
}
