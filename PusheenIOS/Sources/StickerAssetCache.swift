import Foundation

/// Persistent raw-data cache for Telegram sticker previews and full assets.
///
/// The actor owns both the memory/disk lookup and the in-flight request table,
/// so two SwiftUI views asking for the same sticker can never start two network
/// downloads. Raw bytes are cached instead of rendered images so static,
/// animated and video stickers all use the same path.
actor StickerAssetCache {
    enum Variant: String, Sendable {
        case preview
        case file
    }

    struct Key: Hashable, Sendable {
        let serverNamespace: String
        let stickerID: Int
        let variant: Variant
    }

    static let shared = StickerAssetCache()

    private let directoryURL: URL
    private var memory: [Key: Data] = [:]
    private var memoryOrder: [Key] = []
    private var memoryCost = 0
    private var inFlight: [Key: Task<Data, Error>] = [:]
    private let memoryCostLimit = 48 * 1_024 * 1_024

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directoryURL = root.appendingPathComponent("PusheenStickerAssets-v1", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.directoryURL,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var cacheDirectory = self.directoryURL
        try? cacheDirectory.setResourceValues(values)
    }

    func data(
        for key: Key,
        loader: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        if let cached = memory[key] {
            markRecentlyUsed(key)
            return cached
        }

        let fileURL = diskURL(for: key)
        if let cached = try? Data(contentsOf: fileURL, options: .mappedIfSafe) {
            insertIntoMemory(cached, for: key)
            return cached
        }

        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task<Data, Error> { try await loader() }
        inFlight[key] = task
        do {
            let loaded = try await task.value
            inFlight[key] = nil
            insertIntoMemory(loaded, for: key)
            // A cache write must never turn a successful sticker download into
            // a failed chat render. `.atomic` prevents partially-written files.
            try? loaded.write(to: fileURL, options: .atomic)
            return loaded
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    private func diskURL(for key: Key) -> URL {
        let namespace = Self.stableHash(key.serverNamespace)
        return directoryURL.appendingPathComponent(
            "\(namespace)-\(key.stickerID)-\(key.variant.rawValue).asset",
            isDirectory: false
        )
    }

    private func insertIntoMemory(_ data: Data, for key: Key) {
        if let previous = memory.updateValue(data, forKey: key) {
            memoryCost -= previous.count
        }
        memoryCost += data.count
        markRecentlyUsed(key)
        while memoryCost > memoryCostLimit, let oldest = memoryOrder.first {
            memoryOrder.removeFirst()
            if let removed = memory.removeValue(forKey: oldest) {
                memoryCost -= removed.count
            }
        }
    }

    private func markRecentlyUsed(_ key: Key) {
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
    }

    /// FNV-1a is deterministic across launches, unlike Swift's randomized
    /// `Hasher`, and keeps backend URLs out of filenames.
    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
