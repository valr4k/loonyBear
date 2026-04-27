import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

final class WidgetSyncService {
    private let snapshotStore: WidgetSnapshotStore
    private let clock: AppClock
    private let saveQueue = DispatchQueue(label: "LoonyBear.WidgetSyncService.save", qos: .utility)
    private var lastRequestedSections: [WidgetSectionSnapshot]?

    init(
        snapshotStore: WidgetSnapshotStore = WidgetSnapshotStore(),
        clock: AppClock = AppClock()
    ) {
        self.snapshotStore = snapshotStore
        self.clock = clock
    }

    func syncSnapshot(from dashboard: DashboardProjection) {
        let sections = dashboard.sections.map { section in
            WidgetSectionSnapshot(
                type: section.id.rawValue,
                title: section.title,
                habits: section.habits.map { habit in
                    WidgetHabitSnapshot(
                        id: habit.id,
                        name: habit.name,
                        scheduleSummary: habit.scheduleSummary,
                        currentStreak: habit.currentStreak,
                        isCompletedToday: habit.isCompletedToday
                    )
                }
            )
        }

        guard lastRequestedSections != sections else { return }
        lastRequestedSections = sections

        let snapshot = WidgetSnapshot(
            generatedAt: clock.now(),
            sections: sections
        )

        saveQueue.async { [snapshotStore] in
            do {
                let didWrite = try snapshotStore.saveIfChanged(snapshot)
                guard didWrite else { return }
                ReliabilityLog.info("widget.snapshot.save succeeded with \(snapshot.sections.count) section(s)")
                DispatchQueue.main.async {
                    Self.reloadWidgets()
                }
            } catch {
                ReliabilityLog.error("widget.snapshot.save failed: \(error.localizedDescription)")
            }
        }
    }

    private static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
