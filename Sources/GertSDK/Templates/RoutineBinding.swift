//
//  RoutineBinding.swift
//  GertSDK / Templates
//
//  Encodes a *template-backed* routine entry — the unmaterialized form
//  the gert-domain-home loader expects in a property file. Use this
//  instead of the materialized Materialize output when persisting on
//  device for later compilation by the Go loader.
//
//  The shape mirrors model.Routine fields: { id, template, template_version,
//  bindings, toggles }. Materialized YAML is also fine to write to disk
//  (see Materializer / FileRoutineStore), but the binding form is
//  smaller, schema-stable, and lets the compiler re-validate against
//  the latest property context.
//

import Foundation

public struct RoutineBinding {
    public let id: String
    public let templateID: String
    public let templateVersion: Int
    public let bindings: [String: Any]
    public let toggles: [String: Bool]

    public init(
        id: String, templateID: String, templateVersion: Int,
        bindings: [String: Any] = [:], toggles: [String: Bool] = [:]
    ) {
        self.id = id
        self.templateID = templateID
        self.templateVersion = templateVersion
        self.bindings = bindings
        self.toggles = toggles
    }
}

public enum RoutineBindingEncoder {
    /// Encode a single binding as a YAML mapping suitable for inclusion
    /// under a `routines:` list in a `.home.yaml` property file.
    /// Output uses the same in-house writer as the materializer.
    public static func encode(_ b: RoutineBinding) -> String {
        var entries: [(String, EmitNode)] = []
        entries.append(("id",               .scalar(b.id, .plain)))
        entries.append(("template",         .scalar(b.templateID, .plain)))
        entries.append(("template_version", .scalar(String(b.templateVersion), .plain)))

        // bindings: declared-order-stable. Keys sorted ascending — this
        // is the contract iOS writes; the loader doesn't care about
        // bindings key order, only about set/values.
        if !b.bindings.isEmpty {
            let sorted = b.bindings.keys.sorted()
            let mapItems: [(String, EmitNode)] = sorted.map { k in
                (k, .scalar(scalarString(b.bindings[k]!), styleFor(b.bindings[k]!)))
            }
            entries.append(("bindings", .map(mapItems)))
        }

        if !b.toggles.isEmpty {
            let sorted = b.toggles.keys.sorted()
            let mapItems: [(String, EmitNode)] = sorted.map { k in
                (k, .scalar(b.toggles[k]! ? "true" : "false", .plain))
            }
            entries.append(("toggles", .map(mapItems)))
        }

        return YAMLWriter.emit(.map(entries))
    }

    /// Encode a list of bindings as the body of a `routines:` block.
    /// The output is a sequence of mappings; callers prepend whatever
    /// outer keys their property file needs.
    public static func encodeList(_ bs: [RoutineBinding]) -> String {
        let items: [EmitNode] = bs.map { b in
            // Reuse single-encoder by parsing back into entries.
            // Simpler: build the same .map() inline.
            var entries: [(String, EmitNode)] = []
            entries.append(("id",               .scalar(b.id, .plain)))
            entries.append(("template",         .scalar(b.templateID, .plain)))
            entries.append(("template_version", .scalar(String(b.templateVersion), .plain)))
            if !b.bindings.isEmpty {
                let sorted = b.bindings.keys.sorted()
                entries.append(("bindings", .map(sorted.map { k in
                    (k, .scalar(scalarString(b.bindings[k]!), styleFor(b.bindings[k]!)))
                })))
            }
            if !b.toggles.isEmpty {
                let sorted = b.toggles.keys.sorted()
                entries.append(("toggles", .map(sorted.map { k in
                    (k, .scalar(b.toggles[k]! ? "true" : "false", .plain))
                })))
            }
            return .map(entries)
        }
        return YAMLWriter.emit(.seq(items))
    }
}

// MARK: - Value coercion

private func scalarString(_ v: Any) -> String {
    switch v {
    case let s as String: return s
    case let b as Bool:   return b ? "true" : "false"
    case let i as Int:    return String(i)
    case let i as Int64:  return String(i)
    case let d as Double:
        if d.rounded() == d && abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    default: return "\(v)"
    }
}

/// Strings that look numeric or boolean must be quoted to round-trip
/// as strings; unambiguous numbers/booleans go plain.
private func styleFor(_ v: Any) -> ScalarStyle {
    switch v {
    case is Int, is Int64, is Bool, is Double:
        return .plain
    case let s as String:
        // Quote if the string would otherwise parse as a number or bool.
        if s == "true" || s == "false" { return .doubleQuoted }
        if Int(s) != nil || Double(s) != nil { return .doubleQuoted }
        return .plain
    default:
        return .plain
    }
}
