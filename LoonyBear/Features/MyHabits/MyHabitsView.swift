import Combine
import SwiftUI
struct MyHabitsView: View {
    @EnvironmentObject private var appState: HabitAppState
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
                                    if let overdueDay = habit.activeOverdueDay {
                                        Button {
                                            Task {
                                                await appState.completeHabitDay(id: habit.id, on: overdueDay)
                                            }
                                        } label: {
                                            Image(systemName: "checkmark")
                                        }
                                        .tint(.green)

                                        Button {
                                            Task {
                                                await appState.skipHabitDay(id: habit.id, on: overdueDay)
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                        }
                                        .tint(.red)
                                    } else if habit.isCompletedToday {
                                        Button {
                                            Task {
                                                await appState.clearHabitDayStateToday(id: habit.id)
                                            }
                                        } label: {
                                            Image(systemName: "calendar.badge.minus")
                                        }
                                        .tint(.orange)
                                    } else if habit.isSkippedToday {
                                        Button {
                                            Task {
                                                await appState.clearHabitDayStateToday(id: habit.id)
                                            }
                                        } label: {
                                            Image(systemName: "calendar.badge.minus")
                                        }
                                        .tint(.orange)
                                    } else {
                                        Button {
                                            Task {
                                                await appState.completeHabitToday(id: habit.id)
                                            }
                                        } label: {
                                            Image(systemName: "checkmark")
                                        }
                                        .tint(.green)

                                        Button {
                                            Task {
                                                await appState.skipHabitToday(id: habit.id)
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
                                    .tint(.blue)
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
        .alert("Action failed", isPresented: actionErrorAlertBinding) {
            Button("OK") {
                appState.clearActionError()
            }
        } message: {
            Text(appState.actionErrorMessage ?? "")
        }
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
                    if habit.reminderText != nil || activeOverdueLabel != nil {
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
