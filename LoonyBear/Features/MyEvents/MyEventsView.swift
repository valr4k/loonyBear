import SwiftUI

struct MyEventsView: View {
    @EnvironmentObject private var eventAppState: EventAppState
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
                    systemImage: "calendar.badge",
                    description: Text("Create your first event to get started.")
                )
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
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
                                    onEditEvent(event)
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
        .background(AppBackground())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onCreateEvent()
                } label: {
                    AppToolbarIconLabel("Create Event", systemName: "plus")
                }
                .appAccentTint()
            }
        }
        .alert("Action failed", isPresented: actionErrorAlertBinding) {
            Button("OK") {
                eventAppState.clearActionError()
            }
        } message: {
            Text(eventAppState.actionErrorMessage ?? "")
        }
    }

    private var events: [EventCardProjection] {
        eventAppState.dashboard.events
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

private struct EventCardView: View {
    let event: EventCardProjection
    let position: PillRowPosition
    let currentTime: Date
    @AppStorage(AppTint.storageKey) private var appTintRawValue = AppTint.blue.rawValue

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

    private var durationColor: Color {
        if EventDurationFormatter.isCountdownComplete(event, now: currentTime) {
            return .red
        }
        return Color(uiColor: AppTint.stored(rawValue: appTintRawValue).uiColor)
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
