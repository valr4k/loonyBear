import Combine
import SwiftUI
struct MyHabitsView: View {
    @EnvironmentObject private var appState: HabitAppState
    @State private var isShowingArchive = false
    let currentTime: Date
    let onCreateHabit: () -> Void
    let onShowHabitInfo: (HabitCardProjection) -> Void
    let onEditHabit: (HabitCardProjection) -> Void

    init(
        currentTime: Date = Date(),
        onCreateHabit: @escaping () -> Void = {},
        onShowHabitInfo: @escaping (HabitCardProjection) -> Void = { _ in },
        onEditHabit: @escaping (HabitCardProjection) -> Void = { _ in }
    ) {
        self.currentTime = currentTime
        self.onCreateHabit = onCreateHabit
        self.onShowHabitInfo = onShowHabitInfo
        self.onEditHabit = onEditHabit
    }

    var body: some View {
        Group {
            if appState.isLoading || !appState.hasLoadedOnce {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.hasLoadedOnce && sections.isEmpty {
                ContentUnavailableView(
                    allHabits.isEmpty ? "No habits yet" : "No active habits",
                    systemImage: "checklist",
                    description: Text(allHabits.isEmpty ? "Create your first habit to start tracking your progress." : "Archived habits live on the Archive page.")
                )
            } else {
                List {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        sectionHeader(section.title, isFirst: sectionIndex == 0)

                        ForEach(Array(section.habits.enumerated()), id: \.element.id) { index, habit in
                            HabitCardView(
                                habit: habit,
                                position: rowPosition(for: index, count: section.habits.count),
                                currentTime: currentTime
                            )
                            .padding(.horizontal, 10)
                            .listRowInsets(EdgeInsets())
	                            .listRowBackground(Color.clear)
	                            .listRowSeparator(.hidden)
	                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
	                                if habit.isArchived || habit.startsInFuture {
	                                    EmptyView()
                                } else if let overdueDay = habit.activeOverdueDay {
                                    Button {
                                        performSwipeAction {
                                            await appState.completeHabitDay(id: habit.id, on: overdueDay, animatedRefresh: true)
                                        }
                                    } label: {
                                        Image(systemName: "checkmark")
                                    }
                                    .tint(.green)

                                    Button {
                                        performSwipeAction {
                                            await appState.skipHabitDay(id: habit.id, on: overdueDay, animatedRefresh: true)
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .tint(.red)
                                } else if habit.isCompletedToday {
                                    Button {
                                        performSwipeAction {
                                            await appState.clearHabitDayStateToday(id: habit.id, animatedRefresh: true)
                                        }
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                    .tint(.orange)
                                } else if habit.isSkippedToday {
                                    Button {
                                        performSwipeAction {
                                            await appState.clearHabitDayStateToday(id: habit.id, animatedRefresh: true)
                                        }
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                    .tint(.orange)
                                } else {
                                    Button {
                                        performSwipeAction {
                                            await appState.completeHabitToday(id: habit.id, animatedRefresh: true)
                                        }
                                    } label: {
                                        Image(systemName: "checkmark")
                                    }
                                    .tint(.green)

                                    Button {
                                        performSwipeAction {
                                            await appState.skipHabitToday(id: habit.id, animatedRefresh: true)
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .tint(.red)
                                }
	                            }
	                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
	                                Button {
	                                    onShowHabitInfo(habit)
	                                } label: {
	                                    Image(systemName: "info")
	                                }
	                                .tint(.indigo)

	                                Button {
	                                    onEditHabit(habit)
	                                } label: {
	                                    Image(systemName: "pencil")
	                                }
	                                .tint(.blue)
	                            }
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.horizontal, 10, for: .scrollContent)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppBackground(style: .habits))
        .navigationDestination(isPresented: $isShowingArchive) {
            ArchivedHabitsView(
                currentTime: currentTime,
                onShowHabitInfo: onShowHabitInfo,
                onEditHabit: onEditHabit
            )
            .environmentObject(appState)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingArchive = true
                } label: {
                    AppToolbarIconLabel("Archived Habits", systemName: "archivebox")
                }
                .appAccentTint()

                Button {
                    onCreateHabit()
                } label: {
                    AppToolbarIconLabel("Create Habit", systemName: "plus")
                }
                .appAccentTint()
            }
        }
        .alert("Action failed", isPresented: actionErrorAlertBinding) {
            Button("OK") {
                appState.clearActionError()
            }
        } message: {
            Text(appState.actionErrorMessage ?? "")
        }
    }

    private func sectionHeader(_ title: String, isFirst: Bool) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, isFirst ? 0 : 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var actionErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { appState.actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appState.clearActionError()
                }
            }
        )
    }

    private var allHabits: [HabitCardProjection] {
        appState.dashboard.sections.flatMap(\.habits)
    }

    private var sections: [HabitSectionProjection] {
        appState.dashboard.sections.filter { $0.id != .archived }
    }

    private func rowPosition(for index: Int, count: Int) -> HabitRowPosition {
        if count == 1 {
            return .single
        }
        if index == 0 {
            return .first
        }
        if index == count - 1 {
            return .last
        }
        return .middle
    }

    private func performSwipeAction(_ action: @escaping () async -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            await action()
        }
    }
}

private struct ArchivedHabitsView: View {
    @EnvironmentObject private var appState: HabitAppState
    let currentTime: Date
    let onShowHabitInfo: (HabitCardProjection) -> Void
    let onEditHabit: (HabitCardProjection) -> Void

