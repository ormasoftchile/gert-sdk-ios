import Foundation

/// Represents an active runbook execution session.
public class RunSession {
    public let runID:       String
    public let kitName:     String
    public let runbookName: String
    public let actor:       String
    public let startedAt:   Date

    private let runbook:  RunbookEntry
    private let executor: StepExecutor
    private let broker:   EventBroker

    private var runTask: Task<CompletedRun, Error>?

    // MARK: - Event Streams

    /// All events for this run in sequence order.
    public var events: AsyncStream<RuntimeEvent> {
        broker.makeStream()
    }

    /// Events whose `kind` starts with `kindPrefix` (e.g. `"tool/"`, `"step/"`).
    public func events(kindPrefix: String) -> AsyncStream<RuntimeEvent> {
        filtered { $0.kind.hasPrefix(kindPrefix) }
    }

    /// Events associated with a specific step.
    public func events(stepID: String) -> AsyncStream<RuntimeEvent> {
        filtered { $0.stepID == stepID }
    }

    /// Events emitted by a specific tool (all actions).
    public func events(toolName: String) -> AsyncStream<RuntimeEvent> {
        filtered { $0.toolName == toolName }
    }

    /// Events emitted by a specific tool action.
    public func events(toolName: String, action: String) -> AsyncStream<RuntimeEvent> {
        filtered { $0.toolName == toolName && $0.action == action }
    }

    // MARK: - Lifecycle

    /// Begins executing the runbook asynchronously. Subscribe to `events` before calling this.
    public func start() async throws {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { throw RunSessionError.sessionDeallocated }
            return try await self.executeRun()
        }
    }

    /// Waits for the run to finish and returns the completed-run summary.
    public func wait() async throws -> CompletedRun {
        guard let task = runTask else { throw RunSessionError.notStarted }
        return try await task.value
    }

    /// Cancels the run. The run task detects cancellation cooperatively and
    /// emits run/cancelled before exiting.
    public func cancel() async {
        runTask?.cancel()
    }

    // MARK: - Internal Init

    init(
        runID:       String,
        kitName:     String,
        runbookName: String,
        actor:       String,
        runbook:     RunbookEntry,
        executor:    StepExecutor,
        traceWriter: TraceWriter
    ) {
        self.runID       = runID
        self.kitName     = kitName
        self.runbookName = runbookName
        self.actor       = actor
        self.startedAt   = Date()
        self.runbook     = runbook
        self.executor    = executor
        self.broker      = EventBroker(traceWriter: traceWriter)
    }

    // MARK: - Private Execution

    private func executeRun() async throws -> CompletedRun {
        defer { Task { await self.broker.close() } }

        let steps = buildExecutionPlan()
        var collectedEvents: [RuntimeEvent] = []

        // Collect every event for the CompletedRun summary via a dedicated subscriber.
        let collectorStream = broker.makeStream()
        let collectTask = Task {
            for await event in collectorStream {
                collectedEvents.append(event)
            }
        }

        await broker.emit(
            kind:    RuntimeEvent.runStarted,
            runID:   runID,
            payload: [
                "runbook": .string(runbookName),
                "actor":   .string(actor),
                "kit":     .string(kitName),
            ]
        )

        var firstStepError: Error?

        for (index, step) in steps.enumerated() {
            if Task.isCancelled {
                await broker.emit(kind: RuntimeEvent.runCancelled, runID: runID)
                await collectTask.value
                return makeCompletedRun(status: .cancelled, events: collectedEvents)
            }

            await broker.emit(
                kind:      RuntimeEvent.stepStarted,
                runID:     runID,
                stepID:    step.id,
                stepIndex: index,
                toolName:  step.toolName
            )

            do {
                let outputs = try await executor.execute(
                    step:      step,
                    broker:    broker,
                    runID:     runID,
                    stepIndex: index
                )
                await broker.emit(
                    kind:      RuntimeEvent.stepCompleted,
                    runID:     runID,
                    stepID:    step.id,
                    stepIndex: index,
                    toolName:  step.toolName,
                    payload:   outputs.asJSONPayload()
                )
            } catch is CancellationError {
                await broker.emit(kind: RuntimeEvent.runCancelled, runID: runID)
                await collectTask.value
                return makeCompletedRun(status: .cancelled, events: collectedEvents)
            } catch {
                firstStepError = firstStepError ?? error
                await broker.emit(
                    kind:      RuntimeEvent.stepFailed,
                    runID:     runID,
                    stepID:    step.id,
                    stepIndex: index,
                    toolName:  step.toolName,
                    payload:   ["error": .string(error.localizedDescription)]
                )
            }
        }

        if let error = firstStepError {
            await broker.emit(
                kind:    RuntimeEvent.runFailed,
                runID:   runID,
                payload: ["error": .string(error.localizedDescription)]
            )
            await collectTask.value
            let completed = makeCompletedRun(status: .failed, events: collectedEvents)
            throw RunSessionError.runFailed(completed, underlying: error)
        }

        await broker.emit(kind: RuntimeEvent.runCompleted, runID: runID)
        await collectTask.value
        return makeCompletedRun(status: .succeeded, events: collectedEvents)
    }

    private func buildExecutionPlan() -> [ExecutionStep] {
        runbook.steps.map { step in
            let inputs: [String: Any] = step.args?.reduce(into: [:]) { dict, pair in
                dict[pair.key] = pair.value.value
            } ?? [:]
            return ExecutionStep(id: step.id, toolName: step.tool, action: step.action, inputs: inputs)
        }
    }

    private func makeCompletedRun(status: RunStatus, events: [RuntimeEvent]) -> CompletedRun {
        CompletedRun(
            runID:       runID,
            kitName:     kitName,
            runbookName: runbookName,
            actor:       actor,
            startedAt:   startedAt,
            completedAt: Date(),
            status:      status,
            events:      events
        )
    }

    private func filtered(
        _ predicate: @escaping @Sendable (RuntimeEvent) -> Bool
    ) -> AsyncStream<RuntimeEvent> {
        let upstream = broker.makeStream()
        return AsyncStream { continuation in
            Task {
                for await event in upstream where predicate(event) {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - Errors

public enum RunSessionError: Error, LocalizedError {
    case notStarted
    case sessionDeallocated
    case runFailed(CompletedRun, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .notStarted:
            return "Run has not been started — call start() first"
        case .sessionDeallocated:
            return "RunSession was deallocated before the run completed"
        case .runFailed(_, let error):
            return "Run failed: \(error.localizedDescription)"
        }
    }
}
