import SwiftUI

@main
struct BaselineApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView(state: SampleDashboard.fixture)
                .preferredColorScheme(.dark)
        }
    }
}
