import Foundation

// CollectorResolver is what the host plugs in to fulfill collector
// steps (the human-facing forms in a routine). Tests pass a closure
// that returns canned values; an iOS app passes a closure that pushes
// a SwiftUI form and waits for submission.
public protocol CollectorResolver: Sendable {
    func resolve(step: Step, runID: String) async throws -> [String: JSONValue]
}

// FailingCollectorResolver fails every collector. Useful as a default
// when the host hasn't supplied one and no collector steps are
// expected (pure tool runbooks).
public struct FailingCollectorResolver: CollectorResolver {
    public init() {}
    public func resolve(step: Step, runID: String) async throws -> [String: JSONValue] {
        throw StepExecutionError.noCollectorResolver(step.id)
    }
}

public enum StepExecutionError: Error, LocalizedError {
    case unsupportedStepType(String, stepID: String)
    case toolHandlerMissing(String)
    case toolMissingRef(stepID: String)
    case noCollectorResolver(String)
    case toolFailed(String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .unsupportedStepType(let t, let id):
            return "Step '\(id)' has unsupported type '\(t)'"
        case .toolHandlerMissing(let name):
            return "No registered handler for tool '\(name)'"
        case .toolMissingRef(let id):
            return "Tool step '\(id)' is missing a 'tool:' reference"
        case .noCollectorResolver(let id):
            return "Collector step '\(id)' has no resolver registered"
        case .toolFailed(let name, let err):
            return "Tool '\(name)' failed: \(err.localizedDescription)"
        }
    }
}

// StepExecutor runs one step, emits the right lifecycle events, and
// returns the step's captured outputs. It does not interpret the
// runbook flow itself — that's RunSession's job.
struct StepExecutor {
    let handlers: HandlerRegistry
    let collectorResolver: CollectorResolver

    func execute(
        step: Step,
        index: Int,
        runID: String,
        broker: EventBroker
    ) async throws -> [String: JSONValue] {
        switch step.type {
        case "tool":
            return try await executeTool(step: step, index: index, runID: runID, broker: broker)
        case "collector":
            return try await executeCollector(step: step, runID: runID)
        case "noop":
            return [:]
        default:
            throw StepExecutionError.unsupportedStepType(step.type, stepID: step.id)
        }
    }

    private func executeTool(
        step: Step,
        index: Int,
        runID: String,
        broker: EventBroker
    ) async throws -> [String: JSONValue] {
        guard let ref = step.tool else {
            throw StepExecutionError.toolMissingRef(stepID: step.id)
        }
        guard let handler = handlers.handler(for: ref.name) else {
            throw StepExecutionError.toolHandlerMissing(ref.name)
        }

        let args = (ref.args ?? [:]).mapValues { $0.anyValue }

        await broker.emit(
            kind: RuntimeEvent.toolInvoked,
            runID: runID,
            stepID: step.id,
            stepIndex: index,
            toolName: ref.name,
            action: ref.action,
            payload: ref.args
        )

        do {
            let raw = try await handler.execute(action: ref.action, args: args)
            let outputs = raw.mapValues { JSONValue(any: $0) }
            await broker.emit(
                kind: RuntimeEvent.toolCompleted,
                runID: runID,
                stepID: step.id,
                stepIndex: index,
                toolName: ref.name,
                action: ref.action,
                payload: outputs
            )
            return outputs
        } catch {
            await broker.emit(
                kind: RuntimeEvent.toolFailed,
                runID: runID,
                stepID: step.id,
                stepIndex: index,
                toolName: ref.name,
                action: ref.action,
                payload: ["error": .string(error.localizedDescription)]
            )
            throw StepExecutionError.toolFailed(ref.name, underlying: error)
        }
    }

    private func executeCollector(
        step: Step,
        runID: String
    ) async throws -> [String: JSONValue] {
        return try await collectorResolver.resolve(step: step, runID: runID)
    }
}
