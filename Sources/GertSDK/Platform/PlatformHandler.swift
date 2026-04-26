import Foundation

/// GertToolHandler protocol for platform-specific tool implementations.
public protocol GertToolHandler {
    /// The capability this handler provides
    var capability: String { get }
    
    /// Execute the tool with given inputs
    /// - Parameter inputs: Input parameters as a dictionary
    /// - Returns: Output dictionary
    /// - Throws: If execution fails
    func execute(inputs: [String: Any]) async throws -> [String: Any]
    
    /// Check if this capability is available on the current device
    /// - Returns: true if available, false otherwise
    func checkAvailability() async -> Bool
}

/// Registry for platform handlers
public class PlatformHandlerRegistry {
    public static let shared = PlatformHandlerRegistry()
    
    private var handlers: [GertToolHandler] = []
    
    private init() {
        // Register all built-in handlers
        registerBuiltInHandlers()
    }
    
    /// Register a custom handler
    public func register(_ handler: GertToolHandler) {
        handlers.append(handler)
    }
    
    /// Get handler for a specific capability
    public func handler(for capability: String) -> GertToolHandler? {
        handlers.first { $0.capability == capability }
    }
    
    /// All registered handlers
    public var allHandlers: [GertToolHandler] {
        handlers
    }
    
    private func registerBuiltInHandlers() {
        handlers = [
            CameraHandler(),
            LocationHandler(),
            NFCHandler(),
            BiometricsHandler(),
            BluetoothHandler(),
            NotificationsHandler()
        ]
    }
}
