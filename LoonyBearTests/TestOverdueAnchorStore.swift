import Foundation

@testable import LoonyBear

final class TestOverdueAnchorStore: OverdueAnchorStore {
    private var values: [String: Date] = [:]

    func anchorDay(for kind: OverdueAnchorKind, id: UUID, calendar: Calendar) -> Date? {
        values[key(for: kind, id: id)].map { calendar.startOfDay(for: $0) }
    }

    func setAnchorDay(_ day: Date, for kind: OverdueAnchorKind, id: UUID, calendar: Calendar) {
        values[key(for: kind, id: id)] = calendar.startOfDay(for: day)
    }

    func clearAnchorDay(for kind: OverdueAnchorKind, id: UUID) {
        values.removeValue(forKey: key(for: kind, id: id))
    }

    func clearAllAnchors() {
        values.removeAll()
    }

    private func key(for kind: OverdueAnchorKind, id: UUID) -> String {
        "\(kind.rawValue):\(id.uuidString)"
    }
}
