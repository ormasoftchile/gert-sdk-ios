import Foundation

// RuntimeEvent describes a single event emitted while a run executes.
// Events are immutable and ordered by `sequence`. The vocabulary of
// `kind` strings matches what gert's HTTP/SSE server emits so a host
// can reuse logging, telemetry and replay code paths between local
// in-app runs and server-side runs.
public struct RuntimeEvent: Sendable, Codable, Equatable {
    public let sequence: Int
    public let timestamp: Date
    public let kind: String
    public let runID: String
    public let stepID: String?
    public let stepIndex: Int?
    public let toolName: String?
    public let action: String?
    public let payload: [String: JSONValue]?

    public init(
        sequence: Int,
        timestamp: Date = Date(),
        kind: String,
        runID: String,
        stepID: String? = nil,
        stepIndex: Int? = nil,
        toolName: String? = nil,
        action: String? = nil,
        payload: [String: JSONValue]? = nil
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.kind = kind
        self.runID = runID
        self.stepID = stepID
        self.stepIndex = stepIndex
        self.toolName = toolName
        self.action = action
        self.payload = payload
    }
}

public extension RuntimeEvent {
    // Run lifecycle
    static let runStarted   = "run/started"
    static let runCompleted = "run/completed"
    static let runFailed    = "run/failed"
    static let runCancelled = "run/cancelled"

    // Step lifecycle
    static let stepStarted     = "step/started"
    static let stepCompleted   = "step/completed"
    static let stepFailed      = "step/failed"
    /// Emitted when a collector step is waiting for the host to
    /// supply user input via `RunSession.submitCollectorInput`.
    static let stepAwaitingInput = "step/awaiting_input"

    // Tool lifecycle (a tool step emits its own start/complete in
    // addition to the surrounding step lifecycle events).
    static let toolInvoked   = "tool/invoked"
    static let toolCompleted = "tool/completed"
    static let toolFailed    = "tool/failed"
}

public enum RunStatus: String, Sendable, Codable {
    case succeeded
    case failed
    case cancelled
}

// CompletedRun is the immutable summary returned when a RunSession
// finishes. It carries the full event log so a caller can sync it to
// the gert server, archive it, or display it offline.
public struct CompletedRun: Sendable, Codable {
    public let runID: String
    public let kitName: String
    public let runbookID: String
    public let actor: String
    public let startedAt: Date
    public let completedAt: Date
    public let status: RunStatus
    public let events: [RuntimeEvent]

    public init(
        runID: String,
        kitName: String,
        runbookID: String,
        actor: String,
        startedAt: Date,
        completedAt: Date,
        status: RunStatus,
        events: [RuntimeEvent]
    ) {
        self.runID = runID
        self.kitName = kitName
        self.runbookID = runbookID
        self.actor = actor
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.events = events
    }
}
