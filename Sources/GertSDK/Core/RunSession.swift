import Foundation

public enum RunSessionError: Error, LocalizedError {
    case alreadyStarted
    case notStarted

    public var errorDescription: String? {
        switch self {
        case .alreadyStarted: return "Run session has already been started"
        case .notStarted:     return "Run session has not been started"
        }
    }
}

// RunSession drives the execution of a single runbook against a kit.
// It owns the EventBroker, sequences the flow, and exposes both an
// AsyncStream of events and a `wait()` for the final summary.
public final class RunSession: @unchecked Sendable {
    public let runID: String
    public let kitName: String
    public let runbook: Runbook
    public let actor: String
    public let startedAt: Date

    private let executor: StepExecutor
    private let broker = EventBroker()
    private var task: Task<CompletedRun, Error>?

    init(
        runID: String,
        kitName: String,
        runbook: Runbook,
        actor: String,
        executor: StepExecutor
    ) {
        self.runID = runID
        self.kitName = kitName
        self.runbook = runbook
        self.actor = actor
        self.startedAt = Date()
        self.executor = executor
    }

    /// Live event stream. Subscribers attached after `start()` still
    /// see buffered earlier events thanks to EventBroker's backlog.
    public var events: AsyncStream<RuntimeEvent> { broker.makeStream() }

    public func events(kindPrefix: String) -> AsyncStream<RuntimeEvent> {
        let upstream = broker.makeStream()
        return AsyncStream { cont in
            Task {
                for await ev in upstream where ev.kind.hasPrefix(kindPrefix) {
                    cont.yield(ev)
                }
                cont.finish()
            }
        }
    }

    /// Begins execution. Subsequent calls are a no-op.
    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { throw RunSessionError.notStarted }
            return try await self.run()
        }
    }

    /// Waits for the run to finish and returns the summary.
    public func wait() async throws -> CompletedRun {
        guard let task else { throw RunSessionError.notStarted }
        return try await task.value
    }

    /// Cooperative cancellation; the loop checks Task.isCancelled
    /// between steps.
    public func cancel() {
        task?.cancel()
    }

    private func run() async throws -> CompletedRun {
        var collected: [RuntimeEvent] = []
        let collector = Task { [broker] in
            for await ev in broker.makeStream() {
                collected.append(ev)
            }
        }

        await broker.emit(
            kind: RuntimeEvent.runStarted,
            runID: runID,
            payload: [
                "runbook": .string(runbook.id),
                "actor":   .string(actor),
                "kit":     .string(kitName),
            ]
        )

        var firstError: Error?

        for (index, item) in runbook.flow.enumerated() {
            if Task.isCancelled {
                await broker.emit(kind: RuntimeEvent.runCancelled, runID: runID)
                await broker.close()
                _ = await collector.value
                return CompletedRun(
                    runID: runID, kitName: kitName, runbookID: runbook.id, actor: actor,
                    startedAt: startedAt, completedAt: Date(),
                    status: .cancelled, events: collected
                )
            }

            let step = item.step
            await broker.emit(
                kind: RuntimeEvent.stepStarted,
                runID: runID,
                stepID: step.id,
                stepIndex: index,
                toolName: step.tool?.name
            )

            do {
                let outputs = try await executor.execute(
                    step: step, index: index, runID: runID, broker: broker
                )
                await broker.emit(
                    kind: RuntimeEvent.stepCompleted,
                    runID: runID,
                    stepID: step.id,
                    stepIndex: index,
                    toolName: step.tool?.name,
                    payload: outputs
                )
            } catch is CancellationError {
                await broker.emit(kind: RuntimeEvent.runCancelled, runID: runID)
                await broker.close()
                _ = await collector.value
                return CompletedRun(
                    runID: runID, kitName: kitName, runbookID: runbook.id, actor: actor,
                    startedAt: startedAt, completedAt: Date(),
                    status: .cancelled, events: collected
                )
            } catch {
                firstError = firstError ?? error
                await broker.emit(
                    kind: RuntimeEvent.stepFailed,
                    runID: runID,
                    stepID: step.id,
                    stepIndex: index,
                    toolName: step.tool?.name,
                    payload: ["error": .string(error.localizedDescription)]
                )
            }
        }

        let status: RunStatus
        if let firstError {
            await broker.emit(
                kind: RuntimeEvent.runFailed,
                runID: runID,
                payload: ["error": .string(firstError.localizedDescription)]
            )
            status = .failed
        } else {
            await broker.emit(kind: RuntimeEvent.runCompleted, runID: runID)
            status = .succeeded
        }

        await broker.close()
        _ = await collector.value

        let summary = CompletedRun(
            runID: runID, kitName: kitName, runbookID: runbook.id, actor: actor,
            startedAt: startedAt, completedAt: Date(),
            status: status, events: collected
        )
        if let firstError { throw firstError }
        return summary
    }
}
