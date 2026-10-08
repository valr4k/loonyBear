import SwiftUI

enum CardReminderStyle: Equatable {
    case neutral
    case overdue
    case completed
    case scheduled
    case historyReview
    case skipped

    init(
        isArchived: Bool,
        startsInFuture: Bool,
        isOverdue: Bool,
        needsHistoryReview: Bool,
        isCompleted: Bool,
        isSkipped: Bool
    ) {
        if isArchived || startsInFuture {
            self = .neutral
        } else if isOverdue {
            self = .overdue
        } else if needsHistoryReview {
            self = .historyReview
        } else if isCompleted {
            self = .completed
        } else if isSkipped {
            self = .skipped
        } else {
            self = .scheduled
        }
    }

    var color: Color {
        switch self {
        case .neutral:
            .secondary
        case .overdue:
            .red
        case .completed:
            .green
        case .scheduled:
            .blue.opacity(0.75)
        case .historyReview:
            .orange.opacity(0.75)
        case .skipped:
            .red.opacity(0.75)
        }
    }
}
