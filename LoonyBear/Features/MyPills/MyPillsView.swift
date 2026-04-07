import Combine
import SwiftUI

struct MyPillsView: View {
    @EnvironmentObject private var pillAppState: PillAppState
    @State private var currentTime = Date()
    @State private var pillPendingDeletion: PillCardProjection?

    private let reminderStateTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    let onCreatePill: () -> Void
    let onSelectPill: (PillCardProjection) -> Void

    init(
        onCreatePill: @escaping () -> Void = {},
        onSelectPill: @escaping (PillCardProjection) -> Void = { _ in }
    ) {
        self.onCreatePill = onCreatePill
        self.onSelectPill = onSelectPill
    }

    var body: some View {
        Group {
            if pillAppState.isLoading || !pillAppState.hasLoadedOnce {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pillAppState.hasLoadedOnce && pills.isEmpty {
                ContentUnavailableView(
                    "No pills yet",
                    systemImage: "pills",
                    description: Text("Create your first pill to track dosage, reminders, and taken days.")
                )
            } else {
                List {
                    ForEach(sections) { section in
                        Section {
                            ForEach(Array(section.pills.enumerated()), id: \.element.id) { index, pill in
                                Button {
                                    onSelectPill(pill)
                                } label: {
                                    PillCardView(
                                        pill: pill,
                                        position: rowPosition(for: index, count: section.pills.count),
                                        currentTime: currentTime
                                    )
                                    .padding(.horizontal, 10)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        if pill.isTakenToday {
                                            pillAppState.unmarkTakenToday(id: pill.id)
                                        } else {
                                            pillAppState.markTakenToday(id: pill.id)
                                        }
                                    } label: {
                                        Image(systemName: pill.isTakenToday ? "xmark" : "checkmark")
                                    }
                                    .tint(pill.isTakenToday ? .orange : .green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        pillPendingDeletion = pill
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
        .background(AppBackground(style: .pills))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onCreatePill()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Pill")
            }
        }
        .alert("Delete pill?", isPresented: deleteAlertBinding) {
            Button("Delete", role: .destructive) {
                if let pillPendingDeletion {
                    pillAppState.deletePill(id: pillPendingDeletion.id)
                }
                pillPendingDeletion = nil
            }

            Button("Cancel", role: .cancel) {
                pillPendingDeletion = nil
            }
        } message: {
            Text("This pill will be permanently deleted.")
        }
        .alert("Action failed", isPresented: actionErrorAlertBinding) {
            Button("OK") {
                pillAppState.clearActionError()
            }
        } message: {
            Text(pillAppState.actionErrorMessage ?? "")
        }
        .onReceive(reminderStateTimer) { now in
            currentTime = now
        }
    }

    private var pills: [PillCardProjection] {
        pillAppState.dashboard.pills.sorted(by: pillSort)
    }

    private var sections: [PillDashboardSectionProjection] {
        let today = pills.filter(\.isScheduledToday)
        let pending = pills.filter { !$0.isScheduledToday }
        return [
            PillDashboardSectionProjection(id: .today, title: "Today", pills: today),
            PillDashboardSectionProjection(id: .pending, title: "Pending", pills: pending),
        ].filter { !$0.pills.isEmpty }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pillPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pillPendingDeletion = nil
                }
            }
        )
    }

    private var actionErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { pillAppState.actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    pillAppState.clearActionError()
                }
            }
        )
    }

    private func rowPosition(for index: Int, count: Int) -> PillRowPosition {
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

    private func pillSort(_ lhs: PillCardProjection, _ rhs: PillCardProjection) -> Bool {
        let lhsTime = sortTime(for: lhs)
        let rhsTime = sortTime(for: rhs)

        if lhsTime != rhsTime {
            return lhsTime < rhsTime
        }

        return lhs.sortOrder < rhs.sortOrder
    }

    private func sortTime(for pill: PillCardProjection) -> Int {
        guard let hour = pill.reminderHour, let minute = pill.reminderMinute else {
            return Int.max
        }

        return hour * 60 + minute
    }
}

#Preview {
    MyPillsView()
        .environmentObject(AppEnvironment.preview.pillAppState)
}

private enum PillDashboardSectionID: Hashable {
    case today
    case pending
}

private struct PillDashboardSectionProjection: Identifiable {
    let id: PillDashboardSectionID
    let title: String
    let pills: [PillCardProjection]
}
