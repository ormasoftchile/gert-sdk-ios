// RunEventsExample.swift
// Demonstrates subscribing to the RuntimeEvent stream from a RunSession.
import Foundation

public struct RunEventsExample {

    // MARK: - a. Subscribe to all events

    /// Print every event emitted during a run.
    public static func subscribeAllEvents(session: RunSession) {
        Task {
            for await event in session.events {
                print("[\(event.sequence)] \(event.kind) run=\(event.runID)")
            }
        }
    }

    // MARK: - b. Subscribe filtered by toolName

    /// React to all lifecycle events for the "notifications.local" tool.
    public static func subscribeNotificationsTool(session: RunSession) {
        Task {
            for await event in session.events(toolName: "notifications.local") {
                switch event.kind {
                case RuntimeEvent.toolInvoked:
                    print("[notifications.local] sending notification…")
                case RuntimeEvent.toolCompleted:
                    print("[notifications.local] notification sent ✓")
                case RuntimeEvent.toolFailed:
                    let reason = event.payload["error"].flatMap {
                        if case .string(let s) = $0 { return s } else { return nil }
                    } ?? "unknown error"
                    print("[notifications.local] failed: \(reason)")
                default:
                    break
                }
            }
        }
    }

    // MARK: - c. Subscribe filtered by toolName + action

    /// React specifically to "location.read" tool with action "read".
    public static func subscribeLocationRead(session: RunSession) {
        Task {
            for await event in session.events(toolName: "location.read", action: "read") {
                switch event.kind {
                case RuntimeEvent.toolInvoked:
                    print("[location.read/read] acquiring GPS fix…")
                case RuntimeEvent.toolCompleted:
                    print("[location.read/read] location acquired ✓")
                case RuntimeEvent.toolFailed:
                    let reason = event.payload["error"].flatMap {
                        if case .string(let s) = $0 { return s } else { return nil }
                    } ?? "unknown error"
                    print("[location.read/read] failed: \(reason)")
                default:
                    break
                }
            }
        }
    }

    // MARK: - Full example wiring

    /// Load a kit, subscribe to events, and start the run.
    public static func run(kitURL: URL) async throws {
        let kit = try await GertSDK.loadKit(from: kitURL)

        guard let runbook = kit.runbooks.first(where: { $0.name == "pool-weekly-check" }) else {
            print("Runbook not found")
            return
        }

        print("Starting: \(runbook.name) — \(runbook.steps.count) steps")

        let session = try await kit.startRun(runbook: runbook.name, actor: "alice")

        // Wire up all three subscriber patterns before starting.
        subscribeAllEvents(session: session)
        subscribeNotificationsTool(session: session)
        subscribeLocationRead(session: session)

        // Start the run — events will be delivered to the subscribers above.
        try await session.start()
    }
}
