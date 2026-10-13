import SwiftUI
import Kingfisher

@main
struct PusheenApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var deviceEnvironment = DeviceEnvironmentStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ImageCache.default.memoryStorage.config.totalCostLimit = 64 * 1024 * 1024
        ImageCache.default.diskStorage.config.sizeLimit = 128 * 1024 * 1024
        // Start filling the memory/disk Fluent cache during the splash/auth
        // flow instead of waiting until the first emoji is already on screen.
        FluentEmojiCache.shared.warmCommonEmoji()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .transformEnvironment(\.dynamicTypeSize) { value in
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-fixtures-large-text") { value = .accessibility3 }
                    #endif
                }
                .environmentObject(session)
                .environmentObject(deviceEnvironment)
                .tint(CinemaPalette.accent)
                .onChange(of: scenePhase) { _, phase in
                    session.setAppActive(phase == .active)
                    if phase == .active { deviceEnvironment.refresh() }
                }
        }
    }
}
