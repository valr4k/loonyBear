import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

final class WidgetSyncService {
    private let snapshotStore: WidgetSnapshotStore
    private let clock: AppClock
    private let saveQueue = DispatchQueue(label: "LoonyBear.WidgetSyncService.save", qos: .utility)
    private let stateQueue = DispatchQueue(label: "LoonyBear.WidgetSyncService.state", qos: .utility)
    private var lastSavedSections: [WidgetSectionSnapshot]?
    private var pendingSections: [WidgetSectionSnapshot]?

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

        let shouldScheduleSave = stateQueue.sync { () -> Bool in
            guard lastSavedSections != sections, pendingSections != sections else {
                return false
            }
            pendingSections = sections
            return true
        }
        guard shouldScheduleSave else { return }

        let snapshot = WidgetSnapshot(
            generatedAt: clock.now(),
            sections: sections
        )

        saveQueue.async { [weak self, snapshotStore] in
            do {
                let didWrite = try snapshotStore.saveIfChanged(snapshot)
                self?.finishSave(for: sections, didSucceed: true)
                guard didWrite else { return }
                ReliabilityLog.info("widget.snapshot.save succeeded with \(snapshot.sections.count) section(s)")
                DispatchQueue.main.async {
                    Self.reloadWidgets()
                }
            } catch {
                self?.finishSave(for: sections, didSucceed: false)
                ReliabilityLog.error("widget.snapshot.save failed: \(error.localizedDescription)")
            }
        }
    }

    private func finishSave(for sections: [WidgetSectionSnapshot], didSucceed: Bool) {
        stateQueue.sync {
            if self.pendingSections == sections {
                self.pendingSections = nil
            }
            if didSucceed {
                self.lastSavedSections = sections
            }
        }
    }

    private static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
