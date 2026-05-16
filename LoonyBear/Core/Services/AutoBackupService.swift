import Combine
import Foundation

struct AutoBackupToken {
    fileprivate let dirtyGeneration: Int
}

@MainActor
final class AutoBackupService: ObservableObject {
    static let shared = AutoBackupService()

    static let enabledKey = "backup_auto_enabled"
    static let dirtyKey = "backup_auto_dirty"
    static let dirtyGenerationKey = "backup_auto_dirty_generation"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isDirty: Bool
    @Published private(set) var isBackingUp = false

    private let backupService: BackupService
    private let defaults: UserDefaults
    private let debounceDuration: Duration
    private var dirtyGeneration: Int
    private var debounceTask: Task<Void, Never>?
    private var activeExternalBackupCount = 0
    private var notificationObservers: [NSObjectProtocol] = []

    init(
        backupService: BackupService? = nil,
        defaults: UserDefaults = .standard,
        debounceDuration: Duration = .seconds(20)
    ) {
        self.backupService = backupService ?? .shared
        self.defaults = defaults
        self.debounceDuration = debounceDuration
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        isDirty = defaults.bool(forKey: Self.dirtyKey)
        dirtyGeneration = defaults.integer(forKey: Self.dirtyGenerationKey)
        observeStoreMutations()
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        debounceTask?.cancel()
    }

    func setEnabled(_ enabled: Bool) {
        let resolvedEnabled = enabled && canWriteAutomaticBackup()
        isEnabled = resolvedEnabled
        defaults.set(resolvedEnabled, forKey: Self.enabledKey)

        if resolvedEnabled {
            scheduleDebouncedBackup(reason: "auto-backup-enabled")
        } else {
            debounceTask?.cancel()
            debounceTask = nil
        }
    }

    func markDirty(reason: String) {
        dirtyGeneration += 1
        isDirty = true
        persistDirtyState()
        ReliabilityLog.info("backup.auto.dirty reason=\(reason)")
        scheduleDebouncedBackup(reason: reason)
    }

    func handleStartup() {
        guard ensureCanWriteAutomaticBackup() else { return }
        runBackupIfNeeded(reason: "startup")
    }

    func handleForeground() {
        guard ensureCanWriteAutomaticBackup() else { return }
        runBackupIfNeeded(reason: "foreground")
    }

    func handleBackground() {
        debounceTask?.cancel()
        debounceTask = nil
        guard ensureCanWriteAutomaticBackup() else { return }
        runBackupIfNeeded(reason: "background")
    }

    func beginExternalBackup() -> AutoBackupToken {
        debounceTask?.cancel()
        debounceTask = nil
        activeExternalBackupCount += 1
        return AutoBackupToken(dirtyGeneration: dirtyGeneration)
    }

    func completeExternalBackup(
        _ token: AutoBackupToken,
        succeeded: Bool,
        clearsDirtyRegardless: Bool = false,
        schedulesPendingDirty: Bool = true
    ) {
        activeExternalBackupCount = max(0, activeExternalBackupCount - 1)

        guard succeeded else { return }

        if clearsDirtyRegardless {
            clearDirty()
        } else {
            clearDirtyIfUnchanged(since: token.dirtyGeneration)
        }
        if isDirty, schedulesPendingDirty {
            scheduleDebouncedBackup(reason: "external-backup-completed")
        }
    }

    private func observeStoreMutations() {
        let names: [Notification.Name] = [
            .habitStoreDidChange,
            .pillStoreDidChange,
            .eventStoreDidChange,
        ]

        notificationObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let reason = notification.name.rawValue
                Task { @MainActor [weak self, reason] in
                    self?.markDirty(reason: reason)
                }
            }
        }
    }

    private func scheduleDebouncedBackup(reason: String) {
        guard isEnabled, isDirty else { return }
        guard !isBackingUp, activeExternalBackupCount == 0 else { return }
        guard ensureCanWriteAutomaticBackup() else { return }

        debounceTask?.cancel()
        let debounceDuration = self.debounceDuration
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.runBackupIfNeeded(reason: "debounced-\(reason)")
            }
        }
    }

    private func runBackupIfNeeded(reason: String) {
        guard isEnabled, isDirty else { return }
        guard !isBackingUp, activeExternalBackupCount == 0 else { return }
        guard ensureCanWriteAutomaticBackup() else { return }

        debounceTask?.cancel()
        debounceTask = nil
        isBackingUp = true
        let generationAtStart = dirtyGeneration
        ReliabilityLog.info("backup.auto.create started reason=\(reason)")

        Task { [weak self] in
            guard let self else { return }
            let result = await self.runCreateBackupInBackground()

            await MainActor.run {
                self.isBackingUp = false

                switch result {
                case .success:
                    self.clearDirtyIfUnchanged(since: generationAtStart)
                    ReliabilityLog.info("backup.auto.create succeeded reason=\(reason)")
                    NotificationCenter.default.post(name: .backupStatusDidChange, object: nil)

                    if self.isDirty {
                        self.scheduleDebouncedBackup(reason: "post-success-dirty")
                    }
                case .failure(let error):
                    ReliabilityLog.error("backup.auto.create failed reason=\(reason): \(error.localizedDescription)")
                }
            }
        }
    }

    private func clearDirtyIfUnchanged(since generationAtStart: Int) {
        guard dirtyGeneration == generationAtStart else { return }
        clearDirty()
    }

    private func clearDirty() {
        isDirty = false
        persistDirtyState()
    }

    private func ensureCanWriteAutomaticBackup() -> Bool {
        guard isEnabled else { return false }
        guard canWriteAutomaticBackup() else {
            setEnabled(false)
            ReliabilityLog.info("backup.auto.disabled reason=backup-not-trusted")
            return false
        }
        return true
    }

    private func canWriteAutomaticBackup() -> Bool {
        do {
            return try backupService.loadStatus().allowsAutomaticBackup
        } catch {
            return false
        }
    }

    private func persistDirtyState() {
        defaults.set(isDirty, forKey: Self.dirtyKey)
        defaults.set(dirtyGeneration, forKey: Self.dirtyGenerationKey)
    }

    private func runCreateBackupInBackground() async -> Result<Void, Error> {
        let backupService = self.backupService
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try backupService.createBackup()
                    continuation.resume(returning: .success(()))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }
}
