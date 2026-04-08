import SwiftUI

enum AppBackgroundStyle {
    case `default`
    case habits
    case pills
    case settings
}

struct AppScreen<Content: View>: View {
    var backgroundStyle: AppBackgroundStyle = .default
    var topPadding: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .padding(.bottom, 40)
        }
        .background(AppBackground(style: backgroundStyle))
    }
}

struct AppBackground: View {
    let style: AppBackgroundStyle
    @Environment(\.colorScheme) private var colorScheme

    init(style: AppBackgroundStyle = .default) {
        self.style = style
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            tintColor
                .opacity(tintOpacity)
        }
        .ignoresSafeArea()
    }

    private var tintColor: Color {
        .clear
    }

    private var tintOpacity: Double {
        0
    }
}

struct AppSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        content
    }
}

struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

struct AppInsetCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

struct AppValueRow: View {
    let title: String
    let value: String
    var valueColor: AnyShapeStyle = AnyShapeStyle(.secondary)
    var showsChevron = false

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }
}

struct AppValidationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppSectionDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 18)
    }
}

struct AppEmptyStateCard: View {
    let title: String
    let message: String
    let symbol: String
    let buttonTitle: String?
    let action: (() -> Void)?

    init(title: String, message: String, symbol: String, buttonTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.buttonTitle = buttonTitle
        self.action = action
    }

    var body: some View {
        AppCard {
            VStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.blue)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let buttonTitle, let action {
                    Button(buttonTitle, action: action)
                        .buttonStyle(.glassProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
    }
}

struct InlineDaysSelector: View {
    @Binding var selection: WeekdaySet

    private let fullDayNames: [(String, WeekdaySet)] = [
        ("Monday", .monday),
        ("Tuesday", .tuesday),
        ("Wednesday", .wednesday),
        ("Thursday", .thursday),
        ("Friday", .friday),
        ("Saturday", .saturday),
        ("Sunday", .sunday),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(fullDayNames, id: \.0) { day in
                HStack {
                    Text(day.0)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(day.1) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggle(day.1)
                }

                if day.0 != fullDayNames.last?.0 {
                    AppSectionDivider()
                }

            }
        }
    }

    private func toggle(_ weekday: WeekdaySet) {
        var updatedSelection = selection
        if updatedSelection.contains(weekday) {
            updatedSelection.remove(weekday)
        } else {
            updatedSelection.insert(weekday)
        }
        selection = updatedSelection
    }
}
