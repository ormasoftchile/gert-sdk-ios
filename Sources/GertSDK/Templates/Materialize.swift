//
//  Materialize.swift
//  GertSDK / Templates
//
//  Swift port of pkg/materialize. Walks a parsed Template's routine
//  body, applies bindings + toggles per specs/templates-v1.md, and
//  emits a byte-deterministic YAML document.
//
//  Determinism strategy:
//  Rather than depend on a third-party emitter producing bytes
//  identical to Go's yaml.v3, this port (and eventually the Go ref
//  too) emit through a minimal in-house writer that controls every
//  formatting choice. The writer covers only the subset of YAML the
//  template grammar can produce.
//

import Foundation
import Yams

public struct MaterializeInput {
    public let template: Template
    public let routineID: String
    public let bindings: [String: Any]
    public let toggles: [String: Bool]
    public let context: SlotContext?

    public init(
        template: Template,
        routineID: String,
        bindings: [String: Any] = [:],
        toggles: [String: Bool] = [:],
        context: SlotContext? = nil
    ) {
        self.template = template
        self.routineID = routineID
        self.bindings = bindings
        self.toggles = toggles
        self.context = context
    }
}

public struct MaterializeResult {
    public let bytes: String
    public let bindings: [String: Any]
    public let toggles: [String: Bool]
}

public enum MaterializeError: Error, CustomStringConvertible {
    case missing(String)
    case slotMissing(String)
    case slotInvalid(String, Error)
    case toggleNotDeclared(String)
    case bindingNotDeclared(String)
    case unsupportedNode

    public var description: String {
        switch self {
        case let .missing(s): return s
        case let .slotMissing(id): return "required slot \"\(id)\" has no binding"
        case let .slotInvalid(id, e): return "slot \"\(id)\": \(e)"
        case let .toggleNotDeclared(id): return "toggle \"\(id)\" is not a declared toggle"
        case let .bindingNotDeclared(id): return "binding \"\(id)\" is not a declared slot"
        case .unsupportedNode: return "unsupported node kind in template body"
        }
    }
}

public enum Materializer {
    public static func materialize(_ input: MaterializeInput) throws -> MaterializeResult {
        if input.routineID.isEmpty { throw MaterializeError.missing("routine id is required") }

        let reg = SlotRegistry.default
        let values = try resolveBindings(template: input.template, supplied: input.bindings,
                                         registry: reg, context: input.context)
        let flags  = try resolveToggles(template: input.template, supplied: input.toggles)

        // Walk + materialize the routine body.
        guard let body = try walkAndMaterialize(node: input.template.routine,
                                                values: values, flags: flags, registry: reg) else {
            throw MaterializeError.missing("template routine produced empty body")
        }
        guard case let .map(bodyEntries) = body else {
            throw MaterializeError.missing("template routine must be a map at top level")
        }

        // Final structure: id: <RoutineID>  + body...  + metadata
        var entries: [(String, EmitNode)] = []
        entries.append(("id", .scalar(input.routineID, .plain)))
        entries.append(contentsOf: bodyEntries)
        entries.append(("metadata", provenance(template: input.template,
                                               values: values, flags: flags)))

        let bytes = YAMLWriter.emit(.map(entries))
        return MaterializeResult(bytes: bytes, bindings: values, toggles: flags)
    }

    // MARK: - Resolution

    private static func resolveBindings(
        template: Template, supplied: [String: Any],
        registry: SlotRegistry, context: SlotContext?
    ) throws -> [String: Any] {
        var out: [String: Any] = [:]
        let declared = Set(template.slots.map { $0.id })

        for s in template.slots {
            let raw: Any?
            if let v = supplied[s.id] {
                raw = v
            } else if let d = s.defaultValue {
                raw = d
            } else if s.required {
                throw MaterializeError.slotMissing(s.id)
            } else {
                continue
            }
            guard let value = SlotValue.from(raw) else {
                throw MaterializeError.slotInvalid(s.id,
                    SlotError.wrongType(slotType: s.type, expected: "supported type", got: "\(type(of: raw!))"))
            }
            guard let tp = registry.lookup(s.type) else {
                throw MaterializeError.slotInvalid(s.id,
                    SlotError.wrongType(slotType: s.type, expected: "known type", got: s.type))
            }
            do {
                try tp.validate(value, params: s.params, context: context)
            } catch {
                throw MaterializeError.slotInvalid(s.id, error)
            }
            out[s.id] = raw
        }

        for k in supplied.keys {
            if !declared.contains(k) { throw MaterializeError.bindingNotDeclared(k) }
        }
        return out
    }

