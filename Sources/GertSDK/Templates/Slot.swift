//
//  Slot.swift
//  GertSDK / Templates
//
//  Swift port of pkg/slot in gert-domain-home. The closed catalog of
//  slot types from specs/templates-v1.md. Adding a type requires
//  editing `SlotRegistry.default` and adding tests.
//
//  This file MUST stay in lock-step with the Go reference; the
//  cross-platform corpus at testdata/golden/templates/ is the contract.
//

import Foundation

/// Property-level information that some slot types need to validate
/// references (zones, assets). Implementations are supplied by the
/// caller; this module does not depend on the property model directly.
public protocol SlotContext {
    func hasZone(_ id: String) -> Bool
    func hasAsset(_ id: String) -> Bool
}

/// Errors raised by slot validation.
public enum SlotError: Error, Equatable, CustomStringConvertible {
    case wrongType(slotType: String, expected: String, got: String)
    case empty(slotType: String)
    case missingContext(slotType: String)
    case undeclaredZone(String)
    case undeclaredAsset(String)
    case patternMismatch(slotType: String, value: String, pattern: String)
    case lengthOutOfRange(slotType: String, length: Int, range: String)
    case containsNewline(slotType: String)
    case belowMin(value: Int64, min: Int64)
    case aboveMax(value: Int64, max: Int64)
    case enumMissingOptions
    case enumOptionsEmpty
    case enumValueNotInOptions(value: String, options: [String])

    public var description: String {
        switch self {
        case let .wrongType(t, expected, got):
            return "\(t) requires \(expected), got \(got)"
        case let .empty(t):
            return "\(t) requires a non-empty string"
        case let .missingContext(t):
            return "\(t) requires a property context"
        case let .undeclaredZone(s):
            return "zone_ref \"\(s)\" is not declared in property zones"
        case let .undeclaredAsset(s):
            return "asset_ref \"\(s)\" is not declared in property assets"
        case let .patternMismatch(t, v, p):
            return "\(t) \"\(v)\" does not match \(p)"
        case let .lengthOutOfRange(t, n, r):
            return "\(t) length must be \(r), got \(n)"
        case let .containsNewline(t):
            return "\(t) must not contain newlines"
        case let .belowMin(v, m):
            return "int \(v) is below min \(m)"
        case let .aboveMax(v, m):
            return "int \(v) is above max \(m)"
        case .enumMissingOptions:
            return "enum slot must declare options"
        case .enumOptionsEmpty:
            return "enum options must be a non-empty list of strings"
        case let .enumValueNotInOptions(v, opts):
            return "enum value \"\(v)\" is not one of \(opts)"
        }
    }
}

/// A slot value supplied by the user. The materializer decodes binding
/// values from YAML into this enum so the slot validators have a single
/// concrete type to switch on.
public enum SlotValue: Equatable {
    case string(String)
    case int(Int64)
    case bool(Bool)
    case double(Double)

    /// Best-effort coercion from `Any?` (e.g., values produced by Yams
    /// untyped decoding).
    public static func from(_ v: Any?) -> SlotValue? {
        switch v {
        case let s as String: return .string(s)
        case let i as Int: return .int(Int64(i))
        case let i as Int64: return .int(i)
        case let i as UInt: return .int(Int64(i))
        case let b as Bool: return .bool(b)
        case let d as Double: return .double(d)
        case let f as Float: return .double(Double(f))
        default: return nil
        }
    }
}

/// One entry in the closed slot type catalog.
public protocol SlotType {
    /// The catalog name as it appears in template YAML.
    var name: String { get }

    /// Validate `value` for this slot, given the slot's declared
    /// `params` (e.g., min/max for int, options for enum) and the
    /// property `context`.
    func validate(_ value: SlotValue, params: [String: Any], context: SlotContext?) throws

    /// Produce the canonical string form of a previously-validated
    /// value for interpolation into a template.
    func marshal(_ value: SlotValue) -> String
}

/// Closed registry of slot types. Adding a type requires editing
/// `SlotRegistry.default` and adding tests; there is no public
/// `register` method by design.
public struct SlotRegistry {
    private let types: [String: SlotType]

    private init(_ types: [SlotType]) {
        var m: [String: SlotType] = [:]
        for t in types { m[t.name] = t }
        self.types = m
    }

    public func lookup(_ name: String) -> SlotType? { types[name] }

    public static let `default` = SlotRegistry([
        ZoneRefSlot(),
        AssetRefSlot(),
        CadenceSlot(),
        DurationSlot(),
        StringShortSlot(),
        IntSlot(),
        EnumSlot(),
    ])
}

// MARK: - Types

