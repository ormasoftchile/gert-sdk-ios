import Foundation

// EventBroker is the actor every emitter funnels events through. It
// owns a monotonically-increasing sequence number and a set of
// subscribers (one continuation per `events` AsyncStream consumer).
//
// Subscribers see all events emitted from the moment they start
// iterating; events emitted before subscription are buffered for
// late consumers up to a small bound so a host that calls
// `events.next()` slightly after `start()` still sees `run/started`.
actor EventBroker {
    private var nextSequence: Int = 0
    private var subscribers: [UUID: AsyncStream<RuntimeEvent>.Continuation] = [:]
    private var backlog: [RuntimeEvent] = []
    private let backlogLimit: Int = 1024

    /// Creates a new subscriber stream. Existing buffered events are
    /// replayed in order before live events flow through.
    nonisolated func makeStream() -> AsyncStream<RuntimeEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.attach(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.detach(id: id) }
            }
        }
    }

    private func attach(id: UUID, continuation: AsyncStream<RuntimeEvent>.Continuation) {
        for ev in backlog { continuation.yield(ev) }
        subscribers[id] = continuation
    }

    private func detach(id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    /// Emit a new event; assigns the next sequence and broadcasts.
    func emit(
        kind: String,
        runID: String,
        stepID: String? = nil,
        stepIndex: Int? = nil,
        toolName: String? = nil,
        action: String? = nil,
        payload: [String: JSONValue]? = nil
    ) {
        let ev = RuntimeEvent(
            sequence: nextSequence,
            kind: kind,
            runID: runID,
            stepID: stepID,
            stepIndex: stepIndex,
            toolName: toolName,
            action: action,
            payload: payload
        )
        nextSequence += 1
        backlog.append(ev)
        if backlog.count > backlogLimit { backlog.removeFirst(backlog.count - backlogLimit) }
        for (_, cont) in subscribers { cont.yield(ev) }
    }

    /// Closes all subscriber streams; called when the run finishes.
    func close() {
        for (_, cont) in subscribers { cont.finish() }
        subscribers.removeAll()
    }
}
