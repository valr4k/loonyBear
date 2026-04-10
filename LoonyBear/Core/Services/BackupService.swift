import CoreData
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
    static let shared = BackupService(
        context: PersistenceController.shared.container.viewContext,
        makeWorkContext: PersistenceController.shared.makeBackgroundContext
    )

    private let readContext: NSManagedObjectContext
    private let makeWorkContext: () -> NSManagedObjectContext
    private let defaults: UserDefaults
    private let compressionService: CompressionService
    private let bookmarkKey = "backup_folder_bookmark"
    private let folderNameKey = "backup_folder_name"
    private let appName = "LoonyBear"
    private let schemaVersion = 1

    init(
        context: NSManagedObjectContext,
        makeWorkContext: @escaping () -> NSManagedObjectContext,
        defaults: UserDefaults = .standard,
        compressionService: CompressionService = CompressionService()
    ) {
        readContext = context
        self.makeWorkContext = makeWorkContext
        self.defaults = defaults
        self.compressionService = compressionService
    }

    func saveFolderBookmark(for url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw BackupServiceError.invalidFolderAccess
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
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
                hasSelectedFolder: true,
                requiresFolderReselection: false
            )
        } catch BackupServiceError.invalidFolderAccess {
            return BackupStatus(
                folderName: storedFolderName,
                latestBackupText: "No backups yet",
                fileSizeText: "—",
                hasSelectedFolder: true,
                requiresFolderReselection: true
            )
        }
    }

    func createBackup() throws {
        guard let folderURL = try resolveFolderURL() else {
            throw BackupServiceError.folderNotSelected
        }

        defer {
            folderURL.stopAccessingSecurityScopedResource()
        }

        let archive = try makeArchive()
        let encoded = try JSONEncoder.backupEncoder.encode(archive)
        let data = try compressionService.gzipCompress(encoded)

        let previousURL = folderURL.appendingPathComponent("\(appName).previous.json.gz")
        let primaryURL = folderURL.appendingPathComponent("\(appName).json.gz")

        if FileManager.default.fileExists(atPath: previousURL.path) {
            try? FileManager.default.removeItem(at: previousURL)
        }

        if FileManager.default.fileExists(atPath: primaryURL.path) {
            try FileManager.default.moveItem(at: primaryURL, to: previousURL)
        }

        try data.write(to: primaryURL, options: .atomic)
    }

    func restoreBackup() throws {
        guard let folderURL = try resolveFolderURL() else {
            throw BackupServiceError.folderNotSelected
        }

        defer {
            folderURL.stopAccessingSecurityScopedResource()
        }

        let snapshotURL = folderURL.appendingPathComponent("\(appName).restore-snapshot.json.gz")
        let snapshot = try compressionService.gzipCompress(JSONEncoder.backupEncoder.encode(makeArchive()))
        try snapshot.write(to: snapshotURL, options: .atomic)

        let archive = try loadPreferredArchive(in: folderURL)
        try restoreArchive(archive)
    }

    func restoreArchive(_ archive: BackupArchive) throws {
        guard archive.schemaVersion == schemaVersion else {
            throw BackupServiceError.unsupportedSchemaVersion(archive.schemaVersion)
        }

        try replaceStore(with: archive)
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

        if isStale {
            try saveFolderBookmark(for: url)
        }

        return url
    }

    private var hasStoredFolderReference: Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

    private var storedFolderName: String {
        defaults.string(forKey: folderNameKey) ?? "Choose folder again"
    }

    private func makeArchive() throws -> BackupArchive {
        try performWork { context in
            let habitsRequest = NSFetchRequest<NSManagedObject>(entityName: "Habit")
            habitsRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

            let habits = try context.fetch(habitsRequest)

            let backupHabits = habits.compactMap { habit -> BackupHabit? in
                guard
                    let id = habit.value(forKey: "id") as? UUID,
                    let type = habit.value(forKey: "typeRaw") as? String,
                    let name = habit.value(forKey: "name") as? String,
                    let startDate = habit.value(forKey: "startDate") as? Date,
                    let createdAt = habit.value(forKey: "createdAt") as? Date,
                    let updatedAt = habit.value(forKey: "updatedAt") as? Date
                else {
                    return nil
                }

                let reminderEnabled = habit.value(forKey: "reminderEnabled") as? Bool ?? false
                let reminderHour = Int(habit.value(forKey: "reminderHour") as? Int16 ?? 0)
                let reminderMinute = Int(habit.value(forKey: "reminderMinute") as? Int16 ?? 0)

                return BackupHabit(
                    id: id,
                    type: type,
                    name: name,
                    sortOrder: Int(habit.value(forKey: "sortOrder") as? Int32 ?? 0),
                    startDate: startDate,
                    reminderEnabled: reminderEnabled,
                    reminderTime: reminderEnabled ? BackupReminderTime(hour: reminderHour, minute: reminderMinute) : nil,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    version: Int(habit.value(forKey: "version") as? Int32 ?? 1)
                )
            }

            let scheduleVersions = try fetchObjects(entityName: "HabitScheduleVersion", in: context).compactMap { object -> BackupScheduleVersion? in
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    let habitId = object.value(forKey: "habitID") as? UUID,
                    let effectiveFrom = object.value(forKey: "effectiveFrom") as? Date,
                    let createdAt = object.value(forKey: "createdAt") as? Date
                else {
                    return nil
                }

                return BackupScheduleVersion(
                    id: id,
                    habitId: habitId,
                    weekdayMask: Int(object.value(forKey: "weekdayMask") as? Int16 ?? 0),
                    effectiveFrom: effectiveFrom,
                    createdAt: createdAt,
                    version: Int(object.value(forKey: "version") as? Int32 ?? 1)
                )
            }

            let completionRecords = try fetchObjects(entityName: "HabitCompletion", in: context).compactMap { object -> BackupCompletion? in
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    let habitId = object.value(forKey: "habitID") as? UUID,
                    let localDate = object.value(forKey: "localDate") as? Date,
                    let source = object.value(forKey: "sourceRaw") as? String,
                    let createdAt = object.value(forKey: "createdAt") as? Date
                else {
                    return nil
                }

                return BackupCompletion(
                    id: id,
                    habitId: habitId,
                    localDate: localDate,
                    source: source,
                    createdAt: createdAt
                )
            }

            let ordering = backupHabits.map {
                BackupOrdering(habitId: $0.id, type: $0.type, sortOrder: $0.sortOrder)
            }

            let backupPills = try fetchObjects(entityName: "Pill", in: context).compactMap { pill -> BackupPill? in
                guard
                    let id = pill.value(forKey: "id") as? UUID,
                    let name = pill.value(forKey: "name") as? String,
                    let dosage = pill.value(forKey: "dosage") as? String,
                    let startDate = pill.value(forKey: "startDate") as? Date,
                    let createdAt = pill.value(forKey: "createdAt") as? Date,
                    let updatedAt = pill.value(forKey: "updatedAt") as? Date
                else {
                    return nil
                }

                let reminderEnabled = pill.value(forKey: "reminderEnabled") as? Bool ?? false
                let reminderHour = Int(pill.value(forKey: "reminderHour") as? Int16 ?? 0)
                let reminderMinute = Int(pill.value(forKey: "reminderMinute") as? Int16 ?? 0)

                return BackupPill(
                    id: id,
                    name: name,
                    dosage: dosage,
                    details: pill.value(forKey: "detailsText") as? String,
                    sortOrder: Int(pill.value(forKey: "sortOrder") as? Int32 ?? 0),
                    startDate: startDate,
                    reminderEnabled: reminderEnabled,
                    reminderTime: reminderEnabled ? BackupReminderTime(hour: reminderHour, minute: reminderMinute) : nil,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    version: Int(pill.value(forKey: "version") as? Int32 ?? 1)
                )
            }

            let pillScheduleVersions = try fetchObjects(entityName: "PillScheduleVersion", in: context).compactMap { object -> BackupPillScheduleVersion? in
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    let pillId = object.value(forKey: "pillID") as? UUID,
                    let effectiveFrom = object.value(forKey: "effectiveFrom") as? Date,
                    let createdAt = object.value(forKey: "createdAt") as? Date
                else {
                    return nil
                }

                return BackupPillScheduleVersion(
                    id: id,
                    pillId: pillId,
                    weekdayMask: Int(object.value(forKey: "weekdayMask") as? Int16 ?? 0),
                    effectiveFrom: effectiveFrom,
                    createdAt: createdAt,
                    version: Int(object.value(forKey: "version") as? Int32 ?? 1)
                )
            }

            let pillIntakeRecords = try fetchObjects(entityName: "PillIntake", in: context).compactMap { object -> BackupPillIntake? in
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    let pillId = object.value(forKey: "pillID") as? UUID,
                    let localDate = object.value(forKey: "localDate") as? Date,
                    let source = object.value(forKey: "sourceRaw") as? String,
                    let createdAt = object.value(forKey: "createdAt") as? Date
                else {
                    return nil
                }

                return BackupPillIntake(
                    id: id,
                    pillId: pillId,
                    localDate: localDate,
                    source: source,
                    createdAt: createdAt
                )
            }

            return BackupArchive(
                schemaVersion: schemaVersion,
                exportedAt: Date(),
                habits: backupHabits,
                scheduleVersions: scheduleVersions,
                completionRecords: completionRecords,
                ordering: ordering,
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

    private func readMetadata(in folderURL: URL) throws -> (timestampText: String, fileSizeText: String) {
        guard let loadedArchive = try loadPreferredArchiveFile(in: folderURL) else {
            return ("No backups yet", "—")
        }

        let fileSize = ByteCountFormatter.string(fromByteCount: Int64(loadedArchive.data.count), countStyle: .file)
        let timestamp = loadedArchive.archive.exportedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return (timestamp, fileSize)
    }

    private func loadPreferredArchive(in folderURL: URL) throws -> BackupArchive {
        guard let loadedArchive = try loadPreferredArchiveFile(in: folderURL) else {
            throw BackupServiceError.missingBackup
        }

        return loadedArchive.archive
    }

    private func loadPreferredArchiveFile(in folderURL: URL) throws -> (archive: BackupArchive, data: Data)? {
        let candidateURLs = [
            folderURL.appendingPathComponent("\(appName).json.gz"),
            folderURL.appendingPathComponent("\(appName).previous.json.gz"),
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
