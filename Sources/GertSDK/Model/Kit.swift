import Foundation

/// Kit represents a loaded gert kit bundle.
public struct LoadedKit {
    public let manifest: Manifest
    public let runbooks: [RunbookEntry]
    public let tools: [ToolDefinition]
    
    /// Start a new run of a runbook in this kit.
    /// - Parameters:
    ///   - runbook: Name of the runbook to execute
    ///   - actor: Opaque actor identifier (e.g., user ID, email)
    ///   - inputs: Optional inputs to pass to the runbook
    /// - Returns: A RunSession tracking the execution
    /// - Throws: If runbook not found or validation fails
    public func startRun(
        runbook: String,
        actor: String,
        inputs: [String: Any] = [:]
    ) async throws -> RunSession {
        guard runbooks.contains(where: { $0.name == runbook }) else {
            throw KitError.runbookNotFound(runbook)
        }
        
        let runID = UUID().uuidString
        let executor = StepExecutor(tools: tools)
        let traceWriter = try TraceWriter(runID: runID)
        
        return RunSession(
            runID: runID,
            kitName: manifest.name,
            runbookName: runbook,
            actor: actor,
            executor: executor,
            traceWriter: traceWriter
        )
    }
}

/// Manifest maps to manifest.json in the kit bundle.
public struct Manifest: Codable {
    public let name: String
    public let version: String
    public let description: String?
    public let dependencies: [Dependency]?
    
    enum CodingKeys: String, CodingKey {
        case name, version, description, dependencies
    }
}

/// Dependency represents a required kit dependency.
public struct Dependency: Codable {
    public let name: String
    public let version: String
    
    enum CodingKeys: String, CodingKey {
        case name, version
    }
}

/// RunbookEntry represents a runbook definition.
public struct RunbookEntry: Codable {
    public let name: String
    public let description: String?
    public let steps: [String]?
    
    enum CodingKeys: String, CodingKey {
        case name, description, steps
    }
}

/// CompletedRun represents a finished run ready to sync.
public struct CompletedRun {
    public let runID: String
    public let kitName: String
    public let runbookName: String
    public let actor: String
    public let startedAt: Date
    public let completedAt: Date
    public let status: RunStatus
    public let events: [RunEvent]
}

public enum RunStatus: String, Codable {
    case succeeded
    case failed
    case cancelled
}

public enum KitError: Error, LocalizedError {
    case runbookNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .runbookNotFound(let name):
            return "Runbook '\(name)' not found in kit"
        }
    }
}
