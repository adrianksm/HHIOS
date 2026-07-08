import SwiftUI

@main
struct HHiOSApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Theme.accent)
                .task {
                    // `-startDemo 1` launch arg enters offline demo (used for
                    // screenshots/evaluation); otherwise validate the session.
                    if UserDefaults.standard.bool(forKey: "startDemo") {
                        session.enterDemo()
                    } else {
                        await session.restore()
                    }
                }
        }
    }
}
