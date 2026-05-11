//
//  TemplateKit.swift
//  GertSDK / Templates
//
//  The compose surface used by an iOS app to drive a "pick a
//  template → fill a form → save a routine" flow without knowing
//  about gert internals.
//
//  Responsibilities:
//    1. Discover and parse `*.template.yaml` files in a directory.
//    2. Expose a form descriptor per template so a generic UI can
//       render the right input controls (text / int with min-max /
//       enum / toggle).
//    3. Materialize a user-provided binding/toggle map into a
//       routine YAML payload via the deterministic emitter.
//

import Foundation

public struct TemplateKit {
    public let templates: [Template]
    public let context: SlotContext?

    public init(templates: [Template], context: SlotContext? = nil) {
        self.templates = templates
        self.context = context
    }

    /// Loads every `*.template.yaml` file in `directory` (non-recursive).
    /// Files that fail to parse are skipped — their errors are returned
    /// in `errors` so the caller can report them. The returned templates
    /// are sorted by id for stable UI ordering.
    public static func load(
        directory: URL, context: SlotContext? = nil
    ) -> (kit: TemplateKit, errors: [(URL, Error)]) {
        var loaded: [Template] = []
        var errors: [(URL, Error)] = []

        let fm = FileManager.default
        let contents: [String]
        do {
            contents = try fm.contentsOfDirectory(atPath: directory.path)
        } catch {
            return (TemplateKit(templates: [], context: context), [(directory, error)])
        }
        let files = contents.filter { $0.hasSuffix(".template.yaml") }.sorted()
        for name in files {
            let url = directory.appendingPathComponent(name)
            do {
                let tpl = try TemplateParser.parseFile(url.path)
                loaded.append(tpl)
            } catch {
                errors.append((url, error))
            }
        }
        loaded.sort { $0.id < $1.id }
        return (TemplateKit(templates: loaded, context: context), errors)
    }

    public func template(id: String) -> Template? {
        templates.first { $0.id == id }
    }

    /// Compose a routine from a template + user-supplied bindings/toggles.
    /// Returns the deterministic YAML payload; the caller is responsible
    /// for persisting it (see Store).
    public func compose(
        templateID: String,
        routineID: String,
        bindings: [String: Any] = [:],
        toggles: [String: Bool] = [:]
    ) throws -> MaterializeResult {
        guard let tpl = template(id: templateID) else {
            throw ComposeError.unknownTemplate(templateID)
        }
        return try Materializer.materialize(.init(
            template: tpl,
            routineID: routineID,
            bindings: bindings,
            toggles: toggles,
            context: context
        ))
    }
}

public enum ComposeError: Error, CustomStringConvertible {
    case unknownTemplate(String)
    public var description: String {
        switch self {
        case let .unknownTemplate(id): return "unknown template \"\(id)\""
        }
    }
}

// MARK: - Form descriptor

/// A UI-agnostic description of the form a user must fill to compose a
/// routine from a template. The iOS app renders one screen by walking
/// `fields` in order; each field carries enough metadata to pick the
/// right SwiftUI control.
public struct FormDescriptor {
    public let templateID: String
    public let templateVersion: Int
    public let title: String
    public let description: String?
    public let fields: [Field]
    public let toggles: [ToggleField]

    public struct Field {
        public let id: String
        public let label: String
        public let kind: Kind
        public let required: Bool
        public let defaultValue: Any?

        public enum Kind {
            case zoneRef                          // pick from context.zones
            case assetRef                         // pick from context.assets
            case cadence                          // free text matching N(m|h|d|w)
            case duration                         // same syntax as cadence
            case stringShort                      // 1..80 chars, single line
            case int(min: Int64?, max: Int64?)
            case enumeration(options: [String])
        }
    }

    public struct ToggleField {
        public let id: String
        public let label: String
        public let defaultValue: Bool
    }
}

public extension Template {
    /// Build a `FormDescriptor` for this template.
    func formDescriptor() -> FormDescriptor {
        let fields = slots.map { s -> FormDescriptor.Field in
            FormDescriptor.Field(
                id: s.id,
                label: s.label ?? humanize(s.id),
                kind: kindFor(slot: s),
                required: s.required,
                defaultValue: s.defaultValue
            )
        }
        let toggleFields = toggles.map {
            FormDescriptor.ToggleField(
                id: $0.id,
                label: $0.label ?? humanize($0.id),
                defaultValue: $0.defaultValue
            )
        }
        return FormDescriptor(
            templateID: id,
            templateVersion: version,
            title: title ?? humanize(id),
            description: description,
            fields: fields,
            toggles: toggleFields
        )
    }
}

private func kindFor(slot s: Template.Slot) -> FormDescriptor.Field.Kind {
    switch s.type {
    case "zone_ref":     return .zoneRef
    case "asset_ref":    return .assetRef
    case "cadence":      return .cadence
    case "duration":     return .duration
    case "string_short": return .stringShort
    case "int":
        let mn = (s.params["min"] as? Int).map(Int64.init)
            ?? (s.params["min"] as? Int64)
        let mx = (s.params["max"] as? Int).map(Int64.init)
            ?? (s.params["max"] as? Int64)
        return .int(min: mn, max: mx)
    case "enum":
        let opts = (s.params["options"] as? [String])
            ?? (s.params["options"] as? [Any])?.compactMap { $0 as? String }
            ?? []
        return .enumeration(options: opts)
    default:
        return .stringShort
    }
}

private func humanize(_ id: String) -> String {
    id.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
}
