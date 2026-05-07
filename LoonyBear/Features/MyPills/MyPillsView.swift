import Combine
import SwiftUI

struct MyPillsView: View {
    @EnvironmentObject private var pillAppState: PillAppState
    @State private var isShowingArchive = false
    let currentTime: Date
    let onCreatePill: () -> Void
    let onOpenArchivedPill: (PillCardProjection) -> Void
    let onEditPill: (PillCardProjection) -> Void

    init(
        currentTime: Date = Date(),
        onCreatePill: @escaping () -> Void = {},
        onOpenArchivedPill: @escaping (PillCardProjection) -> Void = { _ in },
        onEditPill: @escaping (PillCardProjection) -> Void = { _ in }
    ) {
        self.currentTime = currentTime
        self.onCreatePill = onCreatePill
        self.onOpenArchivedPill = onOpenArchivedPill
        self.onEditPill = onEditPill
    }

    var body: some View {
        Group {
            if pillAppState.isLoading || !pillAppState.hasLoadedOnce {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pillAppState.hasLoadedOnce && activePills.isEmpty {
                ContentUnavailableView(
                    pills.isEmpty ? "No pills yet" : "No active pills",
                    systemImage: "pills",
                    description: Text(pills.isEmpty ? "Create your first pill to track dosage, reminders, and taken days." : "Deleted pills live in Recently Deleted.")
                )
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
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
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onEditPill(pill)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    if pill.isArchived || pill.startsInFuture {
                                        EmptyView()
                                    } else if let overdueDay = pill.activeOverdueDay {
                                        Button {
                                            performSwipeAction {
                                                await pillAppState.markPillTaken(id: pill.id, on: overdueDay, animatedRefresh: true)
                                            }
                                        } label: {
                                            Image(systemName: "checkmark")
                                        }
                                        .tint(.green)

                                        Button {
                                            performSwipeAction {
                                                await pillAppState.skipPillDay(id: pill.id, on: overdueDay, animatedRefresh: true)
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                        }
                                        .tint(.red)
                                    } else if pill.isTakenToday {
                                        Button {
                                            performSwipeAction {
                                                await pillAppState.clearPillDayStateToday(id: pill.id, animatedRefresh: true)
                                            }
                                        } label: {
                                            Image(systemName: "arrow.uturn.backward")
                                        }
                                        .tint(.orange)
                                    } else if pill.isSkippedToday {
                                        Button {
                                            performSwipeAction {
                                                await pillAppState.clearPillDayStateToday(id: pill.id, animatedRefresh: true)
                                            }
                                        } label: {
                                            Image(systemName: "arrow.uturn.backward")
                                        }
                                        .tint(.orange)
                                    } else {
                                        Button {
                                            performSwipeAction {
                                                await pillAppState.markTakenToday(id: pill.id, animatedRefresh: true)
                                            }
                                        } label: {
                                            Image(systemName: "checkmark")
                                        }
                                        .tint(.green)

                                        Button {
                                            performSwipeAction {
                                                await pillAppState.skipPillToday(id: pill.id, animatedRefresh: true)
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                        }
                                        .tint(.red)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.horizontal, 10, for: .scrollContent)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppBackground(style: .pills))
        .navigationDestination(isPresented: $isShowingArchive) {
            ArchivedPillsView(
                currentTime: currentTime,
                onOpenPill: onOpenArchivedPill
            )
            .environmentObject(pillAppState)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if hasArchivedPills {
                    Button {
                        isShowingArchive = true
                    } label: {
                        AppToolbarIconLabel("Recently Deleted", systemName: "tray.badge")
                    }
                    .appAccentTint()
                }

                Button {
                    onCreatePill()
                } label: {
                    AppToolbarIconLabel("Create Pill", systemName: "plus")
                }
                .appAccentTint()
            }
        }
        .alert("Action failed", isPresented: actionErrorAlertBinding) {
            Button("OK") {
                pillAppState.clearActionError()
            }
        } message: {
            Text(pillAppState.actionErrorMessage ?? "")
        }
    }

    private var pills: [PillCardProjection] {
        pillAppState.dashboard.pills
    }

    private var activePills: [PillCardProjection] {
        pills.filter { !$0.isArchived }
    }

    private var hasArchivedPills: Bool {
        pills.contains { $0.isArchived }
    }

    private var sections: [PillDashboardSectionProjection] {
        let today = activePills.filter { $0.isScheduledToday || $0.activeOverdueDay != nil }
        let pending = activePills.filter { !$0.isScheduledToday && $0.activeOverdueDay == nil }
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

    private func performSwipeAction(_ action: @escaping () async -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            await action()
        }
    }
}

private struct ArchivedPillsView: View {
    @EnvironmentObject private var pillAppState: PillAppState
    let currentTime: Date
    let onOpenPill: (PillCardProjection) -> Void

    var body: some View {
        Group {
            if archivedPills.isEmpty {
                ContentUnavailableView(
                    "No recently deleted pills",
                    systemImage: "trash",
                    description: Text("Deleted pills will appear here.")
                )
            } else {
                List {
                    ForEach(Array(archivedPills.enumerated()), id: \.element.id) { index, pill in
                        PillCardView(
                            pill: pill,
                            position: rowPosition(for: index, count: archivedPills.count),
                            currentTime: currentTime
                        )
                        .padding(.horizontal, 10)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onOpenPill(pill)
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.horizontal, 10, for: .scrollContent)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppBackground(style: .pills))
        .appTintedBackButton()
    }

    private var archivedPills: [PillCardProjection] {
        pillAppState.dashboard.pills.filter(\.isArchived)
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
