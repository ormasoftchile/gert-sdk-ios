import Foundation

/// Capability represents a platform capability token.
public struct Capability: RawRepresentable, Codable, Hashable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    // Standard platform capabilities
    public static let camera = Capability(rawValue: "capability/camera")
    public static let location = Capability(rawValue: "capability/location")
    public static let nfc = Capability(rawValue: "capability/nfc")
    public static let biometrics = Capability(rawValue: "capability/biometrics")
    public static let bluetooth = Capability(rawValue: "capability/bluetooth")
    public static let notifications = Capability(rawValue: "capability/notifications")
    
    /// All built-in capabilities
    public static let allBuiltIn: [Capability] = [
        .camera,
        .location,
        .nfc,
        .biometrics,
        .bluetooth,
        .notifications
    ]
}