    private static func resolveToggles(
        template: Template, supplied: [String: Bool]
    ) throws -> [String: Bool] {
        var out: [String: Bool] = [:]
        let declared = Set(template.toggles.map { $0.id })

        for t in template.toggles {
            out[t.id] = supplied[t.id] ?? t.defaultValue
        }
        for k in supplied.keys {
            if !declared.contains(k) { throw MaterializeError.toggleNotDeclared(k) }
        }
        return out
    }

    // MARK: - Tree walk

    /// Returns the materialized node, or nil if the input node should be
    /// dropped entirely (because a child carried `when:<false>`).
    private static func walkAndMaterialize(
        node: Node, values: [String: Any], flags: [String: Bool], registry: SlotRegistry
    ) throws -> EmitNode? {
        // If the mapping carries when:<false>, drop the entire node.
        if case let .mapping(m) = node {
            for (k, v) in m {
                if case let .scalar(ks) = k, ks.string == "when",
                   case let .scalar(vs) = v {
                    let toggleVal = flags[vs.string] ?? false
                    if !toggleVal { return nil }
                }
            }
        }

        switch node {
        case let .scalar(s):
            let style = quotingStyle(for: s)
            let interp = interpolate(s.string, values: values)
            return .scalar(interp, style)
        case let .mapping(m):
            var entries: [(String, EmitNode)] = []
            for (k, v) in m {
                guard case let .scalar(ks) = k else { continue }
                if ks.string == "when" { continue } // strip the gate marker
                if let nv = try walkAndMaterialize(node: v, values: values, flags: flags, registry: registry) {
                    entries.append((ks.string, nv))
                }
            }
            return .map(entries)
        case let .sequence(seq):
            var out: [EmitNode] = []
            for c in seq {
                if let nc = try walkAndMaterialize(node: c, values: values, flags: flags, registry: registry) {
                    out.append(nc)
                }
            }
            return .seq(out)
        case .alias:
            throw MaterializeError.unsupportedNode
        @unknown default:
            throw MaterializeError.unsupportedNode
        }
    }

    /// Determine the quoting style for a scalar based on its source style,
    /// mirroring the Go materializer's preserve-source-style behavior.
    private static func quotingStyle(for s: Node.Scalar) -> ScalarStyle {
        switch s.style {
        case .doubleQuoted: return .doubleQuoted
        case .singleQuoted: return .singleQuoted
        default: return .plain
        }
    }

    // MARK: - Interpolation

    private static let slotRefRegex = try! NSRegularExpression(
        pattern: #"\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}"#
    )

    private static func interpolate(_ s: String, values: [String: Any]) -> String {
        let ns = s as NSString
        let matches = slotRefRegex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return s }

        var out = ""
        var cursor = 0
        for m in matches {
            let id = ns.substring(with: m.range(at: 1))
            let r = m.range
            if r.location > cursor {
                out += ns.substring(with: NSRange(location: cursor, length: r.location - cursor))
            }
            if let v = values[id] {
                out += marshalAny(v)
            }
            cursor = r.location + r.length
        }
        if cursor < ns.length {
            out += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return out
    }

    private static func marshalAny(_ v: Any) -> String {
        switch v {
        case let s as String: return s
        case let b as Bool:   return b ? "true" : "false"
        case let i as Int:    return String(i)
        case let i as Int64:  return String(i)
        case let d as Double:
            // Match Go's strconv.FormatFloat(d, 'f', -1, 64)
            if d.rounded() == d && abs(d) < 1e15 {
                return String(Int64(d))
            }
            return String(d)
        default: return "\(v)"
        }
    }

    // MARK: - Provenance

    private static func provenance(
        template: Template, values: [String: Any], flags: [String: Bool]
    ) -> EmitNode {
        var bindings: [(String, EmitNode)] = []
        for s in template.slots {
            if let v = values[s.id] {
                bindings.append((s.id, .scalar(marshalAny(v), .plain)))
            }
        }
        var toggles: [(String, EmitNode)] = []
        for t in template.toggles {
            let b = flags[t.id] ?? t.defaultValue
            toggles.append((t.id, .scalar(b ? "true" : "false", .plain)))
        }
        return .map([
            ("template_id",       .scalar(template.id, .plain)),
            ("template_version",  .scalar(String(template.version), .plain)),
            ("template_bindings", .map(bindings)),
            ("template_toggles",  .map(toggles)),
        ])
    }
}
