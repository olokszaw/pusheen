import SwiftUI

@main
struct PusheenApp: App {
    @StateObject private var session = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Start filling the memory/disk Fluent cache during the splash/auth
        // flow instead of waiting until the first emoji is already on screen.
        FluentEmojiCache.shared.warmCommonEmoji()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(.purple)
                .onChange(of: scenePhase) { _, phase in
                    session.setAppActive(phase == .active)
                }
        }
    }
}
