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
    
    /// Execute a single step, emitting tool/invoked, tool/completed, or tool/failed events.
    /// - Parameters:
    ///   - step: The step definition from the execution plan
    ///   - broker: EventBroker to emit tool lifecycle events
    ///   - runID: The run identifier
    ///   - stepIndex: The index of the step in the runbook
    /// - Returns: Step output as a dictionary
    /// - Throws: Execution errors
    public func execute(
        step:      ExecutionStep,
        broker:    EventBroker,
        runID:     String,
        stepIndex: Int
    ) async throws -> [String: Any] {
        guard let tool = tools[step.toolName] else {
            throw ExecutionError.toolNotFound(step.toolName)
        }
        
        guard let iosImpl = tool.iosImpl else {
            throw ExecutionError.noIOSImpl(step.toolName)
        }

        await broker.emit(
            kind:      RuntimeEvent.toolInvoked,
            runID:     runID,
            stepID:    step.id,
            stepIndex: stepIndex,
            toolName:  step.toolName,
            action:    step.action,
            payload:   step.inputs.asJSONPayload()
        )

        do {
            let result: [String: Any]
            switch iosImpl.transport {
            case .nativeSDK:
                result = try await executeNativeHandler(impl: iosImpl, inputs: step.inputs)
            case .http:
                result = try await executeHTTPHandler(impl: iosImpl, inputs: step.inputs)
            }

            await broker.emit(
                kind:      RuntimeEvent.toolCompleted,
                runID:     runID,
                stepID:    step.id,
                stepIndex: stepIndex,
                toolName:  step.toolName,
                action:    step.action,
                payload:   result.asJSONPayload()
            )
            return result
        } catch {
            await broker.emit(
                kind:      RuntimeEvent.toolFailed,
                runID:     runID,
                stepID:    step.id,
                stepIndex: stepIndex,
                toolName:  step.toolName,
                action:    step.action,
                payload:   [
                    "error":     .string(error.localizedDescription),
                    "errorType": .string(String(describing: type(of: error))),
                ]
            )
            throw error
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

/// Represents a step in the execution plan.
public struct ExecutionStep {
    public let id:       String
    public let toolName: String
    public let action:   String
    public let inputs:   [String: Any]

    public init(id: String, toolName: String, action: String = "", inputs: [String: Any] = [:]) {
        self.id       = id
        self.toolName = toolName
        self.action   = action
        self.inputs   = inputs
    }
}

// MARK: - Payload helper

extension Dictionary where Key == String, Value == Any {
    func asJSONPayload() -> [String: JSONValue] {
        reduce(into: [:]) { result, pair in
            result[pair.key] = jsonValue(from: pair.value)
        }
    }
}

private func jsonValue(from value: Any) -> JSONValue {
    switch value {
    case let s as String:       return .string(s)
    case let i as Int:          return .int(i)
    case let d as Double:       return .double(d)
    case let b as Bool:         return .bool(b)
    case let dict as [String: Any]:
        return .object(dict.reduce(into: [:]) { $0[$1.key] = jsonValue(from: $1.value) })
    case let arr as [Any]:
        return .array(arr.map { jsonValue(from: $0) })
    default:
        return .string("\(value)")
    }
}
