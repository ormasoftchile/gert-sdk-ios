import Foundation

public struct RunbookEntry: Codable {
    public let name: String
    public let version: String
    public let description: String?
    public let requiresCapabilities: [String]?
    public let steps: [RunbookStep]
    
    public var requiredCapabilities: [String] {
        requiresCapabilities ?? []
    }
    
    enum CodingKeys: String, CodingKey {
        case name, version, description, steps
        case requiresCapabilities = "requires-capabilities"
    }
}

public struct RunbookStep: Codable {
    public let id: String
    public let name: String
    public let tool: String
    public let action: String
    public let args: [String: AnyCodable]?
    public let onSuccess: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, tool, action, args
        case onSuccess = "on-success"
    }
}

/// Helper type for decoding heterogeneous args dictionaries
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
