import CoreData
import CryptoKit
import Foundation

enum BackupServiceError: LocalizedError, Equatable {
    case folderNotSelected
    case invalidFolderAccess
    case missingBackup
    case corruptedBackup
    case unsupportedSchemaVersion(Int)
    case internalFailure

    var errorDescription: String? {
        switch self {
        case .folderNotSelected:
            return "Please choose a backup folder first."
        case .invalidFolderAccess:
            return "The selected backup folder is no longer accessible."
        case .missingBackup:
            return "No backup file was found in the selected folder."
        case .corruptedBackup:
            return "The backup file could not be read."
        case .unsupportedSchemaVersion(let version):
            return "This backup uses unsupported schema version \(version)."
        case .internalFailure:
            return "Backup operation failed unexpectedly."
        }
    }
}

final class BackupService {
    typealias SnapshotWriter = (_ data: Data, _ url: URL) throws -> Void
    typealias ArchiveWriter = (_ data: Data, _ url: URL) throws -> Void

    static let shared = BackupService(
        context: PersistenceController.shared.container.viewContext,
        makeWorkContext: PersistenceController.shared.makeBackgroundContext
    )

    private let readContext: NSManagedObjectContext
    private let makeWorkContext: () -> NSManagedObjectContext
    private let defaults: UserDefaults
    private let compressionService: CompressionService
    private let snapshotWriter: SnapshotWriter
    private let archiveWriter: ArchiveWriter
    private let bookmarkKey = "backup_folder_bookmark"
    private let folderNameKey = "backup_folder_name"
    private let lastCreatedBackupFingerprintKey = "backup_last_created_fingerprint"
    private let lastRestoredBackupFingerprintKey = "backup_last_restored_fingerprint"
    private let appName = "LoonyBear"
    private let schemaVersion = 1

    init(
        context: NSManagedObjectContext,
        makeWorkContext: @escaping () -> NSManagedObjectContext,
        defaults: UserDefaults = .standard,
        compressionService: CompressionService = CompressionService(),
        snapshotWriter: @escaping SnapshotWriter = { data, url in
            try data.write(to: url, options: .atomic)
        },
        archiveWriter: @escaping ArchiveWriter = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        readContext = context
        self.makeWorkContext = makeWorkContext
        self.defaults = defaults
        self.compressionService = compressionService
        self.snapshotWriter = snapshotWriter
        self.archiveWriter = archiveWriter
    }

