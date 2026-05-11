//
//  Template.swift
//  GertSDK / Templates
//
//  Swift port of pkg/template in gert-domain-home.
//  Parses + structurally validates a template per
//  specs/templates-v1.md. Materialization lives in Materialize.swift.
//

import Foundation
import Yams

/// Parsed + validated template.
public struct Template {
    public let id: String
    public let version: Int
    public let kind: String
    public let title: String?
    public let description: String?
    public let slots: [Slot]
    public let toggles: [Toggle]
    /// The `routine:` body, preserved as a Yams node so the materializer
    /// walks it in source key order (determinism contract).
    public let routine: Node
    public let file: String

    public struct Slot {
        public let id: String
        public let type: String
        public let required: Bool
        public let defaultValue: Any?
        public let label: String?
        public let params: [String: Any] // type-specific (min/max, options)
    }

    public struct Toggle {
        public let id: String
        public let label: String?
        public let defaultValue: Bool
    }
}

/// Errors raised by the template parser/validator.
public struct TemplateError: Error, CustomStringConvertible {
    public let file: String
    public let line: Int
    public let message: String

    public var description: String {
        if file.isEmpty { return "line \(line): \(message)" }
        return "\(file):\(line): \(message)"
    }
}

private func err(_ file: String, _ line: Int, _ msg: String) -> TemplateError {
    TemplateError(file: file, line: line, message: msg)
}

public enum TemplateParser {
    private static let allowedTopLevel: Set<String> = [
        "id", "version", "kind", "title", "description",
        "slots", "toggles", "routine",
    ]

    public static func parseFile(_ path: String) throws -> Template {
        let body = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(file: path, body: body)
    }

    public static func parse(file: String, body: String) throws -> Template {
        let node: Node
        do {
            guard let n = try Yams.compose(yaml: body) else {
                throw err(file, 0, "empty template document")
            }
            node = n
        } catch let e as TemplateError { throw e }
        catch { throw err(file, 0, "yaml parse: \(error)") }

        guard case let .mapping(root) = node else {
            throw err(file, lineOf(node), "template root must be a map")
        }

        var id = ""
        var version = 0
        var kind = ""
        var title: String?
        var description: String?
        var slots: [Template.Slot] = []
        var toggles: [Template.Toggle] = []
        var routine: Node?

        for (k, v) in root {
            guard case let .scalar(keyScalar) = k else {
                throw err(file, lineOf(k), "non-scalar top-level key")
            }
            let key = keyScalar.string
            if !allowedTopLevel.contains(key) {
                throw err(file, lineOf(k), "unknown top-level key \"\(key)\"")
            }
            switch key {
            case "id": id = scalarString(v) ?? ""
            case "version":
                guard let s = scalarString(v), let n = Int(s) else {
                    throw err(file, lineOf(v), "version must be an integer")
                }
                version = n
            case "kind": kind = scalarString(v) ?? ""
            case "title": title = scalarString(v)
            case "description": description = scalarString(v)
            case "slots": slots = try parseSlots(file: file, node: v)
            case "toggles": toggles = try parseToggles(file: file, node: v)
            case "routine": routine = v
            default: break
            }
        }

        // Required-field checks
        if id.isEmpty { throw err(file, 0, "missing required key: id") }
        if version == 0 { throw err(file, 0, "missing or zero required key: version") }
        switch kind {
        case "routine", "incident": break
        case "":
            throw err(file, 0, "missing required key: kind")
        default:
            throw err(file, 0, "kind must be routine or incident, got \"\(kind)\"")
        }
        guard let routineNode = routine else {
            throw err(file, 0, "missing required key: routine")
        }

        let tpl = Template(
            id: id, version: version, kind: kind,
            title: title, description: description,
            slots: slots, toggles: toggles,
            routine: routineNode, file: file
        )
        try validateBody(tpl: tpl)
        return tpl
    }

    // MARK: - Slots / Toggles

    private static func parseSlots(file: String, node: Node) throws -> [Template.Slot] {
        guard case let .sequence(seq) = node else {
            throw err(file, lineOf(node), "slots must be a list")
        }
        var out: [Template.Slot] = []
        for item in seq {
            guard case let .mapping(m) = item else {
                throw err(file, lineOf(item), "slot entry must be a map")
            }
            var id = ""
            var type = ""
            var required = false
            var defaultValue: Any?
            var label: String?
            var params: [String: Any] = [:]
            for (k, v) in m {
                guard case let .scalar(ks) = k else { continue }
                switch ks.string {
                case "id": id = scalarString(v) ?? ""
                case "type": type = scalarString(v) ?? ""
                case "required": required = (scalarString(v) == "true")
                case "default": defaultValue = nodeToAny(v)
                case "label": label = scalarString(v)
                default: params[ks.string] = nodeToAny(v)
                }
            }
            if id.isEmpty { throw err(file, lineOf(item), "slot missing id") }
            if type.isEmpty { throw err(file, lineOf(item), "slot \"\(id)\" missing type") }
            out.append(.init(
                id: id, type: type, required: required,
                defaultValue: defaultValue, label: label, params: params
            ))
        }
        return out
    }

