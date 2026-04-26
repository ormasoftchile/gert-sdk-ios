import Foundation

/// ToolDefinition represents a tool from the kit's tool catalog.
public struct ToolDefinition: Codable {
    public let name: String
    public let description: String?
    public let requiresCapabilities: [String]?
    public let impl: PlatformImplBlock?
    
    /// Returns the iOS implementation if available
    public var iosImpl: PlatformImpl? {
        impl?.ios
    }
    
    /// Check if this tool has an iOS implementation
    public var hasIOSImpl: Bool {
        iosImpl != nil
    }
    
    /// Required capabilities for this tool
    public var requiredCapabilities: [String] {
        requiresCapabilities ?? []
    }
    
    enum CodingKeys: String, CodingKey {
        case name, description
        case requiresCapabilities = "requires-capabilities"
        case impl
    }
}

/// PlatformImplBlock contains implementations for different platforms.
public struct PlatformImplBlock: Codable {
    public let ios: PlatformImpl?
    public let android: PlatformImpl?
    
    enum CodingKeys: String, CodingKey {
        case ios, android
    }
}

/// PlatformImpl describes how to execute a tool on a specific platform.
public struct PlatformImpl: Codable {
    public let transport: Transport
    public let handler: String
    public let config: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case transport, handler, config
    }
}

/// Transport describes how the tool implementation is invoked.
public enum Transport: String, Codable {
    case nativeSDK = "native-sdk"
    case http = "http"
}
