import Foundation

@MainActor
final class AppStateWriteCoordinator {
    private let writeQueue: OperationQueue

    init(name: String) {
        let queue = OperationQueue()
        queue.name = name
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        writeQueue = queue
    }

    func performWriteOperation<T>(_ operation: @escaping () throws -> T) async throws -> T {
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

    func performMutation(
        refresh: @escaping () -> Void,
        setError: @escaping (String?) -> Void,
        refreshOnFailure: Bool = false,
        mutation: @escaping () throws -> Void
    ) async -> Bool {
        do {
            try await performWriteOperation(mutation)
            refresh()
            setError(nil)
            return true
        } catch {
            if refreshOnFailure {
                refresh()
            }
            setError(error.localizedDescription)
            return false
        }
    }

    func performThrowingMutation<T>(
        refresh: @escaping () -> Void = {},
        setError: @escaping (String?) -> Void,
        refreshOnFailure: Bool = false,
        operation: @escaping () throws -> T
    ) async throws -> T {
        do {
            let result = try await performWriteOperation(operation)
            refresh()
            setError(nil)
            return result
        } catch {
            if refreshOnFailure {
                refresh()
            }
            setError(error.localizedDescription)
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
            let finalizedDays = try await performWriteOperation(operation)
            if finalizedDays > 0 {
                ReliabilityLog.info("\(logPrefix) finalized \(finalizedDays) day(s)")
            }
        } catch {
            reconciliationErrorMessage = error.localizedDescription
            ReliabilityLog.error("\(logPrefix) failed: \(error.localizedDescription)")
        }

        refresh()
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
