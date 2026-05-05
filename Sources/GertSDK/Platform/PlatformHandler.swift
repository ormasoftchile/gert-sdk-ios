import Foundation

// GertToolHandler is the contract every native tool implementation
// must satisfy. The runtime looks up handlers by `toolName`
// (e.g. "camera.capture", "location.read") rather than by capability,
// because runbooks reference tools by name.
public protocol GertToolHandler: Sendable {
    /// The fully-qualified tool name this handler implements
    /// (e.g. "camera.capture").
    var toolName: String { get }

    /// Execute the tool. `action` and `args` come straight from the
    /// runbook step. Returns a dictionary that becomes the step's
    /// captured outputs.
    func execute(action: String, args: [String: Any]) async throws -> [String: Any]

    /// Quick check that the underlying capability is available on
    /// this device. Default returns true.
    func isAvailable() async -> Bool
}

public extension GertToolHandler {
    func isAvailable() async -> Bool { true }
}

// HandlerRegistry is the per-session map of toolName → handler.
// Hosts (apps, tests) register handlers explicitly; the SDK does
// NOT pre-register the iOS-only platform handlers because some
// targets (mac unit tests, a domain validator) don't need them.
public final class HandlerRegistry: @unchecked Sendable {
    private var handlers: [String: GertToolHandler] = [:]

    public init() {}

    public func register(_ handler: GertToolHandler) {
        handlers[handler.toolName] = handler
    }

    public func handler(for toolName: String) -> GertToolHandler? {
        handlers[toolName]
    }

    public var registeredTools: [String] {
        Array(handlers.keys).sorted()
    }
}
