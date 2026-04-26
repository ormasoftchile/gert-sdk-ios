# Run Events v1 (iOS)

Status: Proposal

## Summary

Implement a first-class runtime event stream for app developers with:

- Run lifecycle events
- Step lifecycle events
- Tool lifecycle events
- Filtered subscriptions, including per-tool and per-tool-action listeners

## Event Envelope

Use a canonical envelope for all runtime events:

- kind: String
- runID: String
- sequence: Int64
- timestampMs: Int64
- stepID: String?
- stepIndex: Int?
- toolName: String?
- action: String?
- payload: [String: AnyCodable]

Compatibility rules:

- Unknown payload fields are ignored by consumers.
- New kinds are additive.

## Event Kinds (v1)

Run:

- run/started
- run/completed
- run/failed
- run/cancelled

Step:

- step/started
- step/completed
- step/failed
- step/skipped

Tool:

- tool/invoked
- tool/completed
- tool/failed
- tool/progress (optional v1)

## Ordering and Terminal Rules

- sequence is monotonic per run, starting at 0.
- events are delivered in sequence order per run.
- no events after terminal run events:
	- run/completed
	- run/failed
	- run/cancelled

Durability rule:

- Emit and trace-write happen in the same pipeline.
- If trace write fails, session transitions to failed and emits run/failed with write failure reason.

## RunSession API (proposed)

		public var events: AsyncStream<RuntimeEvent>

		public func events(kindPrefix: String) -> AsyncStream<RuntimeEvent>
		public func events(stepID: String) -> AsyncStream<RuntimeEvent>
		public func events(toolName: String) -> AsyncStream<RuntimeEvent>
		public func events(toolName: String, action: String) -> AsyncStream<RuntimeEvent>

Implementation notes:

- Keep one internal event broker inside RunSession.
- Derive filtered streams from the same broker source.
- Assign sequence in one place (RunSession) to preserve order.

## Tool Instrumentation

Step execution should emit:

1. tool/invoked before handler execution
2. tool/completed on success
3. tool/failed on failure

Optional:

- tool/progress through handler callback hooks.

## Trace Alignment

- Every emitted RuntimeEvent is appended to trace JSONL.
- Trace lines preserve kind and sequence.
- Trace readback decodes to RuntimeEvent for sync/replay.

Example trace line shape:

	{"kind":"run/started","run_id":"r1","sequence":0,"timestamp_ms":1714145000000,"payload":{"runbook":"pool-weekly-check","actor":"alice"}}

## App Usage Examples

Tool-specific listener:

	for await event in session.events(toolName: "notifications.local") {
		switch event.kind {
		case "tool/invoked":
			showToolBusy()
		case "tool/completed":
			showToolDone()
		case "tool/failed":
			showToolError()
		default:
			break
		}
	}

Tool action listener:

	for await event in session.events(toolName: "location.read", action: "read") {
		switch event.kind {
		case "tool/invoked":
			onStart()
		case "tool/completed":
			onSuccess()
		case "tool/failed":
			onFailure()
		default:
			break
		}
	}

## Rollout

Phase 1:

- Implement run and step event stream in RunSession.

Phase 2:

- Add tool events and filtered per-tool APIs.

Phase 3:

- Enforce live stream and trace parity.

## Test Contract

Unit:

- Sequence is strictly increasing per run.
- Filters return only matching tool or action events.
- No events are emitted after terminal event.

Integration:

- Successful run emits expected order:
	- run/started
	- step/started
	- tool/invoked
	- tool/completed
	- step/completed
	- run/completed
- Failing tool emits:
	- tool/failed
	- step/failed
	- run/failed

Trace:

- Trace line count equals emitted event count.
- Sequence in trace is strictly increasing by 1.

## Migration Notes

- Keep existing RunEvent public types temporarily as compatibility wrappers.
- Mark old variants deprecated once RuntimeEvent is available.
- Remove compatibility wrappers in next major SDK version.
