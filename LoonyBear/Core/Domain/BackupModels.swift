import Foundation

struct BackupArchive: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let habits: [BackupHabit]
    let scheduleVersions: [BackupScheduleVersion]
    let completionRecords: [BackupCompletion]
    let habitHistoryBuckets: [BackupHabitHistoryBucket]
    let habitHistoryRanges: [BackupHabitHistoryRange]
    let ordering: [BackupOrdering]
    let settings: BackupAppSettings?
    let pills: [BackupPill]
    let pillScheduleVersions: [BackupPillScheduleVersion]
    let pillIntakeRecords: [BackupPillIntake]
    let pillHistoryBuckets: [BackupPillHistoryBucket]
    let pillHistoryRanges: [BackupPillHistoryRange]
    let events: [BackupEvent]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case habits
        case scheduleVersions
        case completionRecords
        case habitHistoryBuckets
        case habitHistoryRanges
        case ordering
        case settings
        case pills
        case pillScheduleVersions
        case pillIntakeRecords
        case pillHistoryBuckets
        case pillHistoryRanges
        case events
    }

    init(
        schemaVersion: Int,
        exportedAt: Date,
        habits: [BackupHabit],
        scheduleVersions: [BackupScheduleVersion],
        completionRecords: [BackupCompletion] = [],
        habitHistoryBuckets: [BackupHabitHistoryBucket] = [],
        habitHistoryRanges: [BackupHabitHistoryRange] = [],
        ordering: [BackupOrdering],
        settings: BackupAppSettings? = nil,
        pills: [BackupPill] = [],
        pillScheduleVersions: [BackupPillScheduleVersion] = [],
        pillIntakeRecords: [BackupPillIntake] = [],
        pillHistoryBuckets: [BackupPillHistoryBucket] = [],
        pillHistoryRanges: [BackupPillHistoryRange] = [],
        events: [BackupEvent] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.habits = habits
        self.scheduleVersions = scheduleVersions
        self.completionRecords = completionRecords
        self.habitHistoryBuckets = habitHistoryBuckets
        self.habitHistoryRanges = habitHistoryRanges
        self.ordering = ordering
        self.settings = settings
        self.pills = pills
        self.pillScheduleVersions = pillScheduleVersions
        self.pillIntakeRecords = pillIntakeRecords
        self.pillHistoryBuckets = pillHistoryBuckets
        self.pillHistoryRanges = pillHistoryRanges
        self.events = events
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        habits = try container.decode([BackupHabit].self, forKey: .habits)
        scheduleVersions = try container.decode([BackupScheduleVersion].self, forKey: .scheduleVersions)
        completionRecords = try container.decodeIfPresent([BackupCompletion].self, forKey: .completionRecords) ?? []
        habitHistoryBuckets = try container.decodeIfPresent([BackupHabitHistoryBucket].self, forKey: .habitHistoryBuckets) ?? []
        habitHistoryRanges = try container.decodeIfPresent([BackupHabitHistoryRange].self, forKey: .habitHistoryRanges) ?? []
        ordering = try container.decode([BackupOrdering].self, forKey: .ordering)
        settings = try container.decodeIfPresent(BackupAppSettings.self, forKey: .settings)
        pills = try container.decodeIfPresent([BackupPill].self, forKey: .pills) ?? []
        pillScheduleVersions = try container.decodeIfPresent([BackupPillScheduleVersion].self, forKey: .pillScheduleVersions) ?? []
        pillIntakeRecords = try container.decodeIfPresent([BackupPillIntake].self, forKey: .pillIntakeRecords) ?? []
        pillHistoryBuckets = try container.decodeIfPresent([BackupPillHistoryBucket].self, forKey: .pillHistoryBuckets) ?? []
        pillHistoryRanges = try container.decodeIfPresent([BackupPillHistoryRange].self, forKey: .pillHistoryRanges) ?? []
        events = try container.decodeIfPresent([BackupEvent].self, forKey: .events) ?? []
    }
}

struct BackupAppSettings: Codable, Equatable {
    let appearanceMode: String
    let appTint: String
}

struct BackupEvent: Codable {
    let id: UUID
    let name: String
    let mode: String
    let date: Date
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let version: Int
}