    var body: some View {
        Group {
            if archivedHabits.isEmpty {
                ContentUnavailableView(
                    "No archived habits",
                    systemImage: "archivebox",
                    description: Text("Archived habits will appear here.")
                )
            } else {
                List {
                    ForEach(Array(archivedHabits.enumerated()), id: \.element.id) { index, habit in
                        HabitCardView(
                            habit: habit,
                            position: rowPosition(for: index, count: archivedHabits.count),
                            currentTime: currentTime
                        )
                        .padding(.horizontal, 10)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                onShowHabitInfo(habit)
                            } label: {
                                Image(systemName: "info")
                            }
                            .tint(.indigo)

                            Button {
                                onEditHabit(habit)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.horizontal, 10, for: .scrollContent)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Archived Habits")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppBackground(style: .habits))
        .appTintedBackButton()
    }

    private var archivedHabits: [HabitCardProjection] {
        appState.dashboard.sections
            .first { $0.id == .archived }?
            .habits ?? []
    }

    private func rowPosition(for index: Int, count: Int) -> HabitRowPosition {
        if count == 1 {
            return .single
        }
        if index == 0 {
            return .first
        }
        if index == count - 1 {
            return .last
        }
        return .middle
    }
}

private struct HabitCardView: View {
    let habit: HabitCardProjection
    let position: HabitRowPosition
    let currentTime: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(habit.scheduleSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)

                Text("Current streak: \(DayCountFormatter.compactDurationString(for: habit.currentStreak))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .overlay(alignment: .topTrailing) {
                    if let futureStartLabel {
                        Text(futureStartLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    } else if habit.reminderText != nil || activeOverdueLabel != nil {
                        VStack(alignment: .trailing, spacing: 2) {
                            if let reminderText = habit.reminderText {
                                Text(reminderText)
                            }
                            if let activeOverdueLabel {
                                Text(activeOverdueLabel)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(isReminderOverdue ? .red : .secondary)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .overlay(alignment: .trailing) {
                    if !habit.needsHistoryReview, habit.isCompletedToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                    } else if !habit.needsHistoryReview, habit.isSkippedToday {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if habit.needsHistoryReview {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("History needs review")
                    }
                }
            .frame(width: 40)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            position.backgroundShape
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var isReminderOverdue: Bool {
        habit.activeOverdueDay != nil
    }

    private var activeOverdueLabel: String? {
        guard let overdueDay = habit.activeOverdueDay else { return nil }
        return OverdueDayLabel.text(for: overdueDay, now: currentTime)
    }

    private var futureStartLabel: String? {
        guard habit.startsInFuture, let futureStartDate = habit.futureStartDate else { return nil }
        return FutureStartLabel.text(for: futureStartDate)
    }
}

private enum HabitRowPosition {
    case single
    case first
    case middle
    case last

    @ViewBuilder
    var backgroundShape: some InsettableShape {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
    }

    private var cornerRadii: RectangleCornerRadii {
        switch self {
        case .single:
            .init(topLeading: 22, bottomLeading: 22, bottomTrailing: 22, topTrailing: 22)
        case .first:
            .init(topLeading: 22, bottomLeading: 0, bottomTrailing: 0, topTrailing: 22)
        case .middle:
            .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0)
        case .last:
            .init(topLeading: 0, bottomLeading: 22, bottomTrailing: 22, topTrailing: 0)
        }
    }
}

#Preview {
    MyHabitsView()
        .environmentObject(AppEnvironment.preview.appState)
}
