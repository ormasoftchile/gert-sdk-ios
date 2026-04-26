import Foundation

/// StepExecutor executes individual runbook steps.
public struct StepExecutor {
    private let tools: [String: ToolDefinition]
    private let handlers: [String: GertToolHandler]
    
    init(tools: [ToolDefinition]) {
        var toolMap: [String: ToolDefinition] = [:]
        for tool in tools {
            toolMap[tool.name] = tool
        }
        self.tools = toolMap
        
        // Build handler map from registry
        var handlerMap: [String: GertToolHandler] = [:]
        for handler in PlatformHandlerRegistry.shared.allHandlers {
            handlerMap[handler.capability] = handler
        }
        self.handlers = handlerMap
    }
    
    /// Execute a single step.
    /// - Parameter step: The step definition from the execution plan
    /// - Returns: Step output as a dictionary
    /// - Throws: Execution errors
    public func execute(step: ExecutionStep) async throws -> [String: Any] {
        guard let tool = tools[step.toolName] else {
            throw ExecutionError.toolNotFound(step.toolName)
        }
        
        guard let iosImpl = tool.iosImpl else {
            throw ExecutionError.noIOSImpl(step.toolName)
        }
        
        switch iosImpl.transport {
        case .nativeSDK:
            return try await executeNativeHandler(impl: iosImpl, inputs: step.inputs)
        case .http:
            return try await executeHTTPHandler(impl: iosImpl, inputs: step.inputs)
        }
    }
    
    private func executeNativeHandler(impl: PlatformImpl, inputs: [String: Any]) async throws -> [String: Any] {
        guard let handler = handlers[impl.handler] else {
            throw ExecutionError.handlerNotFound(impl.handler)
        }
        return try await handler.execute(inputs: inputs)
    }
    
    private func executeHTTPHandler(impl: PlatformImpl, inputs: [String: Any]) async throws -> [String: Any] {
        fatalError("Not yet implemented")
    }
}

public enum ExecutionError: Error, LocalizedError {
    case toolNotFound(String)
    case noIOSImpl(String)
    case handlerNotFound(String)
    case stepFailed(String, underlying: Error)
    
    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool '\(name)' not found in kit"
        case .noIOSImpl(let name):
            return "Tool '\(name)' has no iOS implementation"
        case .handlerNotFound(let handler):
            return "Handler '\(handler)' not registered"
        case .stepFailed(let stepName, let error):
            return "Step '\(stepName)' failed: \(error.localizedDescription)"
        }
    }
}

/// Represents a step in the execution plan
public struct ExecutionStep {
    public let id: String
    public let toolName: String
    public let inputs: [String: Any]
}