struct BackupHabit: Codable {
    let id: UUID
    let type: String
    let name: String
    let sortOrder: Int
    let startDate: Date
    let activeFrom: Date?
    let endDate: Date?
    let historyMode: String
    let isArchived: Bool
    let archivedAt: Date?
    let reminderEnabled: Bool
    let reminderTime: BackupReminderTime?
    let createdAt: Date
    let updatedAt: Date
    let version: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case sortOrder
        case startDate
        case activeFrom
        case endDate
        case historyMode
        case isArchived
        case archivedAt
        case reminderEnabled
        case reminderTime
        case createdAt
        case updatedAt
        case version
    }

    init(
        id: UUID,
        type: String,
        name: String,
        sortOrder: Int,
        startDate: Date,
        activeFrom: Date? = nil,
        endDate: Date? = nil,
        historyMode: String = HabitHistoryMode.scheduleBased.rawValue,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        reminderEnabled: Bool,
        reminderTime: BackupReminderTime?,
        createdAt: Date,
        updatedAt: Date,
        version: Int
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.sortOrder = sortOrder
        self.startDate = startDate
        self.activeFrom = activeFrom
        self.endDate = endDate
        self.historyMode = historyMode
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        startDate = try container.decode(Date.self, forKey: .startDate)
        activeFrom = try container.decodeIfPresent(Date.self, forKey: .activeFrom)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        historyMode = try container.decodeIfPresent(String.self, forKey: .historyMode) ?? HabitHistoryMode.scheduleBased.rawValue
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        reminderEnabled = try container.decode(Bool.self, forKey: .reminderEnabled)
        reminderTime = try container.decodeIfPresent(BackupReminderTime.self, forKey: .reminderTime)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        version = try container.decode(Int.self, forKey: .version)
    }
}

struct BackupScheduleVersion: Codable {
    let id: UUID
    let habitId: UUID
    let weekdayMask: Int
    let scheduleKind: String
    let intervalDays: Int?
    let effectiveFrom: Date
    let createdAt: Date
    let version: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case habitId
        case weekdayMask
        case scheduleKind
        case intervalDays
        case effectiveFrom
        case createdAt
        case version
    }

    init(
        id: UUID,
        habitId: UUID,
        weekdayMask: Int,
        scheduleKind: String = ScheduleRule.Kind.weekly.rawValue,
        intervalDays: Int? = nil,
        effectiveFrom: Date,
        createdAt: Date,
        version: Int
    ) {
        self.id = id
        self.habitId = habitId
        self.weekdayMask = weekdayMask
        self.scheduleKind = scheduleKind
        self.intervalDays = intervalDays
        self.effectiveFrom = effectiveFrom
        self.createdAt = createdAt
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        habitId = try container.decode(UUID.self, forKey: .habitId)
        weekdayMask = try container.decode(Int.self, forKey: .weekdayMask)
        scheduleKind = try container.decodeIfPresent(String.self, forKey: .scheduleKind) ?? ScheduleRule.Kind.weekly.rawValue
        intervalDays = try container.decodeIfPresent(Int.self, forKey: .intervalDays)
        effectiveFrom = try container.decode(Date.self, forKey: .effectiveFrom)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        version = try container.decode(Int.self, forKey: .version)
    }
}

struct BackupCompletion: Codable {
    let id: UUID
    let habitId: UUID
    let localDate: Date
    let source: String
    let createdAt: Date
}

struct BackupHabitHistoryBucket: Codable {
    let id: UUID
    let habitId: UUID
    let yearMonthKey: Int
    let positiveMask: Int64
    let skippedMask: Int64
    let archivedMask: Int64
    let positiveCount: Int
    let skippedCount: Int
    let archivedCount: Int
    let createdAt: Date
    let updatedAt: Date
}

