import Foundation

enum TestFailure: Error { case expectedFailure }

actor LoaderCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@main
struct StickerAssetCacheTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pusheen-sticker-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let key = StickerAssetCache.Key(
            serverNamespace: "https://example.test",
            stickerID: 42,
            variant: .preview
        )
        let expected = Data("cached-sticker".utf8)
        let counter = LoaderCounter()
        let cache = StickerAssetCache(directoryURL: root)

        try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<24 {
                group.addTask {
                    try await cache.data(for: key) {
                        await counter.increment()
                        try await Task.sleep(for: .milliseconds(80))
                        return expected
                    }
                }
            }
            for try await value in group {
                precondition(value == expected, "Every waiter must receive the same bytes")
            }
        }
        let concurrentLoadCount = await counter.value
        precondition(concurrentLoadCount == 1, "Concurrent requests must share one loader")

        // A new actor simulates an app relaunch: memory is empty but disk stays.
        let relaunched = StickerAssetCache(directoryURL: root)
        let persisted = try await relaunched.data(for: key) {
            fatalError("Persistent cache must avoid a second network request")
        }
        precondition(persisted == expected, "Disk cache must survive actor/app recreation")

        let fullKey = StickerAssetCache.Key(
            serverNamespace: key.serverNamespace,
            stickerID: key.stickerID,
            variant: .file
        )
        let full = try await relaunched.data(for: fullKey) { Data("full-file".utf8) }
        precondition(full != persisted, "Preview and full sticker files need separate keys")

        let retryKey = StickerAssetCache.Key(
            serverNamespace: key.serverNamespace,
            stickerID: 99,
            variant: .preview
        )
        do {
            _ = try await relaunched.data(for: retryKey) { throw TestFailure.expectedFailure }
            preconditionFailure("The first loader must fail")
        } catch TestFailure.expectedFailure {}
        let recovered = try await relaunched.data(for: retryKey) { Data("retry-ok".utf8) }
        precondition(recovered == Data("retry-ok".utf8), "A failed flight must not poison later retries")

        print("Sticker asset cache tests passed")
    }
}
