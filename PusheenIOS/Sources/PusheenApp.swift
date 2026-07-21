import SwiftUI

@main
struct PusheenApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(.purple)
        }
    }
}
