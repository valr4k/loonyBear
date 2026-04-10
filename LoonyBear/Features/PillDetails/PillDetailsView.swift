import SwiftUI

struct PillDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pillAppState: PillAppState
    let pill: PillCardProjection

    @State private var details: PillDetailsProjection?
    @State private var isLoadingDetails = true
    @State private var needsReloadOnAppear = false
    @State private var displayedMonth: Date = {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }()

    var body: some View {
        AppScreen(backgroundStyle: .pills, topPadding: 8) {
            if isLoadingDetails {
                AppCard {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 28)
                        Spacer()
                    }
                }
            } else if let details {
                AppCard {
                    VStack(alignment: .center, spacing: 8) {
                        Text(details.name)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        Text(details.dosage)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 22)
                    AppSectionDivider()
                    AppValueRow(title: "Start Date", value: details.startDate.formatted(date: .abbreviated, time: .omitted))
                    AppSectionDivider()
                    AppValueRow(title: "Plan", value: details.scheduleSummary)
                    AppSectionDivider()
                    AppValueRow(title: "Reminder", value: details.reminderTime?.formatted ?? "Off")
                }

                AppCard {
                    AppValueRow(title: "Taken for", value: DayCountFormatter.compactDurationString(for: details.totalTakenDays), valueColor: AnyShapeStyle(.primary))
                }

                AppCard {
                    PillReadOnlyMonthCalendarView(
                        month: displayedMonth,
                        takenDays: details.takenDays,
                        skippedDays: details.skippedDays,
                        availableMonths: availableMonths(for: details.startDate),
                        onMonthChange: { displayedMonth = $0 }
                    )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }

                if let description = details.details, !description.isEmpty {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Description")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Pill not found",
                    systemImage: "pills",
                    description: Text("This pill is no longer available.")
                )
            }
        }
        .navigationTitle("Pill Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
        }
        .onAppear {
            guard needsReloadOnAppear else { return }
            needsReloadOnAppear = false
            reloadDetails()
        }
        .task {
            reloadDetails()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pillStoreDidChange)) { _ in
            reloadDetails()
        }
    }

    private func reloadDetails() {
        isLoadingDetails = true
        details = pillAppState.pillDetails(id: pill.id)
        isLoadingDetails = false
    }

    private func availableMonths(for startDate: Date) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())
        guard start <= today else { return [] }

        var months: [Date] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        let lastMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today

        while cursor <= lastMonth {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        return months
    }
}