private struct ZoneRefSlot: SlotType {
    let name = "zone_ref"
    func validate(_ value: SlotValue, params: [String: Any], context: SlotContext?) throws {
        guard case let .string(s) = value else {
            throw SlotError.wrongType(slotType: name, expected: "string", got: "\(value)")
        }
        if s.isEmpty { throw SlotError.empty(slotType: name) }
        guard let ctx = context else { throw SlotError.missingContext(slotType: name) }
        if !ctx.hasZone(s) { throw SlotError.undeclaredZone(s) }
    }
    func marshal(_ value: SlotValue) -> String {
        if case let .string(s) = value { return s }
        return ""
    }
}

private struct AssetRefSlot: SlotType {
    let name = "asset_ref"
    func validate(_ value: SlotValue, params: [String: Any], context: SlotContext?) throws {
        guard case let .string(s) = value else {
            throw SlotError.wrongType(slotType: name, expected: "string", got: "\(value)")
        }
        if s.isEmpty { throw SlotError.empty(slotType: name) }
        guard let ctx = context else { throw SlotError.missingContext(slotType: name) }
        if !ctx.hasAsset(s) { throw SlotError.undeclaredAsset(s) }
    }
    func marshal(_ value: SlotValue) -> String {
        if case let .string(s) = value { return s }
        return ""
    }
}

/// Shared duration regex: `\d+(m|h|d|w)`.
private let durationPattern = #"^\d+(m|h|d|w)$"#

private func validateDurationLike(_ name: String, _ value: SlotValue) throws {
    guard case let .string(s) = value else {
        throw SlotError.wrongType(slotType: name, expected: "string", got: "\(value)")
    }
    if s.range(of: durationPattern, options: .regularExpression) == nil {
        throw SlotError.patternMismatch(slotType: name, value: s, pattern: #"\d+(m|h|d|w)"#)
    }
}

private struct CadenceSlot: SlotType {
    let name = "cadence"
    func validate(_ value: SlotValue, params: [String: Any], context: SlotContext?) throws {
        try validateDurationLike(name, value)
    }
    func marshal(_ value: SlotValue) -> String {
        if case let .string(s) = value { return s }; return ""
    }
}

private struct DurationSlot: SlotType {
    let name = "duration"
    func validate(_ value: SlotValue, params: [String: Any], context: SlotContext?) throws {
        try validateDurationLike(name, value)
    }
    func marshal(_ value: SlotValue) -> String {
        if case let .string(s) = value { return s }; return ""
    }
}

private struct StringShortSlot: SlotType {
    let name = "string_short"
    func validate(_ value: SlotValue, params: [String: Any], context: SlotContext?) throws {
        guard case let .string(s) = value else {
            throw SlotError.wrongType(slotType: name, expected: "string", got: "\(value)")
        }
        if s.count < 1 || s.count > 80 {
            throw SlotError.lengthOutOfRange(slotType: name, length: s.count, range: "1..80")
        }
        if s.contains("\n") || s.contains("\r") {
            throw SlotError.containsNewline(slotType: name)
        }
    }
    func marshal(_ value: SlotValue) -> String {
        if case let .string(s) = value { return s }; return ""
    }
}

private struct IntSlot: SlotType {
    let name = "int"
    func validate(_ value: SlotValue, params: [String: Any], context: SlotContext?) throws {
        guard case let .int(n) = value else {
            throw SlotError.wrongType(slotType: name, expected: "integer", got: "\(value)")
        }
        if let raw = params["min"], let m = toInt64(raw), n < m {
            throw SlotError.belowMin(value: n, min: m)
        }
        if let raw = params["max"], let m = toInt64(raw), n > m {
            throw SlotError.aboveMax(value: n, max: m)
        }
    }
    func marshal(_ value: SlotValue) -> String {
        if case let .int(n) = value { return String(n) }
        return ""
    }
}

private struct EnumSlot: SlotType {
    let name = "enum"
    func validate(_ value: SlotValue, params: [String: Any], context: SlotContext?) throws {
        guard case let .string(s) = value else {
            throw SlotError.wrongType(slotType: name, expected: "string", got: "\(value)")
        }
        guard let raw = params["options"] else { throw SlotError.enumMissingOptions }
        guard let opts = toStringArray(raw), !opts.isEmpty else { throw SlotError.enumOptionsEmpty }
        if !opts.contains(s) { throw SlotError.enumValueNotInOptions(value: s, options: opts) }
    }
    func marshal(_ value: SlotValue) -> String {
        if case let .string(s) = value { return s }; return ""
    }
}

// MARK: - Helpers

private func toInt64(_ v: Any) -> Int64? {
    switch v {
    case let i as Int: return Int64(i)
    case let i as Int64: return i
    case let i as UInt: return Int64(i)
    case let i as UInt64: return Int64(i)
    case let s as String: return Int64(s)
    default: return nil
    }
}

private func toStringArray(_ v: Any) -> [String]? {
    if let xs = v as? [String] { return xs }
    if let xs = v as? [Any] {
        var out: [String] = []
        out.reserveCapacity(xs.count)
        for x in xs {
            guard let s = x as? String else { return nil }
            out.append(s)
        }
        return out
    }
    return nil
}
