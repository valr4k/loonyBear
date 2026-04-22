import Combine
import SwiftUI

struct MyPillsView: View {
    @EnvironmentObject private var pillAppState: PillAppState
    @State private var currentTime = Date()

    private let reminderStateTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    let onCreatePill: () -> Void
    let onShowPillInfo: (PillCardProjection) -> Void
    let onEditPill: (PillCardProjection) -> Void

    init(
        onCreatePill: @escaping () -> Void = {},
        onShowPillInfo: @escaping (PillCardProjection) -> Void = { _ in },
        onEditPill: @escaping (PillCardProjection) -> Void = { _ in }
    ) {
        self.onCreatePill = onCreatePill
        self.onShowPillInfo = onShowPillInfo
        self.onEditPill = onEditPill
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
                                PillCardView(
                                    pill: pill,
                                    position: rowPosition(for: index, count: section.pills.count),
                                    currentTime: currentTime
                                )
                                .padding(.horizontal, 10)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    if pill.isTakenToday {
                                        Button {
                                            Task {
                                                await pillAppState.clearPillDayStateToday(id: pill.id)
                                            }
                                        } label: {
                                            Image(systemName: "calendar.badge.minus")
                                        }
                                        .tint(.orange)
                                    } else if pill.isSkippedToday {
                                        Button {
                                            Task {
                                                await pillAppState.clearPillDayStateToday(id: pill.id)
                                            }
                                        } label: {
                                            Image(systemName: "calendar.badge.minus")
                                        }
                                        .tint(.orange)
                                    } else {
                                        Button {
                                            Task {
                                                await pillAppState.markTakenToday(id: pill.id)
                                            }
                                        } label: {
                                            Image(systemName: "checkmark")
                                        }
                                        .tint(.green)

                                        Button {
                                            Task {
                                                await pillAppState.skipPillToday(id: pill.id)
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                        }
                                        .tint(.red)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        onShowPillInfo(pill)
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
        pillAppState.dashboard.pills
    }

    private var sections: [PillDashboardSectionProjection] {
        let today = pills.filter(\.isScheduledToday)
        let pending = pills.filter { !$0.isScheduledToday }
        return [
            PillDashboardSectionProjection(id: .today, title: "Today", pills: today),
            PillDashboardSectionProjection(id: .pending, title: "Pending", pills: pending),
        ].filter { !$0.pills.isEmpty }
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
