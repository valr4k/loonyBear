import SwiftUI

struct ReminderDaysPickerView: View {
    @Binding var selection: WeekdaySet
    @State private var draftSelection: WeekdaySet

    init(selection: Binding<WeekdaySet>) {
        _selection = selection
        _draftSelection = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        AppScreen {
            AppSection(title: "Days") {
                AppCard {
                    ForEach(fullDayNames, id: \.0) { day in
                        Button {
                            toggle(day.1)
                        } label: {
                            HStack {
                                Text(day.0)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if draftSelection.contains(day.1) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 18, weight: .semibold))
                                        .appAccentForeground()
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if day.0 != fullDayNames.last?.0 {
                            AppSectionDivider()
                        }
                    }
                }
            }
        }
        .navigationTitle("Days")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draftSelection) { _, newValue in
            selection = newValue
        }
        .onDisappear {
            selection = draftSelection
        }
    }

    private func toggle(_ weekday: WeekdaySet) {
        var updatedSelection = draftSelection
        if updatedSelection.contains(weekday) {
            updatedSelection.remove(weekday)
        } else {
            updatedSelection.insert(weekday)
        }
        draftSelection = updatedSelection
    }

    private var fullDayNames: [(String, WeekdaySet)] {
        [
            ("Monday", .monday),
            ("Tuesday", .tuesday),
            ("Wednesday", .wednesday),
            ("Thursday", .thursday),
            ("Friday", .friday),
            ("Saturday", .saturday),
            ("Sunday", .sunday),
        ]
    }
}

#Preview {
    NavigationStack {
        ReminderDaysPickerView(selection: .constant(.weekdays))
    }
}
