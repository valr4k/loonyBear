import Foundation
import Testing

@testable import LoonyBear

struct WidgetSyncServiceTests {
    @Test
    func retriesSameSectionsAfterInitialSaveFailure() async throws {
        let baseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileManager = FailOnceFileManager()
        let snapshotStore = WidgetSnapshotStore(
            fileManager: fileManager,
            baseDirectoryURL: baseDirectoryURL
        )
        let service = WidgetSyncService(
            snapshotStore: snapshotStore,
            clock: AppClock(now: { Date(timeIntervalSince1970: 1_000) })
        )
        let dashboard = makeDashboardProjection()

        service.syncSnapshot(from: dashboard)
        try await waitUntil {
            fileManager.createDirectoryCallCount >= 1
        }
        #expect(FileManager.default.fileExists(atPath: snapshotStore.snapshotURL().path) == false)

        service.syncSnapshot(from: dashboard)
        try await waitUntil {
            FileManager.default.fileExists(atPath: snapshotStore.snapshotURL().path)
        }

        let snapshot = try snapshotStore.load()
        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections.first?.habits.count == 1)
        #expect(fileManager.createDirectoryCallCount >= 2)
    }

    private func makeDashboardProjection() -> DashboardProjection {
        DashboardProjection(
            sections: [
                HabitSectionProjection(
                    id: .build,
                    title: "Build",
                    habits: [
                        HabitCardProjection(
                            id: UUID(),
                            type: .build,
                            name: "Ship widget sync",
                            scheduleSummary: "Daily",
                            currentStreak: 3,
                            reminderText: nil,
                            reminderHour: nil,
                            reminderMinute: nil,
                            isReminderScheduledToday: false,
                            isCompletedToday: false,
                            isSkippedToday: false,
                            sortOrder: 0
                        )
                    ]
                )
            ]
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        intervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @Sendable () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                Issue.record("Timed out waiting for condition.")
                return
            }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }
}

private final class FailOnceFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var hasFailedCreateDirectory = false
    private(set) var createDirectoryCallCount = 0

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        lock.lock()
        createDirectoryCallCount += 1
        let shouldFail = !hasFailedCreateDirectory
        if shouldFail {
            hasFailedCreateDirectory = true
        }
        lock.unlock()

        if shouldFail {
            throw CocoaError(.fileWriteUnknown)
        }

        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }
}
