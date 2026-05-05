import Foundation

// HomeKitManifest matches manifest.json in a kit produced by
// `home-compile`. It is intentionally permissive (extra keys are
// ignored) so the kit format can grow without forcing every SDK
// client to upgrade in lockstep.
public struct HomeKitManifest: Codable, Sendable {
    public let name: String
    public let version: String
    public let kind: String
    public let description: String?
    public let propertyID: String
    public let target: [String]?
    public let requires: [String]?
    public let routinesCount: Int
    public let incidentsCount: Int
    public let compiledAt: String?
    public let domainKitVersion: String?

    enum CodingKeys: String, CodingKey {
        case name, version, kind, description, target, requires
        case propertyID       = "property_id"
        case routinesCount    = "routines_count"
        case incidentsCount   = "incidents_count"
        case compiledAt       = "compiled_at"
        case domainKitVersion = "domain_kit_version"
    }
}

// HomeKitIndex matches index.json. It lets the SDK and host UI list
// routines and incidents without re-reading every YAML file.
public struct HomeKitIndex: Codable, Sendable {
    public let propertyID: String
    public let propertyName: String
    public let routines: [Entry]
    public let incidents: [Entry]?

    public struct Entry: Codable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let path: String
        public let zone: String?
        public let asset: String?
        public let cadence: String?
        public let evidenceType: String?
        public let toolDeps: [String]?
        public let notifications: [String: Int]?
        public let metadata: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id, name, path, zone, asset, cadence, metadata, notifications
            case evidenceType = "evidence_type"
            case toolDeps     = "tool_deps"
        }
    }

    enum CodingKeys: String, CodingKey {
        case propertyID   = "property_id"
        case propertyName = "property_name"
        case routines, incidents
    }
}
