import Foundation

/// Represents an active runbook execution session.
public class RunSession {
    public let runID: String
    public let kitName: String
    public let runbookName: String
    public let actor: String
    public let startedAt: Date
    
    private let executor: StepExecutor
    private let traceWriter: TraceWriter
    
    /// AsyncStream of run events as they occur
    public var events: AsyncStream<RunEvent> {
        AsyncStream { continuation in
            // TODO: Connect to internal event stream
            continuation.finish()
        }
    }
    
    init(
        runID: String,
        kitName: String,
        runbookName: String,
        actor: String,
        executor: StepExecutor,
        traceWriter: TraceWriter
    ) {
        self.runID = runID
        self.kitName = kitName
        self.runbookName = runbookName
        self.actor = actor
        self.startedAt = Date()
        self.executor = executor
        self.traceWriter = traceWriter
    }
    
    /// Start executing the runbook.
    public func start() async throws {
        fatalError("Not yet implemented")
    }
    
    /// Wait for the run to complete and return the final result.
    public func wait() async throws -> CompletedRun {
        fatalError("Not yet implemented")
    }
    
    /// Cancel the run.
    public func cancel() async {
        fatalError("Not yet implemented")
    }
}
