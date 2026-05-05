import Foundation

// JSONValue is a minimal recursive enum used to carry untyped values
// produced by YAML/JSON decoding. We use it instead of `[String: Any]`
// in the public API so the values cross actor/sendable boundaries
// safely and stay Codable end-to-end.
public enum JSONValue: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let v):    try c.encode(v)
        case .int(let v):     try c.encode(v)
        case .double(let v):  try c.encode(v)
        case .string(let v):  try c.encode(v)
        case .array(let v):   try c.encode(v)
        case .object(let v):  try c.encode(v)
        }
    }
}

public extension JSONValue {
    /// Untyped Foundation value, useful when bridging to platform APIs.
    var anyValue: Any {
        switch self {
        case .null:            return NSNull()
        case .bool(let v):     return v
        case .int(let v):      return v
        case .double(let v):   return v
        case .string(let v):   return v
        case .array(let v):    return v.map { $0.anyValue }
        case .object(let v):   return v.mapValues { $0.anyValue }
        }
    }

    init(any value: Any) {
        switch value {
        case is NSNull:                self = .null
        case let v as Bool:            self = .bool(v)
        case let v as Int:             self = .int(v)
        case let v as Double:          self = .double(v)
        case let v as String:          self = .string(v)
        case let v as [Any]:           self = .array(v.map { JSONValue(any: $0) })
        case let v as [String: Any]:   self = .object(v.mapValues { JSONValue(any: $0) })
        default:                       self = .string(String(describing: value))
        }
    }
}
