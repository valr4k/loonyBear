import Combine
import SwiftUI
struct MyHabitsView: View {
    @EnvironmentObject private var appState: HabitAppState
    @State private var currentTime = Date()
    @State private var habitPendingDeletion: HabitCardProjection?
    private let reminderStateTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    let onCreateHabit: () -> Void
    let onShowHabitInfo: (HabitCardProjection) -> Void
    let onEditHabit: (HabitCardProjection) -> Void

    init(
        onCreateHabit: @escaping () -> Void = {},
        onShowHabitInfo: @escaping (HabitCardProjection) -> Void = { _ in },
        onEditHabit: @escaping (HabitCardProjection) -> Void = { _ in }
    ) {
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
                    "No habits yet",
                    systemImage: "checklist",
                    description: Text("Create your first habit to start tracking your progress.")
                )
            } else {
                List {
                    // Motion policy: default to system navigation and List animations.
                    // Add manual animation only for small local state changes when the native behavior is insufficient.
                    ForEach(sections) { section in
                        Section {
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
                                    if habit.isCompletedToday {
                                        Button {
                                            appState.clearHabitDayStateToday(id: habit.id)
                                        } label: {
                                            Image(systemName: "calendar.badge.minus")
                                        }
                                        .tint(.orange)
                                    } else if habit.isSkippedToday {
                                        Button {
                                            appState.clearHabitDayStateToday(id: habit.id)
                                        } label: {
                                            Image(systemName: "calendar.badge.minus")
                                        }
                                        .tint(.orange)
                                    } else {
                                        Button {
                                            appState.completeHabitToday(id: habit.id)
                                        } label: {
                                            Image(systemName: "checkmark")
                                        }
                                        .tint(.green)

                                        Button {
                                            appState.skipHabitToday(id: habit.id)
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

                                    Button {
                                        habitPendingDeletion = habit
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                        } header: {
                            Text(section.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 10)
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.horizontal, 10, for: .scrollContent)
                .listSectionSpacing(24)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppBackground(style: .habits))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onCreateHabit()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Habit")
            }
        }
        .alert("Delete habit?", isPresented: deleteAlertBinding) {
            Button("Delete", role: .destructive) {
                if let habitPendingDeletion {
                    appState.deleteHabit(id: habitPendingDeletion.id)
                }
                habitPendingDeletion = nil
            }

            Button("Cancel", role: .cancel) {
                habitPendingDeletion = nil
            }
        } message: {
            Text("This habit will be permanently deleted.")
        }
        .alert("Action failed", isPresented: actionErrorAlertBinding) {
            Button("OK") {
                appState.clearActionError()
            }
        } message: {
            Text(appState.actionErrorMessage ?? "")
        }
        .onReceive(reminderStateTimer) { now in
            currentTime = now
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { habitPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    habitPendingDeletion = nil
                }
            }
        )
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

    private var sections: [HabitSectionProjection] {
        appState.dashboard.sections
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

                Text("Current streak: \(DayCountFormatter.compactDurationString(for: habit.currentStreak))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .overlay(alignment: .topTrailing) {
                    if let reminderText = habit.reminderText {
                        Text(reminderText)
                            .font(.caption)
                            .foregroundStyle(isReminderOverdueToday ? .red : .secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .overlay(alignment: .trailing) {
                    if habit.isCompletedToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    } else if habit.isSkippedToday {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
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

    private var isReminderOverdueToday: Bool {
        guard habit.isReminderScheduledToday else { return false }
        guard !habit.isCompletedToday else { return false }
        guard !habit.isSkippedToday else { return false }
        guard
            let reminderHour = habit.reminderHour,
            let reminderMinute = habit.reminderMinute
        else {
            return false
        }

        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: currentTime)
        guard let scheduledDateTime = calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: normalizedDay
        ) else {
            return false
        }

        return scheduledDateTime < currentTime
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
