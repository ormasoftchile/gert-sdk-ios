//
//  YAMLWriter.swift
//  GertSDK / Templates
//
//  A minimal block-style YAML emitter used by the materializer to
//  guarantee byte-identical output across language ports.
//
//  Scope:
//    - Indented block mappings and sequences only (no flow style).
//    - Two-space indent. No line-width wrapping. Trailing newline.
//    - Scalars emitted plain unless the source style was quoted, or
//      the value requires quoting to round-trip safely.
//    - Sequence items at indent N: a "- " prefix on the same line
//      as the first scalar/key; nested children indent +2 from "- ".
//    - Mapping keys are always plain.
//

import Foundation

public enum ScalarStyle {
    case plain
    case singleQuoted
    case doubleQuoted
}

/// In-memory representation of the emit tree.
public indirect enum EmitNode {
    case scalar(String, ScalarStyle)
    case map([(String, EmitNode)])
    case seq([EmitNode])
}

public enum YAMLWriter {
    public static func emit(_ root: EmitNode) -> String {
        var out = ""
        writeNode(root, indent: 0, into: &out, asMapValue: false)
        if !out.hasSuffix("\n") { out.append("\n") }
        return out
    }

    private static func writeNode(_ n: EmitNode, indent: Int, into out: inout String, asMapValue: Bool) {
        switch n {
        case let .scalar(s, style):
            out.append(emitScalar(s, style: style))
            out.append("\n")
        case let .map(entries):
            if entries.isEmpty {
                out.append("{}\n")
                return
            }
            for (i, (k, v)) in entries.enumerated() {
                if i > 0 || asMapValue {
                    out.append(String(repeating: " ", count: indent))
                }
                out.append(k)
                out.append(":")
                writeChild(v, indent: indent, into: &out)
                if asMapValue && i == 0 {
                    asMapValueResetMarker(&out) // no-op; structure-only marker
                }
                _ = i
            }
        case let .seq(items):
            if items.isEmpty {
                out.append("[]\n")
                return
            }
            for (i, item) in items.enumerated() {
                if i > 0 || asMapValue {
                    out.append(String(repeating: " ", count: indent))
                }
                out.append("- ")
                writeSeqChild(item, indent: indent + 2, into: &out)
            }
        }
    }

    private static func asMapValueResetMarker(_ out: inout String) { /* no-op */ }

    /// Writes the value of a map entry. Decides between same-line scalar
    /// and a newline-prefixed nested structure.
    private static func writeChild(_ v: EmitNode, indent: Int, into out: inout String) {
        switch v {
        case let .scalar(s, style):
            out.append(" ")
            out.append(emitScalar(s, style: style))
            out.append("\n")
        case let .map(entries):
            if entries.isEmpty {
                out.append(" {}\n")
                return
            }
            out.append("\n")
            for (k, val) in entries {
                out.append(String(repeating: " ", count: indent + 2))
                out.append(k)
                out.append(":")
                writeChild(val, indent: indent + 2, into: &out)
            }
        case let .seq(items):
            if items.isEmpty {
                out.append(" []\n")
                return
            }
            out.append("\n")
            for item in items {
                out.append(String(repeating: " ", count: indent + 2))
                out.append("- ")
                writeSeqChild(item, indent: indent + 4, into: &out)
            }
        }
    }

    /// Writes a sequence item's contents. The "- " has already been
    /// written by the caller; first line of the item must continue on
    /// the same line, subsequent nested lines indent to `indent`.
    private static func writeSeqChild(_ v: EmitNode, indent: Int, into out: inout String) {
        switch v {
        case let .scalar(s, style):
            out.append(emitScalar(s, style: style))
            out.append("\n")
        case let .map(entries):
            if entries.isEmpty {
                out.append("{}\n")
                return
            }
            for (i, (k, val)) in entries.enumerated() {
                if i > 0 {
                    out.append(String(repeating: " ", count: indent))
                }
                out.append(k)
                out.append(":")
                writeChild(val, indent: indent, into: &out)
            }
        case let .seq(items):
            if items.isEmpty {
                out.append("[]\n")
                return
            }
            // Nested sequence inside a sequence: drop to a new line.
            out.append("\n")
            for item in items {
                out.append(String(repeating: " ", count: indent))
                out.append("- ")
                writeSeqChild(item, indent: indent + 2, into: &out)
            }
        }
    }

    // MARK: - Scalar emission

    private static let plainSafeRegex = try! NSRegularExpression(
        pattern: #"^[A-Za-z_][A-Za-z0-9_./-]*$"#
    )
    private static let intRegex    = try! NSRegularExpression(pattern: #"^-?\d+$"#)
    private static let floatRegex  = try! NSRegularExpression(pattern: #"^-?\d+\.\d+$"#)

    private static let yamlReserved: Set<String> = []

    private static func emitScalar(_ s: String, style: ScalarStyle) -> String {
        switch style {
        case .doubleQuoted: return doubleQuote(s)
        case .singleQuoted: return singleQuote(s)
        case .plain:
            if needsQuoting(s) { return doubleQuote(s) }
            return s
        }
    }

    private static func needsQuoting(_ s: String) -> Bool {
        if s.isEmpty { return true }
        if s.contains("\n") { return true }
        if s.hasPrefix(" ") || s.hasSuffix(" ") { return true }
        return false
    }

    private static func doubleQuote(_ s: String) -> String {
        var out = "\""
        for ch in s {
            switch ch {
            case "\\": out.append("\\\\")
            case "\"": out.append("\\\"")
            case "\n": out.append("\\n")
            case "\t": out.append("\\t")
            case "\r": out.append("\\r")
            default: out.append(ch)
            }
        }
        out.append("\"")
        return out
    }

    private static func singleQuote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "'", with: "''")
        return "'" + escaped + "'"
    }
}