    func saveFolderBookmark(for url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw BackupServiceError.invalidFolderAccess
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: bookmarkKey)
        defaults.set(url.lastPathComponent, forKey: folderNameKey)
    }

    func loadStatus() throws -> BackupStatus {
        guard hasStoredFolderReference else {
            return .empty
        }

        do {
            guard let folderURL = try resolveFolderURL() else {
                return .empty
            }

            defer {
                folderURL.stopAccessingSecurityScopedResource()
            }

            let metadata = try readMetadata(in: folderURL)
            return BackupStatus(
                folderName: folderURL.lastPathComponent,
                latestBackupText: metadata.timestampText,
                fileSizeText: metadata.fileSizeText,
                hasLatestBackup: metadata.hasLatestBackup,
                hasSelectedFolder: true,
                requiresFolderReselection: false,
                fileState: metadata.fileState
            )
        } catch let error as BackupServiceError where error == .corruptedBackup {
            return makeArchiveUnavailableStatus(folderName: storedFolderName)
        } catch {
            return makeFolderReselectionStatus()
        }
    }

    func createBackup() throws {
        ReliabilityLog.info("backup.create started")
        guard let folderURL = try resolveFolderURL() else {
            ReliabilityLog.error("backup.create failed: folder not selected")
            throw BackupServiceError.folderNotSelected
        }

        defer {
            folderURL.stopAccessingSecurityScopedResource()
        }

        do {
            let archive = try makeArchive()
            let encoded = try JSONEncoder.backupEncoder.encode(archive)
            let data = try compressionService.gzipCompress(encoded)

            try coordinateFolderWrite(at: folderURL) { coordinatedFolderURL in
                let previousURL = coordinatedFolderURL.appendingPathComponent("\(appName).previous.json.gz")
                let primaryURL = coordinatedFolderURL.appendingPathComponent("\(appName).json.gz")

                if FileManager.default.fileExists(atPath: previousURL.path) {
                    try? FileManager.default.removeItem(at: previousURL)
                }

                if FileManager.default.fileExists(atPath: primaryURL.path) {
                    try FileManager.default.moveItem(at: primaryURL, to: previousURL)
                }

                try archiveWriter(data, primaryURL)
            }
            defaults.set(Self.fingerprint(for: data), forKey: lastCreatedBackupFingerprintKey)
            ReliabilityLog.info("backup.create succeeded")
        } catch {
            ReliabilityLog.error("backup.create failed: \(error.localizedDescription)")
            throw error
        }
    }

    func restoreBackup() throws {
        ReliabilityLog.info("backup.restore started")
        guard let folderURL = try resolveFolderURL() else {
            ReliabilityLog.error("backup.restore failed: folder not selected")
            throw BackupServiceError.folderNotSelected
        }

        defer {
            folderURL.stopAccessingSecurityScopedResource()
        }

        do {
            do {
                let snapshotPayload = try makeArchive()
                do {
                    let snapshotData = try compressionService.gzipCompress(
                        JSONEncoder.backupEncoder.encode(snapshotPayload)
                    )
                    try coordinateFolderWrite(at: folderURL) { coordinatedFolderURL in
                        let snapshotURL = coordinatedFolderURL.appendingPathComponent("\(appName).restore-snapshot.json.gz")
                        try snapshotWriter(snapshotData, snapshotURL)
                    }
                    ReliabilityLog.info("backup.restore snapshot succeeded")
                } catch {
                    ReliabilityLog.error("backup.restore snapshot write failed, restore aborted: \(error.localizedDescription)")
                    throw error
                }
            } catch let error as DataIntegrityError {
                ReliabilityLog.error(
                    "backup.restore snapshot skipped because local store is corrupted: \(error.localizedDescription)"
                )
            } catch {
                ReliabilityLog.error("backup.restore snapshot payload failed, restore aborted: \(error.localizedDescription)")
                throw error
            }

            let loadedArchive = try loadPreferredArchive(in: folderURL)
            try restoreArchive(loadedArchive.archive)
            defaults.set(Self.fingerprint(for: loadedArchive.data), forKey: lastRestoredBackupFingerprintKey)
            ReliabilityLog.info("backup.restore succeeded")
        } catch {
            ReliabilityLog.error("backup.restore failed: \(error.localizedDescription)")
            throw error
        }
    }

    func restoreArchive(_ archive: BackupArchive) throws {
        guard archive.schemaVersion == schemaVersion else {
            throw BackupServiceError.unsupportedSchemaVersion(archive.schemaVersion)
        }

        do {
            try validateArchive(archive)
            ReliabilityLog.info("backup.restore archive validation passed")
        } catch {
            ReliabilityLog.error("backup.restore validation failed: \(error.localizedDescription)")
            throw error
        }

        try replaceStore(with: archive)
        restoreAppSettings(from: archive)
        UserDefaultsOverdueAnchorStore.shared.clearAllAnchors()
        ReliabilityLog.info("backup.restore store replacement succeeded")
    }

    private func resolveFolderURL() throws -> URL? {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        guard url.startAccessingSecurityScopedResource() else {
            throw BackupServiceError.invalidFolderAccess
        }

        do {
            if isStale {
                try saveFolderBookmark(for: url)
            }
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }

        return url
    }

    private var hasStoredFolderReference: Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

    private var storedFolderName: String {
        defaults.string(forKey: folderNameKey) ?? "Choose folder again"
    }

    private func makeFolderReselectionStatus() -> BackupStatus {
        BackupStatus(
            folderName: storedFolderName,
            latestBackupText: "No backups yet",
            fileSizeText: "—",
            hasLatestBackup: false,
            hasSelectedFolder: true,
            requiresFolderReselection: true,
            fileState: .none
        )
    }

    private func makeArchiveUnavailableStatus(folderName: String) -> BackupStatus {
        BackupStatus(
            folderName: folderName,
            latestBackupText: "Backup unreadable",
            fileSizeText: "—",
            hasLatestBackup: false,
            hasSelectedFolder: true,
            requiresFolderReselection: false,
            fileState: .unreadable
        )
    }

    private func makeArchive() throws -> BackupArchive {
        try performWork { context in
            var report = IntegrityReportBuilder()
            let habitsRequest = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            habitsRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

            let habits = try context.fetch(habitsRequest)
            var backupHabits: [BackupHabit] = []
            for habit in habits {
                guard
                    let id = habit.value(forKey: "id") as? UUID,
                    let type = habit.value(forKey: "typeRaw") as? String,
                    let name = habit.value(forKey: "name") as? String,
                    let startDate = habit.value(forKey: "startDate") as? Date,
                    let createdAt = habit.value(forKey: "createdAt") as? Date,
                    let updatedAt = habit.value(forKey: "updatedAt") as? Date
                else {
                    report.append(
                        area: "backup",
                        entityName: habit.entityName,
                        object: habit,
                        message: "Habit row is missing required fields."
                    )
                    continue
                }
                guard HabitType(rawValue: type) != nil else {
                    report.append(
                        area: "backup",
                        entityName: habit.entityName,
                        object: habit,
                        message: "Habit row contains invalid typeRaw."
                    )
                    continue
                }
                let historyModeRaw = (habit.value(forKey: "historyModeRaw") as? String) ?? HabitHistoryMode.scheduleBased.rawValue
                guard HabitHistoryMode(rawValue: historyModeRaw) != nil else {
                    report.append(
                        area: "backup",
                        entityName: habit.entityName,
                        object: habit,
                        message: "Habit row contains invalid historyModeRaw."
                    )
                    continue
                }

                let reminderEnabled = habit.value(forKey: "reminderEnabled") as? Bool ?? false
                let reminderTime = ReminderValidation.validatedReminderTime(
                    from: habit,
                    reminderEnabled: reminderEnabled,
                    area: "backup",
                    report: &report
                )
                guard !reminderEnabled || reminderTime != nil else {
                    report.append(
                        area: "backup",
                        entityName: habit.entityName,
                        object: habit,
                        message: "Habit backup row failed because reminder fields are corrupted."
                    )
                    continue
                }

                backupHabits.append(
                    BackupHabit(
                        id: id,
                        type: type,
                        name: name,
                        sortOrder: Int(habit.value(forKey: "sortOrder") as? Int32 ?? 0),
                        startDate: startDate,
                        historyMode: historyModeRaw,
                        reminderEnabled: reminderEnabled,
                        reminderTime: reminderTime.map { BackupReminderTime(hour: $0.hour, minute: $0.minute) },
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        version: Int(habit.value(forKey: "version") as? Int32 ?? 1)
                    )
                )
            }

            var scheduleVersions: [BackupScheduleVersion] = []
            for object in try fetchObjects(entityName: "HabitScheduleVersion", in: context) {
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    let habitId = object.value(forKey: "habitID") as? UUID,
                    let effectiveFrom = object.value(forKey: "effectiveFrom") as? Date,
                    let createdAt = object.value(forKey: "createdAt") as? Date
                else {
                    report.append(
                        area: "backup",
                        entityName: object.entityName,
                        object: object,
                        message: "Habit schedule row is missing required fields."
                    )
                    continue
                }
                guard let rule = CoreDataScheduleSupport.rule(from: object) else {
                    report.append(
                        area: "backup",
                        entityName: object.entityName,
                        object: object,
                        message: "Habit schedule row contains invalid schedule rule."
                    )
                    continue
                }

                scheduleVersions.append(
                    BackupScheduleVersion(
                        id: id,
                        habitId: habitId,
                        weekdayMask: rule.storageWeekdayMask,
                        scheduleKind: rule.kind.rawValue,
                        intervalDays: rule.intervalDays,
                        effectiveFrom: effectiveFrom,
                        createdAt: createdAt,
                        version: Int(object.value(forKey: "version") as? Int32 ?? 1)
                    )
                )
            }

            var completionRecords: [BackupCompletion] = []
            for object in try fetchObjects(entityName: "HabitCompletion", in: context) {
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    let habitId = object.value(forKey: "habitID") as? UUID,
                    let localDate = object.value(forKey: "localDate") as? Date,
                    let source = object.value(forKey: "sourceRaw") as? String,
                    let createdAt = object.value(forKey: "createdAt") as? Date
                else {
                    report.append(
                        area: "backup",
                        entityName: object.entityName,
                        object: object,
                        message: "Habit completion row is missing required fields."
                    )
                    continue
                }
                guard CompletionSource(rawValue: source) != nil else {
                    report.append(
                        area: "backup",
                        entityName: object.entityName,
                        object: object,
                        message: "Habit completion row contains invalid sourceRaw."
                    )
                    continue
                }

                completionRecords.append(
                    BackupCompletion(
                        id: id,
                        habitId: habitId,
                        localDate: localDate,
                        source: source,
                        createdAt: createdAt
                    )
                )
            }

            let ordering = backupHabits.map {
                BackupOrdering(habitId: $0.id, type: $0.type, sortOrder: $0.sortOrder)
            }

            var backupPills: [BackupPill] = []
            for pill in try fetchObjects(entityName: "Pill", in: context) {
                guard
                    let id = pill.value(forKey: "id") as? UUID,
                    let name = pill.value(forKey: "name") as? String,
                    let dosage = pill.value(forKey: "dosage") as? String,
                    let startDate = pill.value(forKey: "startDate") as? Date,
                    let createdAt = pill.value(forKey: "createdAt") as? Date,
                    let historyModeRaw = pill.value(forKey: "historyModeRaw") as? String,
                    let updatedAt = pill.value(forKey: "updatedAt") as? Date
                else {
                    report.append(
                        area: "backup",
                        entityName: pill.entityName,
                        object: pill,
                        message: "Pill row is missing required fields."
                    )
                    continue
                }
                guard PillHistoryMode(rawValue: historyModeRaw) != nil else {
                    report.append(
                        area: "backup",
                        entityName: pill.entityName,
                        object: pill,
                        message: "Pill row contains invalid historyModeRaw."
                    )
                    continue
                }

                let reminderEnabled = pill.value(forKey: "reminderEnabled") as? Bool ?? false
                let reminderTime = ReminderValidation.validatedReminderTime(
                    from: pill,
                    reminderEnabled: reminderEnabled,
                    area: "backup",
                    report: &report
                )
                guard !reminderEnabled || reminderTime != nil else {
                    report.append(
                        area: "backup",
                        entityName: pill.entityName,
                        object: pill,
                        message: "Pill backup row failed because reminder fields are corrupted."
                    )
                    continue
                }

                backupPills.append(
                    BackupPill(
                        id: id,
                        name: name,
                        dosage: dosage,
                        details: pill.value(forKey: "detailsText") as? String,
                        sortOrder: Int(pill.value(forKey: "sortOrder") as? Int32 ?? 0),
                        startDate: startDate,
                        historyMode: historyModeRaw,
                        reminderEnabled: reminderEnabled,
                        reminderTime: reminderTime.map { BackupReminderTime(hour: $0.hour, minute: $0.minute) },
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        version: Int(pill.value(forKey: "version") as? Int32 ?? 1)
                    )
                )
            }

            var pillScheduleVersions: [BackupPillScheduleVersion] = []
            for object in try fetchObjects(entityName: "PillScheduleVersion", in: context) {
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    let pillId = object.value(forKey: "pillID") as? UUID,
                    let effectiveFrom = object.value(forKey: "effectiveFrom") as? Date,
                    let createdAt = object.value(forKey: "createdAt") as? Date
                else {
                    report.append(
                        area: "backup",
                        entityName: object.entityName,
                        object: object,
                        message: "Pill schedule row is missing required fields."
                    )
                    continue
                }
                guard let rule = CoreDataScheduleSupport.rule(from: object) else {
                    report.append(
                        area: "backup",
                        entityName: object.entityName,
                        object: object,
                        message: "Pill schedule row contains invalid schedule rule."
                    )
                    continue
                }

                pillScheduleVersions.append(
                    BackupPillScheduleVersion(
                        id: id,
                        pillId: pillId,
                        weekdayMask: rule.storageWeekdayMask,
                        scheduleKind: rule.kind.rawValue,
                        intervalDays: rule.intervalDays,
                        effectiveFrom: effectiveFrom,
                        createdAt: createdAt,
                        version: Int(object.value(forKey: "version") as? Int32 ?? 1)
                    )
                )
            }

            var pillIntakeRecords: [BackupPillIntake] = []
            for object in try fetchObjects(entityName: "PillIntake", in: context) {
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    let pillId = object.value(forKey: "pillID") as? UUID,
                    let localDate = object.value(forKey: "localDate") as? Date,
                    let source = object.value(forKey: "sourceRaw") as? String,
                    let createdAt = object.value(forKey: "createdAt") as? Date
                else {
                    report.append(
                        area: "backup",
                        entityName: object.entityName,
                        object: object,
                        message: "Pill intake row is missing required fields."
                    )
                    continue
                }
                guard PillCompletionSource(rawValue: source) != nil else {
                    report.append(
                        area: "backup",
                        entityName: object.entityName,
                        object: object,
                        message: "Pill intake row contains invalid sourceRaw."
                    )
                    continue
                }

                pillIntakeRecords.append(
                    BackupPillIntake(
                        id: id,
                        pillId: pillId,
                        localDate: localDate,
                        source: source,
                        createdAt: createdAt
                    )
                )
            }

            if report.hasIssues {
                throw report.makeError(operation: "createBackup")
            }

            return BackupArchive(
                schemaVersion: schemaVersion,
                exportedAt: Date(),
                habits: backupHabits,
                scheduleVersions: scheduleVersions,
                completionRecords: completionRecords,
                ordering: ordering,
                settings: makeAppSettings(),
                pills: backupPills,
                pillScheduleVersions: pillScheduleVersions,
                pillIntakeRecords: pillIntakeRecords
            )
        }
    }

    private func replaceStore(with archive: BackupArchive) throws {
        try performWork { context in
            context.rollback()

            do {
                try deleteManagedObjects(entityName: "HabitCompletion", in: context)
                try deleteManagedObjects(entityName: "HabitScheduleVersion", in: context)
                try deleteManagedObjects(entityName: "Habit", in: context)
                try deleteManagedObjects(entityName: "PillIntake", in: context)
                try deleteManagedObjects(entityName: "PillScheduleVersion", in: context)
                try deleteManagedObjects(entityName: "Pill", in: context)

                for habit in archive.habits {
                    let object = NSEntityDescription.insertNewObject(forEntityName: "Habit", into: context)
                    object.setValue(habit.id, forKey: "id")
                    object.setValue(habit.type, forKey: "typeRaw")
                    object.setValue(habit.name, forKey: "name")
                    object.setValue(Int32(habit.sortOrder), forKey: "sortOrder")
                    object.setValue(habit.startDate, forKey: "startDate")
                    object.setValue(habit.historyMode, forKey: "historyModeRaw")
                    object.setValue(habit.reminderEnabled, forKey: "reminderEnabled")
                    object.setValue(habit.reminderTime.map { Int16($0.hour) }, forKey: "reminderHour")
                    object.setValue(habit.reminderTime.map { Int16($0.minute) }, forKey: "reminderMinute")
                    object.setValue(habit.createdAt, forKey: "createdAt")
                    object.setValue(habit.updatedAt, forKey: "updatedAt")
                    object.setValue(Int32(habit.version), forKey: "version")
                }

                let habitLookup = Dictionary(uniqueKeysWithValues: try fetchObjects(entityName: "Habit", in: context).compactMap { object -> (UUID, NSManagedObject)? in
                    guard let id = object.value(forKey: "id") as? UUID else { return nil }
                    return (id, object)
                })

                for version in archive.scheduleVersions {
                    let object = NSEntityDescription.insertNewObject(forEntityName: "HabitScheduleVersion", into: context)
                    object.setValue(version.id, forKey: "id")
                    object.setValue(version.habitId, forKey: "habitID")
                    object.setValue(Int16(version.weekdayMask), forKey: "weekdayMask")
                    object.setValue(version.scheduleKind, forKey: "scheduleKindRaw")
                    object.setValue(Int16(version.intervalDays ?? ScheduleRule.defaultIntervalDays), forKey: "intervalDays")
                    object.setValue(version.effectiveFrom, forKey: "effectiveFrom")
                    object.setValue(version.createdAt, forKey: "createdAt")
                    object.setValue(Int32(version.version), forKey: "version")
                    object.setValue(habitLookup[version.habitId], forKey: "habit")
                }

                for completion in archive.completionRecords {
                    let object = NSEntityDescription.insertNewObject(forEntityName: "HabitCompletion", into: context)
                    object.setValue(completion.id, forKey: "id")
                    object.setValue(completion.habitId, forKey: "habitID")
                    object.setValue(completion.localDate, forKey: "localDate")
                    object.setValue(completion.source, forKey: "sourceRaw")
                    object.setValue(completion.createdAt, forKey: "createdAt")
                    object.setValue(habitLookup[completion.habitId], forKey: "habit")
                }

                for pill in archive.pills {
                    let object = NSEntityDescription.insertNewObject(forEntityName: "Pill", into: context)
                    object.setValue(pill.id, forKey: "id")
                    object.setValue(pill.name, forKey: "name")
                    object.setValue(pill.dosage, forKey: "dosage")
                    object.setValue(pill.details, forKey: "detailsText")
                    object.setValue(Int32(pill.sortOrder), forKey: "sortOrder")
                    object.setValue(pill.startDate, forKey: "startDate")
                    object.setValue(pill.historyMode, forKey: "historyModeRaw")
                    object.setValue(pill.reminderEnabled, forKey: "reminderEnabled")
                    object.setValue(pill.reminderTime.map { Int16($0.hour) }, forKey: "reminderHour")
                    object.setValue(pill.reminderTime.map { Int16($0.minute) }, forKey: "reminderMinute")
                    object.setValue(pill.createdAt, forKey: "createdAt")
                    object.setValue(pill.updatedAt, forKey: "updatedAt")
                    object.setValue(Int32(pill.version), forKey: "version")
                }

                let pillLookup = Dictionary(uniqueKeysWithValues: try fetchObjects(entityName: "Pill", in: context).compactMap { object -> (UUID, NSManagedObject)? in
                    guard let id = object.value(forKey: "id") as? UUID else { return nil }
                    return (id, object)
                })

                for version in archive.pillScheduleVersions {
                    let object = NSEntityDescription.insertNewObject(forEntityName: "PillScheduleVersion", into: context)
                    object.setValue(version.id, forKey: "id")
                    object.setValue(version.pillId, forKey: "pillID")
                    object.setValue(Int16(version.weekdayMask), forKey: "weekdayMask")
                    object.setValue(version.scheduleKind, forKey: "scheduleKindRaw")
                    object.setValue(Int16(version.intervalDays ?? ScheduleRule.defaultIntervalDays), forKey: "intervalDays")
                    object.setValue(version.effectiveFrom, forKey: "effectiveFrom")
                    object.setValue(version.createdAt, forKey: "createdAt")
                    object.setValue(Int32(version.version), forKey: "version")
                    object.setValue(pillLookup[version.pillId], forKey: "pill")
                }

                for intake in archive.pillIntakeRecords {
                    let object = NSEntityDescription.insertNewObject(forEntityName: "PillIntake", into: context)
                    object.setValue(intake.id, forKey: "id")
                    object.setValue(intake.pillId, forKey: "pillID")
                    object.setValue(intake.localDate, forKey: "localDate")
                    object.setValue(intake.source, forKey: "sourceRaw")
                    object.setValue(intake.createdAt, forKey: "createdAt")
                    object.setValue(pillLookup[intake.pillId], forKey: "pill")
                }

                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }

        readContext.performAndWait {
            readContext.reset()
        }
    }

    private func makeAppSettings() -> BackupAppSettings {
        BackupAppSettings(
            appearanceMode: AppearanceMode.stored(
                rawValue: defaults.string(forKey: AppearanceMode.storageKey) ?? AppearanceMode.system.rawValue
            ).rawValue,
            appTint: AppTint.stored(
                rawValue: defaults.string(forKey: AppTint.storageKey) ?? AppTint.blue.rawValue
            ).rawValue
        )
    }

    private func restoreAppSettings(from archive: BackupArchive) {
        guard let settings = archive.settings else { return }
        defaults.set(settings.appearanceMode, forKey: AppearanceMode.storageKey)
        defaults.set(AppTint.stored(rawValue: settings.appTint).rawValue, forKey: AppTint.storageKey)
    }

    private func validateArchive(_ archive: BackupArchive) throws {
        var report = IntegrityReportBuilder()
        appendDuplicateIdentifierIssues(
            archive.habits.map(\.id),
            entityName: "BackupHabit",
            area: "backup.restore",
            report: &report
        )
        appendDuplicateIdentifierIssues(
            archive.pills.map(\.id),
            entityName: "BackupPill",
            area: "backup.restore",
            report: &report
        )
        appendDuplicateIdentifierIssues(
            archive.scheduleVersions.map(\.id),
            entityName: "BackupScheduleVersion",
            area: "backup.restore",
            report: &report
        )
        appendDuplicateIdentifierIssues(
            archive.completionRecords.map(\.id),
            entityName: "BackupCompletion",
            area: "backup.restore",
            report: &report
        )
        appendDuplicateIdentifierIssues(
            archive.pillScheduleVersions.map(\.id),
            entityName: "BackupPillScheduleVersion",
            area: "backup.restore",
            report: &report
        )
        appendDuplicateIdentifierIssues(
            archive.pillIntakeRecords.map(\.id),
            entityName: "BackupPillIntake",
            area: "backup.restore",
            report: &report
        )
        let habitIDs = Set(archive.habits.map(\.id))
        let pillIDs = Set(archive.pills.map(\.id))

        if let settings = archive.settings {
            if AppearanceMode(rawValue: settings.appearanceMode) == nil {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupAppSettings",
                    objectIdentifier: "settings",
                    message: "Backup settings contain invalid appearance mode."
                )
            }

            if !AppTint.isValidStoredRawValue(settings.appTint) {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupAppSettings",
                    objectIdentifier: "settings",
                    message: "Backup settings contain invalid app tint."
                )
            }
        }

        for habit in archive.habits {
            let objectIdentifier = "habit:\(habit.id.uuidString)"
            guard HabitType(rawValue: habit.type) != nil else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupHabit",
                    objectIdentifier: objectIdentifier,
                    message: "Habit backup payload contains invalid type."
                )
                continue
            }
            guard HabitHistoryMode(rawValue: habit.historyMode) != nil else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupHabit",
                    objectIdentifier: objectIdentifier,
                    message: "Habit backup payload contains invalid history mode."
                )
                continue
            }

            if habit.reminderEnabled {
                guard let reminderTime = habit.reminderTime else {
                    report.append(
                        area: "backup.restore",
                        entityName: "BackupHabit",
                        objectIdentifier: objectIdentifier,
                        message: "Habit backup payload is missing reminderTime while reminderEnabled is true."
                    )
                    continue
                }
                appendInvalidReminderTimeIssues(
                    reminderTime,
                    entityName: "BackupHabit",
                    objectIdentifier: objectIdentifier,
                    report: &report
                )
            }
        }

        for schedule in archive.scheduleVersions {
            let objectIdentifier = "habitSchedule:\(schedule.id.uuidString)"
            guard habitIDs.contains(schedule.habitId) else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupScheduleVersion",
                    objectIdentifier: objectIdentifier,
                    message: "Habit schedule payload references missing habit."
                )
                continue
            }
            guard ScheduleRule.make(
                kindRaw: schedule.scheduleKind,
                weekdayMask: schedule.weekdayMask,
                intervalDays: schedule.intervalDays ?? ScheduleRule.defaultIntervalDays
            ) != nil else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupScheduleVersion",
                    objectIdentifier: objectIdentifier,
                    message: "Habit schedule payload contains invalid schedule rule."
                )
                continue
            }
        }

        for completion in archive.completionRecords {
            let objectIdentifier = "habitCompletion:\(completion.id.uuidString)"
            guard habitIDs.contains(completion.habitId) else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupCompletion",
                    objectIdentifier: objectIdentifier,
                    message: "Habit completion payload references missing habit."
                )
                continue
            }
            guard CompletionSource(rawValue: completion.source) != nil else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupCompletion",
                    objectIdentifier: objectIdentifier,
                    message: "Habit completion payload contains invalid source."
                )
                continue
            }
        }

        for ordering in archive.ordering {
            let objectIdentifier = "habitOrdering:\(ordering.habitId.uuidString)"
            guard habitIDs.contains(ordering.habitId) else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupOrdering",
                    objectIdentifier: objectIdentifier,
                    message: "Habit ordering payload references missing habit."
                )
                continue
            }
            guard HabitType(rawValue: ordering.type) != nil else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupOrdering",
                    objectIdentifier: objectIdentifier,
                    message: "Habit ordering payload contains invalid type."
                )
                continue
            }
        }

        for pill in archive.pills {
            let objectIdentifier = "pill:\(pill.id.uuidString)"
            guard PillHistoryMode(rawValue: pill.historyMode) != nil else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupPill",
                    objectIdentifier: objectIdentifier,
                    message: "Pill backup payload contains invalid history mode."
                )
                continue
            }
            if pill.reminderEnabled {
                guard let reminderTime = pill.reminderTime else {
                    report.append(
                        area: "backup.restore",
                        entityName: "BackupPill",
                        objectIdentifier: objectIdentifier,
                        message: "Pill backup payload is missing reminderTime while reminderEnabled is true."
                    )
                    continue
                }
                appendInvalidReminderTimeIssues(
                    reminderTime,
                    entityName: "BackupPill",
                    objectIdentifier: objectIdentifier,
                    report: &report
                )
            }
        }

        for schedule in archive.pillScheduleVersions {
            let objectIdentifier = "pillSchedule:\(schedule.id.uuidString)"
            guard pillIDs.contains(schedule.pillId) else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupPillScheduleVersion",
                    objectIdentifier: objectIdentifier,
                    message: "Pill schedule payload references missing pill."
                )
                continue
            }
            guard ScheduleRule.make(
                kindRaw: schedule.scheduleKind,
                weekdayMask: schedule.weekdayMask,
                intervalDays: schedule.intervalDays ?? ScheduleRule.defaultIntervalDays
            ) != nil else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupPillScheduleVersion",
                    objectIdentifier: objectIdentifier,
                    message: "Pill schedule payload contains invalid schedule rule."
                )
                continue
            }
        }

        for intake in archive.pillIntakeRecords {
            let objectIdentifier = "pillIntake:\(intake.id.uuidString)"
            guard pillIDs.contains(intake.pillId) else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupPillIntake",
                    objectIdentifier: objectIdentifier,
                    message: "Pill intake payload references missing pill."
                )
                continue
            }
            guard PillCompletionSource(rawValue: intake.source) != nil else {
                report.append(
                    area: "backup.restore",
                    entityName: "BackupPillIntake",
                    objectIdentifier: objectIdentifier,
                    message: "Pill intake payload contains invalid source."
                )
                continue
            }
        }

        if report.hasIssues {
            throw report.makeError(operation: "restoreArchive")
        }
    }

    private func appendDuplicateIdentifierIssues(
        _ identifiers: [UUID],
        entityName: String,
        area: String,
        report: inout IntegrityReportBuilder
    ) {
        var seen: Set<UUID> = []
        var duplicates: Set<UUID> = []

        for identifier in identifiers {
            if !seen.insert(identifier).inserted {
                duplicates.insert(identifier)
            }
        }

        for duplicate in duplicates {
            report.append(
                area: area,
                entityName: entityName,
                objectIdentifier: duplicate.uuidString,
                message: "\(entityName) payload contains duplicate id."
            )
        }
    }

    private func appendInvalidReminderTimeIssues(
        _ reminderTime: BackupReminderTime,
        entityName: String,
        objectIdentifier: String,
        report: inout IntegrityReportBuilder
    ) {
        guard (0...23).contains(reminderTime.hour) else {
            report.append(
                area: "backup.restore",
                entityName: entityName,
                objectIdentifier: objectIdentifier,
                message: "Reminder hour must be in 0...23."
            )
            return
        }

        guard (0...59).contains(reminderTime.minute) else {
            report.append(
                area: "backup.restore",
                entityName: entityName,
                objectIdentifier: objectIdentifier,
                message: "Reminder minute must be in 0...59."
            )
            return
        }
    }

    private func readMetadata(in folderURL: URL) throws -> (timestampText: String, fileSizeText: String, hasLatestBackup: Bool, fileState: BackupFileState) {
        guard let loadedArchive = try loadPreferredArchiveFile(in: folderURL) else {
            return ("No backups yet", "—", false, .none)
        }

        let fileSize = ByteCountFormatter.string(fromByteCount: Int64(loadedArchive.data.count), countStyle: .file)
        let timestamp = loadedArchive.archive.exportedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        let fingerprint = Self.fingerprint(for: loadedArchive.data)
        return (timestamp, fileSize, true, state(forBackupFingerprint: fingerprint))
    }

    private func loadPreferredArchive(in folderURL: URL) throws -> (archive: BackupArchive, data: Data) {
        guard let loadedArchive = try loadPreferredArchiveFile(in: folderURL) else {
            throw BackupServiceError.missingBackup
        }

        return loadedArchive
    }

    private func loadPreferredArchiveFile(in folderURL: URL) throws -> (archive: BackupArchive, data: Data)? {
        try coordinateFolderRead(at: folderURL) { coordinatedFolderURL in
            let candidateURLs = [
                coordinatedFolderURL.appendingPathComponent("\(appName).json.gz"),
                coordinatedFolderURL.appendingPathComponent("\(appName).previous.json.gz"),
            ]

            var foundExistingArchive = false
            for candidateURL in candidateURLs where FileManager.default.fileExists(atPath: candidateURL.path) {
                foundExistingArchive = true

                do {
                    let data = try Data(contentsOf: candidateURL)
                    let decoded = try compressionService.gzipDecompress(data)
                    let archive = try JSONDecoder.backupDecoder.decode(BackupArchive.self, from: decoded)
                    return (archive, data)
                } catch {
                    guard isRecoverableArchiveReadError(error) else {
                        throw error
                    }
                    continue
                }
            }

            if foundExistingArchive {
                throw BackupServiceError.corruptedBackup
            }

            return nil
        }
    }

    private func state(forBackupFingerprint fingerprint: String) -> BackupFileState {
        if defaults.string(forKey: lastRestoredBackupFingerprintKey) == fingerprint {
            return .restored
        }
        if defaults.string(forKey: lastCreatedBackupFingerprintKey) == fingerprint {
            return .created
        }
        return .available
    }

    private static func fingerprint(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func isRecoverableArchiveReadError(_ error: Error) -> Bool {
        switch error {
        case is CocoaError:
            return true
        case is CompressionServiceError:
            return true
        case is DecodingError:
            return true
        default:
            return false
        }
    }

    private func fetchObjects(entityName: String, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        return try context.fetch(request)
    }

    private func deleteManagedObjects(entityName: String, in context: NSManagedObjectContext) throws {
        let objects = try fetchObjects(entityName: entityName, in: context)
        for object in objects {
            context.delete(object)
        }
    }

    private func performWork<T>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        let context = makeWorkContext()
        var result: Result<T, Error>?

        context.performAndWait {
            do {
                result = .success(try work(context))
            } catch {
                context.rollback()
                result = .failure(error)
            }
        }

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw BackupServiceError.internalFailure
        }
    }

    private func coordinateFolderRead<T>(at folderURL: URL, _ accessor: (URL) throws -> T) throws -> T {
        try coordinateFolderAccess(at: folderURL, writing: false, accessor)
    }

    private func coordinateFolderWrite<T>(at folderURL: URL, _ accessor: (URL) throws -> T) throws -> T {
        try coordinateFolderAccess(at: folderURL, writing: true, accessor)
    }

    private func coordinateFolderAccess<T>(
        at folderURL: URL,
        writing: Bool,
        _ accessor: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?

        let block: (URL) -> Void = { coordinatedURL in
            do {
                result = .success(try accessor(coordinatedURL))
            } catch {
                result = .failure(error)
            }
        }

        if writing {
            coordinator.coordinate(writingItemAt: folderURL, options: [], error: &coordinationError, byAccessor: block)
        } else {
            coordinator.coordinate(readingItemAt: folderURL, options: [], error: &coordinationError, byAccessor: block)
        }

        if let coordinationError {
            throw coordinationError
        }

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw BackupServiceError.internalFailure
        }
    }
}

private extension JSONEncoder {
    static let backupEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let backupDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
