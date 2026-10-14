import SwiftUI

struct MyEventsView: View {
    @EnvironmentObject private var eventAppState: EventAppState
    @State private var pendingOrder: [EventCardProjection]?
    @State private var isSavingOrder = false
    let currentTime: Date
    let onCreateEvent: () -> Void
    let onEditEvent: (EventCardProjection) -> Void

    init(
        currentTime: Date = Date(),
        onCreateEvent: @escaping () -> Void = {},
        onEditEvent: @escaping (EventCardProjection) -> Void = { _ in }
    ) {
        self.currentTime = currentTime
        self.onCreateEvent = onCreateEvent
        self.onEditEvent = onEditEvent
    }

    var body: some View {
        Group {
            if eventAppState.isLoading || !eventAppState.hasLoadedOnce {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                ContentUnavailableView(
                    "No Events Yet",
                    systemImage: "calendar",
                    description: Text("Create your first event to get started.")
                )
            } else {
                List {
                    ForEach(sections) { section in
                        Section {
                            AppListSectionHeader(title: section.title)

                            ForEach(Array(section.events.enumerated()), id: \.element.id) { index, event in
                                EventCardView(
                                    event: event,
                                    position: rowPosition(for: index, count: section.events.count),
                                    currentTime: currentTime
                                )
                                .padding(.horizontal, 10)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !isSavingOrder else { return }
                                    onEditEvent(event)
                                }
                                .modifier(EventReorderModifier(
                                    enabled: !isSavingOrder,
                                    event: event, events: section.events,
                                    move: { ids in saveOrder(ids, mode: event.mode) }
                                ))
                            }
                            .onMove { offsets, destination in
                                guard !isSavingOrder else { return }
                                var ids = section.events.map(\.id)
                                ids.move(fromOffsets: offsets, toOffset: destination)
                                saveOrder(ids, mode: section.events[0].mode)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.horizontal, 10, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.inactive))
            }
        }
        .background(AppBackground())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onCreateEvent()
                } label: {
                    AppToolbarIconLabel("Create Event", systemName: "plus")
                }
                .appAccentTint()
                .disabled(isSavingOrder)
            }
        }
        .appAlert("Action failed", isPresented: actionErrorAlertBinding) {
            Button("OK") {
                eventAppState.clearActionError()
            }
        } message: {
            Text(eventAppState.actionErrorMessage ?? "")
        }
    }

    private var events: [EventCardProjection] {
        pendingOrder ?? eventAppState.dashboard.events
    }

    private func saveOrder(_ ids: [UUID], mode: EventMode) {
        guard !isSavingOrder else { return }
        guard ids != events.filter({ $0.mode == mode }).map(\.id) else { return }
        let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        var reordered = ids.compactMap { byID[$0] }.makeIterator()
        pendingOrder = events.map { $0.mode == mode ? (reordered.next() ?? $0) : $0 }
        isSavingOrder = true
        Task {
            await eventAppState.reorderEvents(ids: ids, mode: mode)
            pendingOrder = nil
            isSavingOrder = false
        }
    }

    private var sections: [EventDashboardSectionProjection] {
        [
            EventDashboardSectionProjection(
                id: .countdown,
                title: "Countdown",
                events: events.filter { $0.mode == .countdown }
            ),
            EventDashboardSectionProjection(
                id: .countUp,
                title: "Count Up",
                events: events.filter { $0.mode == .countUp }
            ),
        ].filter { !$0.events.isEmpty }
    }

    private var actionErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { eventAppState.actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    eventAppState.clearActionError()
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

struct EventReorderModifier: ViewModifier {
    let enabled: Bool
    let event: EventCardProjection
    let events: [EventCardProjection]
    let move: ([UUID]) -> Void

    func body(content: Content) -> some View {
        content
            .moveDisabled(!enabled)
            .accessibilityActions {
                if enabled {
                    Button("Move up") { moveBy(-1) }
                    Button("Move down") { moveBy(1) }
                }
            }
    }

    private func moveBy(_ offset: Int) {
        guard let source = events.firstIndex(where: { $0.id == event.id }),
              events.indices.contains(source + offset) else { return }
        var ids = events.map(\.id)
        ids.swapAt(source, source + offset)
        move(ids)
    }
}

struct EventCardView: View {
    let event: EventCardProjection
    let position: PillRowPosition
    let currentTime: Date
    @Environment(\.appTint) private var appTint

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(durationText)
                .font(.headline)
                .foregroundStyle(durationColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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

    private var durationText: String {
        EventDurationFormatter.text(for: event, now: currentTime)
    }

    var durationColor: Color {
        if EventDurationFormatter.isCountdownComplete(event, now: currentTime) {
            return event.acknowledgedAt == nil ? .red : .secondary
        }
        return appTint.accentColor
    }
}

private enum EventDashboardSectionID: Hashable {
    case countdown
    case countUp
}

private struct EventDashboardSectionProjection: Identifiable {
    let id: EventDashboardSectionID
    let title: String
    let events: [EventCardProjection]
}

#Preview {
    MyEventsView()
        .environmentObject(AppEnvironment.preview.eventAppState)
}
