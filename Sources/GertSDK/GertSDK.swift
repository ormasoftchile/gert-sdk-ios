import Foundation

/// GertSDK — embedded gert runbook execution for iOS.
///
/// Usage:
/// ```swift
/// let kit = try await GertSDK.loadKit(from: kitURL)
/// let session = try await kit.startRun(runbook: "pool-weekly-check", actor: "alice")
/// for await event in session.events {
///     print(event)
/// }
/// ```
public struct GertSDK {
    
    /// Loads a kit bundle from a local URL, resolving all dependencies eagerly.
    /// Throws `KitLoadError.missingPlatformImpl` if any tool lacks an iOS impl.
    /// Throws `KitLoadError.missingCapability` if a required capability is unavailable.
    public static func loadKit(from url: URL) async throws -> LoadedKit {
        fatalError("Not yet implemented")
    }
    
    /// Loads a kit by name, downloading from the platform kit registry if needed.
    public static func loadKit(named name: String, version: String? = nil) async throws -> LoadedKit {
        fatalError("Not yet implemented")
    }
    
    /// Sync: push a completed local run to a gert server.
    public static func syncRun(_ run: CompletedRun, to serverURL: URL, authToken: String?) async throws {
        fatalError("Not yet implemented")
    }
}

public enum KitLoadError: Error, LocalizedError {
    case missingPlatformImpl(toolName: String, platform: String)
    case missingCapability(capability: String)
    case manifestMissing
    case manifestInvalid(String)
    case dependencyNotFound(name: String, version: String)
    case dependencyVersionConflict(name: String, required: String, found: String)
    
    public var errorDescription: String? {
        switch self {
        case .missingPlatformImpl(let toolName, let platform):
            return "Tool '\(toolName)' is missing implementation for platform '\(platform)'"
        case .missingCapability(let capability):
            return "Required capability '\(capability)' is unavailable on this device"
        case .manifestMissing:
            return "Kit manifest.json is missing"
        case .manifestInvalid(let reason):
            return "Kit manifest is invalid: \(reason)"
        case .dependencyNotFound(let name, let version):
            return "Dependency '\(name)' version '\(version)' not found"
        case .dependencyVersionConflict(let name, let required, let found):
            return "Dependency '\(name)' version conflict: required '\(required)', found '\(found)'"
        }
    }
}
