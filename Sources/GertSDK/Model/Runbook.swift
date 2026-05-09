import Foundation
import Yams

// Runbook is the in-memory representation of a runbook/v1 YAML file
// produced by the gert engine or the gert-domain-home compiler. The
// structure mirrors the YAML 1:1 — top-level metadata, plus a `flow`
// of nested step nodes.
//
// Only the step kinds emitted by the home compiler today are modelled:
// tool, collector, noop. Adding branch/parallel/include/iterate later
// is a matter of extending FlowItem.Kind without breaking callers.
public struct Runbook: Codable, Sendable {
    public let apiVersion: String
    public let id: String
    public let name: String
    public let kind: String?
    public let description: String?
    public let metadata: [String: JSONValue]?
    public let flow: [FlowItem]
}

// FlowItem wraps a single `- step:` entry in `flow:`. The runbook/v1
// format always nests the step under a `step:` key so future flow
// kinds (group, parallel, …) can sit alongside without ambiguity.
public struct FlowItem: Codable, Sendable {
    public let step: Step
}

public struct Step: Codable, Sendable {
    public let id: String
    public let type: String
    public let title: String?
    public let subtitle: String?
    public let prompt: String?

    /// Tool steps reference an installed tool by name + action.
    public let tool: ToolRef?

    /// Collector steps render an input form with these fields.
    public let fields: [CollectorField]?

    /// `capture` maps output names to step return values
    /// (template strings or static values). Stored as raw JSONValue so
    /// the executor can resolve templates lazily.
    public let capture: [String: JSONValue]?

    /// `delay` is used by noop steps that pause the run.
    public let delay: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, subtitle, prompt, tool, fields, capture, delay
    }
}

public struct ToolRef: Codable, Sendable {
    public let name: String
    public let action: String
    public let args: [String: JSONValue]?
}

public struct CollectorField: Codable, Sendable {
    public let name: String
    public let type: String        // text | image | select | checklist | …
    public let label: String?
    public let required: Bool?
    public let multiline: Bool?
    public let options: [FieldOption]?
}

public struct FieldOption: Codable, Sendable {
    public let value: String
    public let label: String?
}

// MARK: - YAML loader

public enum RunbookLoadError: Error, LocalizedError {
    case fileNotFound(URL)
    case invalidYAML(String)
    case unsupportedAPIVersion(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):       return "Runbook file not found: \(url.path)"
        case .invalidYAML(let detail):     return "Invalid runbook YAML: \(detail)"
        case .unsupportedAPIVersion(let v): return "Unsupported runbook apiVersion: \(v) (expected 'runbook/v1')"
        }
    }
}

public extension Runbook {
    /// Loads and decodes a runbook/v1 YAML file from disk.
    static func load(from url: URL) throws -> Runbook {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RunbookLoadError.fileNotFound(url)
        }
        let yaml = try String(contentsOf: url, encoding: .utf8)
        let rb: Runbook
        do {
            rb = try YAMLDecoder().decode(Runbook.self, from: yaml)
        } catch {
            throw RunbookLoadError.invalidYAML(error.localizedDescription)
        }
        guard rb.apiVersion == "runbook/v1" else {
            throw RunbookLoadError.unsupportedAPIVersion(rb.apiVersion)
        }
        return rb
    }
}
