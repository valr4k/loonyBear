import Foundation

struct BackupArchive: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let habits: [BackupHabit]
    let scheduleVersions: [BackupScheduleVersion]
    let completionRecords: [BackupCompletion]
    let ordering: [BackupOrdering]
    let pills: [BackupPill]
    let pillScheduleVersions: [BackupPillScheduleVersion]
    let pillIntakeRecords: [BackupPillIntake]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case habits
        case scheduleVersions
        case completionRecords
        case ordering
        case pills
        case pillScheduleVersions
        case pillIntakeRecords
    }

    init(
        schemaVersion: Int,
        exportedAt: Date,
        habits: [BackupHabit],
        scheduleVersions: [BackupScheduleVersion],
        completionRecords: [BackupCompletion],
        ordering: [BackupOrdering],
        pills: [BackupPill] = [],
        pillScheduleVersions: [BackupPillScheduleVersion] = [],
        pillIntakeRecords: [BackupPillIntake] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.habits = habits
        self.scheduleVersions = scheduleVersions
        self.completionRecords = completionRecords
        self.ordering = ordering
        self.pills = pills
        self.pillScheduleVersions = pillScheduleVersions
        self.pillIntakeRecords = pillIntakeRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        habits = try container.decode([BackupHabit].self, forKey: .habits)
        scheduleVersions = try container.decode([BackupScheduleVersion].self, forKey: .scheduleVersions)
        completionRecords = try container.decode([BackupCompletion].self, forKey: .completionRecords)
        ordering = try container.decode([BackupOrdering].self, forKey: .ordering)
        pills = try container.decodeIfPresent([BackupPill].self, forKey: .pills) ?? []
        pillScheduleVersions = try container.decodeIfPresent([BackupPillScheduleVersion].self, forKey: .pillScheduleVersions) ?? []
        pillIntakeRecords = try container.decodeIfPresent([BackupPillIntake].self, forKey: .pillIntakeRecords) ?? []
    }
}

struct BackupHabit: Codable {
    let id: UUID
    let type: String
    let name: String
    let sortOrder: Int
    let startDate: Date
    let reminderEnabled: Bool
    let reminderTime: BackupReminderTime?
    let createdAt: Date
    let updatedAt: Date
    let version: Int
}

struct BackupScheduleVersion: Codable {
    let id: UUID
    let habitId: UUID
    let weekdayMask: Int
    let effectiveFrom: Date
    let createdAt: Date
    let version: Int
}

struct BackupCompletion: Codable {
    let id: UUID
    let habitId: UUID
    let localDate: Date
    let source: String
    let createdAt: Date
}

struct BackupOrdering: Codable {
    let habitId: UUID
    let type: String
    let sortOrder: Int
}

struct BackupReminderTime: Codable {
    let hour: Int
    let minute: Int
}

struct BackupPill: Codable {
    let id: UUID
    let name: String
    let dosage: String
    let details: String?
    let sortOrder: Int
    let startDate: Date
    let reminderEnabled: Bool
    let reminderTime: BackupReminderTime?
    let createdAt: Date
    let updatedAt: Date
    let version: Int
}

struct BackupPillScheduleVersion: Codable {
    let id: UUID
    let pillId: UUID
    let weekdayMask: Int
    let effectiveFrom: Date
    let createdAt: Date
    let version: Int
}

struct BackupPillIntake: Codable {
    let id: UUID
    let pillId: UUID
    let localDate: Date
    let source: String
    let createdAt: Date
}

struct BackupStatus: Equatable {
    let folderName: String
    let latestBackupText: String
    let fileSizeText: String
    let hasSelectedFolder: Bool
    let requiresFolderReselection: Bool

    static let empty = BackupStatus(
        folderName: "Choose folder",
        latestBackupText: "No backups yet",
        fileSizeText: "—",
        hasSelectedFolder: false,
        requiresFolderReselection: false
    )
}
