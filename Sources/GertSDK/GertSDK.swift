import Foundation

// GertSDK is the top-level entry point for hosts. The typical flow is:
//
//   let kit = try KitLoader.load(from: kitURL)
//   let runtime = GertRuntime(kit: kit)
//   runtime.handlers.register(MyCameraHandler())
//   runtime.handlers.register(MyLocationHandler())
//   let session = try runtime.startRun(
//     routineID: "casa-santiago.routine.pool_clean",
//     actor: "alice",
//     collector: MyFormResolver()
//   )
//   for await event in session.events { print(event) }
//   let result = try await session.wait()
//
public enum GertSDK {
    public static let version = "0.1.0"
}

// GertRuntime ties a loaded kit to a per-process handler registry.
// Hosts construct one runtime per kit and reuse it across runs.
public final class GertRuntime: @unchecked Sendable {
    public let kit: LoadedKit
    public let handlers: HandlerRegistry

    public init(kit: LoadedKit, handlers: HandlerRegistry = HandlerRegistry()) {
        self.kit = kit
        self.handlers = handlers
    }

    /// Starts a routine by its kit-scoped id.
    @discardableResult
    public func startRun(
        routineID: String,
        actor: String,
        collector: CollectorResolver = FailingCollectorResolver()
    ) throws -> RunSession {
        guard let entry = kit.routine(id: routineID) else {
            throw GertRuntimeError.routineNotFound(routineID)
        }
        let runbook = try kit.runbook(for: entry)
        let executor = StepExecutor(handlers: handlers, collectorResolver: collector)
        let session = RunSession(
            runID: UUID().uuidString,
            kitName: kit.manifest.name,
            runbook: runbook,
            actor: actor,
            executor: executor
        )
        session.start()
        return session
    }

    /// Lists routines that can run on this device given the currently
    /// registered tool handlers. Routines whose `tool_deps` reference
    /// an unregistered handler are excluded.
    public func runnableRoutines() -> [HomeKitIndex.Entry] {
        kit.routines.filter { entry in
            guard let deps = entry.toolDeps else { return true }
            return deps.allSatisfy { handlers.handler(for: $0) != nil }
        }
    }
}

public enum GertRuntimeError: Error, LocalizedError {
    case routineNotFound(String)
    public var errorDescription: String? {
        switch self {
        case .routineNotFound(let id): return "Routine '\(id)' not found in kit"
        }
    }
}
