import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

final class WidgetSyncService {
    private let snapshotStore: WidgetSnapshotStore

    init(snapshotStore: WidgetSnapshotStore = WidgetSnapshotStore()) {
        self.snapshotStore = snapshotStore
    }

    func syncSnapshot(from dashboard: DashboardProjection) {
        let snapshot = WidgetSnapshot(
            generatedAt: Date(),
            sections: dashboard.sections.map { section in
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
        )

        do {
            try snapshotStore.save(snapshot)
            ReliabilityLog.info("widget.snapshot.save succeeded with \(snapshot.sections.count) section(s)")
            reloadWidgets()
        } catch {
            ReliabilityLog.error("widget.snapshot.save failed: \(error.localizedDescription)")
        }
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
