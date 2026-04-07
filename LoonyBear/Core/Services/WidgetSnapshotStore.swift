import Foundation

struct WidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.valr4k.LoonyBear"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        let url = snapshotURL()
        let data = try encoder.encode(snapshot)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func load() throws -> WidgetSnapshot {
        let data = try Data(contentsOf: snapshotURL())
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }

    func snapshotURL() -> URL {
        if let sharedContainer = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            return sharedContainer
                .appendingPathComponent("WidgetData", isDirectory: true)
                .appendingPathComponent("widget-snapshot.json")
        }

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("LoonyBear", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }
}
