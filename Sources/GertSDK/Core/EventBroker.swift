import Foundation

/// Internal fan-out broker for RuntimeEvent streams.
///
/// Owns the monotonic sequence counter and trace-write pipeline. All events
/// flow through a single `emit(...)` call, guaranteeing sequence order and
/// live-stream/trace parity.
///
/// **Terminal-event rule:** after run/completed, run/failed, or run/cancelled,
/// all streams finish and further emits are no-ops.
///
/// `makeStream()` is `nonisolated` so `RunSession.events` can be a plain `var`.
actor EventBroker {
    private var nextSequence: Int64 = 0
    private var subscribers:  [UUID: AsyncStream<RuntimeEvent>.Continuation] = [:]
    private var isTerminated  = false
    private let traceWriter:  TraceWriter?

    init(traceWriter: TraceWriter? = nil) {
        self.traceWriter = traceWriter
    }

    // MARK: - Emit

    /// Build a RuntimeEvent, stamp sequence, fan out to all subscribers, and
    /// write to trace. Returns the stamped event, or nil if already terminated.
    @discardableResult
    func emit(
        kind:      String,
        runID:     String,
        stepID:    String?             = nil,
        stepIndex: Int?                = nil,
        toolName:  String?             = nil,
        action:    String?             = nil,
        payload:   [String: JSONValue] = [:]
    ) -> RuntimeEvent? {
        guard !isTerminated else { return nil }

        let event = RuntimeEvent(
            kind:        kind,
            runID:       runID,
            sequence:    nextSequence,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            stepID:      stepID,
            stepIndex:   stepIndex,
            toolName:    toolName,
            action:      action,
            payload:     payload
        )
        nextSequence += 1

        deliver(event)

        // Durability: trace-write in same pipeline as fan-out.
        if let writer = traceWriter {
            do {
                try writer.write(event)
            } catch {
                // Don't recurse if the failing write was itself a terminal event.
                guard !RuntimeEvent.terminalKinds.contains(kind) else {
                    terminateStreams()
                    return event
                }
                // Escalate to run/failed with the write-failure reason.
                let failEvent = RuntimeEvent(
                    kind:        RuntimeEvent.runFailed,
                    runID:       runID,
                    sequence:    nextSequence,
                    timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                    payload:     ["error": .string("trace write failed: \(error.localizedDescription)")]
                )
                nextSequence += 1
                deliver(failEvent)
                // Best-effort: try writing the failure event itself.
                try? writer.write(failEvent)
                terminateStreams()
                return failEvent
            }
        }

        if RuntimeEvent.terminalKinds.contains(kind) {
            terminateStreams()
        }

        return event
    }

    // MARK: - Stream Subscription

    /// Creates a subscriber stream. `nonisolated` so it can be called from a
    /// synchronous context (e.g., a computed `var`). The continuation is
    /// registered on the actor's executor via a spawned Task, which is
    /// enqueued before any `emit(...)` call that follows in the same async
    /// chain.
    nonisolated func makeStream() -> AsyncStream<RuntimeEvent> {
        let (stream, continuation) = AsyncStream<RuntimeEvent>.makeStream()
        Task { await self.addSubscriber(continuation) }
        return stream
    }

    // MARK: - Lifecycle

    /// Close the underlying trace file. Call after the terminal event has been emitted.
    func close() {
        try? traceWriter?.close()
    }

    // MARK: - Internals

    private func addSubscriber(_ continuation: AsyncStream<RuntimeEvent>.Continuation) {
        if isTerminated {
            continuation.finish()
            return
        }
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in await self?.removeSubscriber(id: id) }
        }
    }

    private func deliver(_ event: RuntimeEvent) {
        for cont in subscribers.values {
            cont.yield(event)
        }
    }

    private func terminateStreams() {
        isTerminated = true
        subscribers.values.forEach { $0.finish() }
        subscribers.removeAll()
    }

    private func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}
