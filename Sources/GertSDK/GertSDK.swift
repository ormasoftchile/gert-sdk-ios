import Foundation

// GertSDK is the top-level entry point for hosts. The typical flow is:
//
//   let runbook = try Runbook.decode(yamlData)
//   let runtime = GertRuntime()
//   runtime.handlers.register(MyCameraHandler())
//   let session = runtime.startRun(
//     runbook: runbook,
//     actor: "alice",
//     collector: MyFormResolver()
//   )
//   for await event in session.events { print(event) }
//   let result = try await session.wait()
//
public enum GertSDK {
    public static let version = "0.1.0"
}

// GertRuntime owns a per-process handler registry and starts runbook
// runs. Hosts construct one runtime and reuse it across runs.
public final class GertRuntime: @unchecked Sendable {
    public let handlers: HandlerRegistry

    public init(handlers: HandlerRegistry = HandlerRegistry()) {
        self.handlers = handlers
    }

    /// Starts a run for the given runbook.
    @discardableResult
    public func startRun(
        runbook: Runbook,
        actor: String,
        source: String = "",
        collector: CollectorResolver = FailingCollectorResolver()
    ) -> RunSession {
        let executor = StepExecutor(handlers: handlers, collectorResolver: collector)
        let session = RunSession(
            runID: UUID().uuidString,
            kitName: source,
            runbook: runbook,
            actor: actor,
            executor: executor
        )
        session.start()
        return session
    }
}
