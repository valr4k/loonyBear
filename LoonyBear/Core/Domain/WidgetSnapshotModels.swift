import Foundation

struct WidgetSnapshot: Codable {
    static let currentVersion = 1

    let version: Int
    let revision: Int64
    let generatedAt: Date
    let sections: [WidgetSectionSnapshot]

    init(
        version: Int = Self.currentVersion,
        revision: Int64? = nil,
        generatedAt: Date,
        sections: [WidgetSectionSnapshot]
    ) {
        self.version = version
        self.revision = revision ?? Self.defaultRevision(for: generatedAt)
        self.generatedAt = generatedAt
        self.sections = sections
    }

    func withRevision(_ revision: Int64) -> WidgetSnapshot {
        WidgetSnapshot(
            version: version,
            revision: revision,
            generatedAt: generatedAt,
            sections: sections
        )
    }

    private static func defaultRevision(for generatedAt: Date) -> Int64 {
        Int64((generatedAt.timeIntervalSince1970 * 1_000).rounded(.down))
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case revision
        case generatedAt
        case sections
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let generatedAt = try container.decode(Date.self, forKey: .generatedAt)

        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        revision = try container.decodeIfPresent(Int64.self, forKey: .revision) ?? Self.defaultRevision(for: generatedAt)
        self.generatedAt = generatedAt
        sections = try container.decode([WidgetSectionSnapshot].self, forKey: .sections)
    }
}

struct WidgetSectionSnapshot: Codable {
    let type: String
    let title: String
    let habits: [WidgetHabitSnapshot]
}

struct WidgetHabitSnapshot: Codable {
    let id: UUID
    let name: String
    let scheduleSummary: String
    let currentStreak: Int
    let isCompletedToday: Bool
}
