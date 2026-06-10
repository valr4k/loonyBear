import Foundation

enum UserFacingErrorMessage {
    static func text(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return "Couldn’t complete the action."
    }
}

@MainActor
final class AppStateWriteCoordinator {
    private let name: String
    private let writeQueue: OperationQueue

    init(name: String) {
        self.name = name
        let queue = OperationQueue()
        queue.name = name
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        writeQueue = queue
    }

    func performWriteOperation<T>(
        marksDataDirty: Bool = true,
        _ operation: @escaping () throws -> T
    ) async throws -> T {
        let result: T = try await PerformanceLog.measure(
            "appstate.write.operation",
            metadata: "queue=\(name)"
        ) {
            try await withCheckedThrowingContinuation { continuation in
                writeQueue.addOperation {
                    do {
                        continuation.resume(returning: try operation())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        if marksDataDirty {
            PerformanceLog.measure("appstate.autobackup.markDirty", metadata: "queue=\(name)") {
                AutoBackupService.shared.markDirty(reason: "app-state-write")
            }
        }
        return result
    }

    func performMutation(
        refresh: @escaping () -> Void,
        setError: @escaping (String?) -> Void,
        refreshOnFailure: Bool = false,
        mutation: @escaping () throws -> Void
    ) async -> Bool {
        do {
            try await performWriteOperation(mutation)
            PerformanceLog.measure("appstate.refresh.afterMutation") {
                refresh()
            }
            setError(nil)
            return true
        } catch {
            if refreshOnFailure {
                PerformanceLog.measure("appstate.refresh.afterMutationFailure") {
                    refresh()
                }
            }
            setError(UserFacingErrorMessage.text(for: error))
            return false
        }
    }

    func performMutation(
        refresh: @escaping () -> Void,
        setError: @escaping (String?) -> Void,
        refreshOnFailure: Bool = false,
        mutation: @escaping () throws -> Bool
    ) async -> Bool {
        do {
            let didMutate = try await performWriteOperation(marksDataDirty: false, mutation)
            if didMutate {
                PerformanceLog.measure("appstate.autobackup.markDirty", metadata: "queue=\(name)") {
                    AutoBackupService.shared.markDirty(reason: "app-state-write")
                }
            }
            PerformanceLog.measure("appstate.refresh.afterMutation") {
                refresh()
            }
            setError(nil)
            return didMutate
        } catch {
            if refreshOnFailure {
                PerformanceLog.measure("appstate.refresh.afterMutationFailure") {
                    refresh()
                }
            }
            setError(UserFacingErrorMessage.text(for: error))
            return false
        }
    }

    func performThrowingMutation<T>(
        refresh: @escaping () -> Void = {},
        setError: @escaping (String?) -> Void,
        refreshOnFailure: Bool = false,
        marksDataDirtyWhen shouldMarkDataDirty: @escaping (T) -> Bool = { _ in true },
        operation: @escaping () throws -> T
    ) async throws -> T {
        do {
            let result = try await performWriteOperation(marksDataDirty: false, operation)
            if shouldMarkDataDirty(result) {
                PerformanceLog.measure("appstate.autobackup.markDirty", metadata: "queue=\(name)") {
                    AutoBackupService.shared.markDirty(reason: "app-state-write")
                }
            }
            PerformanceLog.measure("appstate.refresh.afterMutation") {
                refresh()
            }
            setError(nil)
            return result
        } catch {
            if refreshOnFailure {
                PerformanceLog.measure("appstate.refresh.afterMutationFailure") {
                    refresh()
                }
            }
            setError(UserFacingErrorMessage.text(for: error))
            throw error
        }
    }

    func performReconciliation(
        logPrefix: String,
        refresh: @escaping () -> Void,
        setError: @escaping (String?) -> Void,
        afterRefresh: @escaping () -> Void,
        operation: @escaping () throws -> Int
    ) async {
        var reconciliationErrorMessage: String?

        do {
            let finalizedDays = try await performWriteOperation(marksDataDirty: false, operation)
            if finalizedDays > 0 {
                ReliabilityLog.info("\(logPrefix) finalized \(finalizedDays) day(s)")
                PerformanceLog.measure("appstate.autobackup.markDirty", metadata: "queue=\(name)") {
                    AutoBackupService.shared.markDirty(reason: "\(logPrefix)-finalized")
                }
            }
        } catch {
            reconciliationErrorMessage = UserFacingErrorMessage.text(for: error)
            ReliabilityLog.error("\(logPrefix) failed: \(error.localizedDescription)")
        }

        PerformanceLog.measure("appstate.refresh.afterReconciliation") {
            refresh()
        }
        if let reconciliationErrorMessage {
            setError(reconciliationErrorMessage)
        }
        afterRefresh()
    }
}

@MainActor
final class AppLifecycleRefreshCoordinator {
    private var isRunning = false
    private var pendingOperation: (() async -> Void)?

    func perform(_ operation: @escaping () async -> Void) async {
        if isRunning {
            pendingOperation = operation
            return
        }

        isRunning = true
        var nextOperation: (() async -> Void)? = operation

        while let currentOperation = nextOperation {
            pendingOperation = nil
            await currentOperation()
            nextOperation = pendingOperation
        }

        isRunning = false
    }
}
