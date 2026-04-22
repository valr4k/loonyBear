import Foundation

struct WidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.valr4k.LoonyBear"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseDirectoryURL: URL?

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        let url = snapshotURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinateWrite(at: url) { coordinatedURL in
            if
                let existingSnapshot = try loadSnapshotIfPresent(at: coordinatedURL),
                snapshot.revision <= existingSnapshot.revision
            {
                return
            }

            let data = try encoder.encode(snapshot)
            try data.write(to: coordinatedURL, options: .atomic)
        }
    }

    func load() throws -> WidgetSnapshot {
        try coordinateRead(at: snapshotURL()) { coordinatedURL in
            let data = try Data(contentsOf: coordinatedURL)
            return try decoder.decode(WidgetSnapshot.self, from: data)
        }
    }

    func snapshotURL() -> URL {
        if let baseDirectoryURL {
            return baseDirectoryURL
                .appendingPathComponent("WidgetData", isDirectory: true)
                .appendingPathComponent("widget-snapshot.json")
        }

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

    private func loadSnapshotIfPresent(at url: URL) throws -> WidgetSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }

    private func coordinateRead<T>(at url: URL, accessor: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?

        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { coordinatedURL in
            do {
                result = .success(try accessor(coordinatedURL))
            } catch {
                result = .failure(error)
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw CocoaError(.fileReadUnknown)
        }
    }

    private func coordinateWrite(at url: URL, accessor: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var operationError: Error?

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try accessor(coordinatedURL)
            } catch {
                operationError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        if let operationError {
            throw operationError
        }
    }
}