struct BackupHabitHistoryRange: Codable {
    let id: UUID
    let habitId: UUID
    let startDate: Date
    let endDate: Date
    let state: String
    let useScheduleForHistory: Bool
    let scheduleKind: String
    let weekdayMask: Int
    let intervalDays: Int
    let anchorDate: Date
    let count: Int
    let createdAt: Date
    let updatedAt: Date
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
    let activeFrom: Date?
    let endDate: Date?
    let historyMode: String
    let isArchived: Bool
    let archivedAt: Date?
    let reminderEnabled: Bool
    let reminderTime: BackupReminderTime?
    let createdAt: Date
    let updatedAt: Date
    let version: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case dosage
        case details
        case sortOrder
        case startDate
        case activeFrom
        case endDate
        case historyMode
        case isArchived
        case archivedAt
        case reminderEnabled
        case reminderTime
        case createdAt
        case updatedAt
        case version
    }

    init(
        id: UUID,
        name: String,
        dosage: String,
        details: String?,
        sortOrder: Int,
        startDate: Date,
        activeFrom: Date? = nil,
        endDate: Date? = nil,
        historyMode: String,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        reminderEnabled: Bool,
        reminderTime: BackupReminderTime?,
        createdAt: Date,
        updatedAt: Date,
        version: Int
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.details = details
        self.sortOrder = sortOrder
        self.startDate = startDate
        self.activeFrom = activeFrom
        self.endDate = endDate
        self.historyMode = historyMode
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        dosage = try container.decode(String.self, forKey: .dosage)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        startDate = try container.decode(Date.self, forKey: .startDate)
        activeFrom = try container.decodeIfPresent(Date.self, forKey: .activeFrom)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        historyMode = try container.decodeIfPresent(String.self, forKey: .historyMode) ?? PillHistoryMode.scheduleBased.rawValue
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        reminderEnabled = try container.decode(Bool.self, forKey: .reminderEnabled)
        reminderTime = try container.decodeIfPresent(BackupReminderTime.self, forKey: .reminderTime)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        version = try container.decode(Int.self, forKey: .version)
    }
}

struct BackupPillScheduleVersion: Codable {
    let id: UUID
    let pillId: UUID
    let weekdayMask: Int
    let scheduleKind: String
    let intervalDays: Int?
    let effectiveFrom: Date
    let createdAt: Date
    let version: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case pillId
        case weekdayMask
        case scheduleKind
        case intervalDays
        case effectiveFrom
        case createdAt
        case version
    }

    init(
        id: UUID,
        pillId: UUID,
        weekdayMask: Int,
        scheduleKind: String = ScheduleRule.Kind.weekly.rawValue,
        intervalDays: Int? = nil,
        effectiveFrom: Date,
        createdAt: Date,
        version: Int
    ) {
        self.id = id
        self.pillId = pillId
        self.weekdayMask = weekdayMask
        self.scheduleKind = scheduleKind
        self.intervalDays = intervalDays
        self.effectiveFrom = effectiveFrom
        self.createdAt = createdAt
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pillId = try container.decode(UUID.self, forKey: .pillId)
        weekdayMask = try container.decode(Int.self, forKey: .weekdayMask)
        scheduleKind = try container.decodeIfPresent(String.self, forKey: .scheduleKind) ?? ScheduleRule.Kind.weekly.rawValue
        intervalDays = try container.decodeIfPresent(Int.self, forKey: .intervalDays)
        effectiveFrom = try container.decode(Date.self, forKey: .effectiveFrom)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        version = try container.decode(Int.self, forKey: .version)
    }
}

struct BackupPillIntake: Codable {
    let id: UUID
    let pillId: UUID
    let localDate: Date
    let source: String
    let createdAt: Date
}

struct BackupPillHistoryBucket: Codable {
    let id: UUID
    let pillId: UUID
    let yearMonthKey: Int
    let positiveMask: Int64
    let skippedMask: Int64
    let archivedMask: Int64
    let positiveCount: Int
    let skippedCount: Int
    let archivedCount: Int
    let createdAt: Date
    let updatedAt: Date
}

struct BackupPillHistoryRange: Codable {
    let id: UUID
    let pillId: UUID
    let startDate: Date
    let endDate: Date
    let state: String
    let useScheduleForHistory: Bool
    let scheduleKind: String
    let weekdayMask: Int
    let intervalDays: Int
    let anchorDate: Date
    let count: Int
    let createdAt: Date
    let updatedAt: Date
}

struct BackupStatus: Equatable {
    let folderName: String
    let latestBackupText: String
    let fileSizeText: String
    let hasLatestBackup: Bool
    let hasSelectedFolder: Bool
    let requiresFolderReselection: Bool
    let fileState: BackupFileState

    var hasUsableFolder: Bool {
        hasSelectedFolder && !requiresFolderReselection
    }

    static let empty = BackupStatus(
        folderName: "Choose folder",
        latestBackupText: "No backups yet",
        fileSizeText: "—",
        hasLatestBackup: false,
        hasSelectedFolder: false,
        requiresFolderReselection: false,
        fileState: .none
    )
}

enum BackupFileState: Equatable {
    case none
    case available
    case created
    case restored
    case unreadable
}
