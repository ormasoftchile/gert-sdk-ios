import Foundation

// TraceEnvelope is the on-the-wire form of a trace event posted to
// the gert server's /api/v1/runs/ingest endpoint. The shape mirrors
// pkg/trace/event.go in the gert repo: every event carries the same
// envelope with a kind discriminator and an opaque payload.
//
// We encode RuntimeEvent into this envelope at sync time rather than
// at emit time so the runtime stays platform-agnostic.
struct TraceEnvelope: Encodable {
    let event_id: String
    let run_id: String
    let runbook_id: String
    let timestamp: String          // RFC3339 with microsecond precision
    let kind: String
    let sequence: Int64
    let payload: JSONValue
}

extension TraceEnvelope {
    /// Builds the envelope for one RuntimeEvent. step_id, step_index,
    /// tool_name and action are folded into the payload alongside any
    /// caller-provided values, matching what the engine emits.
    static func from(event: RuntimeEvent, runbookID: String) -> TraceEnvelope {
        var payload: [String: JSONValue] = event.payload ?? [:]
        if let id = event.stepID         { payload["step_id"]    = .string(id) }
        if let idx = event.stepIndex     { payload["step_index"] = .int(idx) }
        if let tn  = event.toolName      { payload["tool"]       = .string(tn) }
        if let act = event.action        { payload["action"]     = .string(act) }

        return TraceEnvelope(
            event_id:   UUID().uuidString,
            run_id:     event.runID,
            runbook_id: runbookID,
            timestamp:  Self.formatter.string(from: event.timestamp),
            kind:       event.kind,
            sequence:   Int64(event.sequence),
            payload:    .object(payload)
        )
    }

    /// RFC3339 with microsecond fraction; matches engine output.
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
