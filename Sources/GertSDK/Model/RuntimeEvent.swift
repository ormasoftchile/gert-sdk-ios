import Foundation

// MARK: - JSONValue

/// Type-safe Codable representation of arbitrary JSON values, used for RuntimeEvent payload fields.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode JSONValue"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .null:          try container.encodeNil()
        case .array(let v):  try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

// MARK: - RuntimeEvent

/// Canonical event envelope for all runtime events during a runbook execution.
/// See run-events-v1.md for the full specification.
public struct RuntimeEvent: Codable, Sendable {
    /// Event kind (e.g. "run/started", "tool/completed").
    public let kind:        String
    /// Unique identifier for the run this event belongs to.
    public let runID:       String
    /// Monotonic sequence number per run, starting at 0.
    public let sequence:    Int64
    /// Unix timestamp in milliseconds.
    public let timestampMs: Int64
    /// Step identifier (present for step and tool events).
    public let stepID:      String?
    /// Step index in the runbook (present for step and tool events).
    public let stepIndex:   Int?
    /// Tool name (present for tool events).
    public let toolName:    String?
    /// Tool action (present for tool events).
    public let action:      String?
    /// Arbitrary event payload.
    public let payload:     [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case kind
        case runID       = "run_id"
        case sequence
        case timestampMs = "timestamp_ms"
        case stepID      = "step_id"
        case stepIndex   = "step_index"
        case toolName    = "tool_name"
        case action
        case payload
    }

    public init(
        kind:        String,
        runID:       String,
        sequence:    Int64,
        timestampMs: Int64,
        stepID:      String?             = nil,
        stepIndex:   Int?                = nil,
        toolName:    String?             = nil,
        action:      String?             = nil,
        payload:     [String: JSONValue] = [:]
    ) {
        self.kind        = kind
        self.runID       = runID
        self.sequence    = sequence
        self.timestampMs = timestampMs
        self.stepID      = stepID
        self.stepIndex   = stepIndex
        self.toolName    = toolName
        self.action      = action
        self.payload     = payload
    }
}

// MARK: - Event Kind Constants

extension RuntimeEvent {
    public static let runStarted    = "run/started"
    public static let runCompleted  = "run/completed"
    public static let runFailed     = "run/failed"
    public static let runCancelled  = "run/cancelled"

    public static let stepStarted   = "step/started"
    public static let stepCompleted = "step/completed"
    public static let stepFailed    = "step/failed"
    public static let stepSkipped   = "step/skipped"

    public static let toolInvoked   = "tool/invoked"
    public static let toolCompleted = "tool/completed"
    public static let toolFailed    = "tool/failed"
    public static let toolProgress  = "tool/progress"

    /// Kinds that terminate the event stream — no events are delivered after these.
    static let terminalKinds: Set<String> = [
        runCompleted,
        runFailed,
        runCancelled,
    ]
}
