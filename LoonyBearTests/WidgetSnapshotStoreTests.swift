import Foundation
import Testing

@testable import LoonyBear

struct WidgetSnapshotStoreTests {
    @Test
    func saveIgnoresOlderSnapshotWhenNewerOneIsAlreadyStored() throws {
        let baseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = WidgetSnapshotStore(baseDirectoryURL: baseDirectoryURL)

        let newerSnapshot = WidgetSnapshot(
            revision: 10,
            generatedAt: Date(timeIntervalSince1970: 2_000),
            sections: []
        )
        try store.save(newerSnapshot)

        let olderSnapshot = WidgetSnapshot(
            revision: 4,
            generatedAt: Date(timeIntervalSince1970: 1_000),
            sections: [] 
        )
        try store.save(olderSnapshot)

        let loaded = try store.load()
        #expect(loaded.revision == newerSnapshot.revision)
        #expect(loaded.generatedAt == newerSnapshot.generatedAt)
    }

    @Test
    func loadDecodesLegacySnapshotWithoutVersionOrRevision() throws {
        let baseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = WidgetSnapshotStore(baseDirectoryURL: baseDirectoryURL)
        let snapshotURL = store.snapshotURL()

        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyData = """
        {
          "generatedAt": "2025-01-02T03:04:05Z",
          "sections": []
        }
        """.data(using: .utf8)!
        try legacyData.write(to: snapshotURL, options: .atomic)

        let loaded = try store.load()
        #expect(loaded.version == WidgetSnapshot.currentVersion)
        #expect(loaded.revision > 0)
        #expect(loaded.sections.isEmpty)
    }
}
