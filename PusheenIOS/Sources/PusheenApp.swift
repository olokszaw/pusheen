import SwiftUI
import Nuke

@main
struct PusheenApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var deviceEnvironment = DeviceEnvironmentStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        var artworkConfiguration = ImagePipeline.Configuration()
        let artworkCache = try? DataCache(name: "online.izanagi.pusheen.artwork")
        artworkCache?.sizeLimit = 64 * 1024 * 1024
        artworkConfiguration.dataCache = artworkCache
        ImagePipeline.shared = ImagePipeline(configuration: artworkConfiguration)
        // Start filling the memory/disk Fluent cache during the splash/auth
        // flow instead of waiting until the first emoji is already on screen.
        FluentEmojiCache.shared.warmCommonEmoji()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
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