    private static func parseToggles(file: String, node: Node) throws -> [Template.Toggle] {
        guard case let .sequence(seq) = node else {
            throw err(file, lineOf(node), "toggles must be a list")
        }
        var out: [Template.Toggle] = []
        for item in seq {
            guard case let .mapping(m) = item else {
                throw err(file, lineOf(item), "toggle entry must be a map")
            }
            var id = ""
            var label: String?
            var def = false
            for (k, v) in m {
                guard case let .scalar(ks) = k else { continue }
                switch ks.string {
                case "id": id = scalarString(v) ?? ""
                case "label": label = scalarString(v)
                case "default": def = (scalarString(v) == "true")
                default:
                    throw err(file, lineOf(k), "toggle \"\(id)\": unknown key \"\(ks.string)\"")
                }
            }
            if id.isEmpty { throw err(file, lineOf(item), "toggle missing id") }
            out.append(.init(id: id, label: label, defaultValue: def))
        }
        return out
    }

    // MARK: - Body validation

    private static let slotRefRegex = try! NSRegularExpression(
        pattern: #"\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}"#
    )

    private static func validateBody(tpl: Template) throws {
        // Slot type catalog and dup checks.
        let reg = SlotRegistry.default
        var declaredSlots = Set<String>()
        for s in tpl.slots {
            if declaredSlots.contains(s.id) {
                throw err(tpl.file, 0, "duplicate slot id \"\(s.id)\"")
            }
            declaredSlots.insert(s.id)
            if reg.lookup(s.type) == nil {
                throw err(tpl.file, 0, "slot \"\(s.id)\": unknown type \"\(s.type)\"")
            }
            if s.type == "enum" && s.params["options"] == nil {
                throw err(tpl.file, 0, "slot \"\(s.id)\" (enum) must declare options")
            }
        }
        var declaredToggles = Set<String>()
        for t in tpl.toggles {
            if declaredToggles.contains(t.id) {
                throw err(tpl.file, 0, "duplicate toggle id \"\(t.id)\"")
            }
            declaredToggles.insert(t.id)
        }
        try walkRoutine(file: tpl.file, node: tpl.routine,
                        slots: declaredSlots, toggles: declaredToggles, inKey: false)
    }

    private static func walkRoutine(
        file: String, node: Node,
        slots: Set<String>, toggles: Set<String>, inKey: Bool
    ) throws {
        switch node {
        case let .scalar(s):
            let value = s.string
            let nsValue = value as NSString
            let matches = slotRefRegex.matches(
                in: value, range: NSRange(location: 0, length: nsValue.length)
            )
            for m in matches {
                let id = nsValue.substring(with: m.range(at: 1))
                if !slots.contains(id) {
                    throw err(file, lineOf(node), "{{\(id)}} references undeclared slot")
                }
            }
            if inKey, !matches.isEmpty {
                throw err(file, lineOf(node), "slot interpolation not allowed in map keys")
            }
        case let .mapping(m):
            for (k, v) in m {
                if case let .scalar(ks) = k, ks.string == "when" {
                    guard case let .scalar(vs) = v else {
                        throw err(file, lineOf(v), "when: must be a toggle id (scalar)")
                    }
                    if !toggles.contains(vs.string) {
                        throw err(file, lineOf(v), "when: \"\(vs.string)\" is not a declared toggle")
                    }
                    continue
                }
                try walkRoutine(file: file, node: k, slots: slots, toggles: toggles, inKey: true)
                try walkRoutine(file: file, node: v, slots: slots, toggles: toggles, inKey: false)
            }
        case let .sequence(seq):
            for c in seq {
                try walkRoutine(file: file, node: c, slots: slots, toggles: toggles, inKey: false)
            }
        case .alias:
            throw err(file, lineOf(node), "yaml anchors/aliases are not allowed in templates")
        @unknown default:
            return
        }
    }
}

// MARK: - Node helpers

internal func lineOf(_ n: Node) -> Int { n.mark?.line ?? 0 }

internal func scalarString(_ n: Node) -> String? {
    if case let .scalar(s) = n { return s.string }
    return nil
}

/// Best-effort untyped conversion of a Yams Node to a Swift Any value.
/// Used for slot params and binding values.
internal func nodeToAny(_ n: Node) -> Any? {
    switch n {
    case let .scalar(s):
        // Try int, then bool, then double, fall back to string.
        if let i = Int(s.string) { return i }
        if s.string == "true" { return true }
        if s.string == "false" { return false }
        if let d = Double(s.string) { return d }
        return s.string
    case let .sequence(seq):
        return seq.map { nodeToAny($0) as Any }
    case let .mapping(m):
        var out: [String: Any] = [:]
        for (k, v) in m {
            if case let .scalar(ks) = k {
                out[ks.string] = nodeToAny(v) as Any
            }
        }
        return out
    case .alias:
        return nil
    @unknown default:
        return nil
    }
}
