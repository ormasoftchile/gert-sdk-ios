import Foundation

public enum KitLoadError: Error, LocalizedError {
    case directoryNotFound(URL)
    case manifestMissing(URL)
    case indexMissing(URL)
    case manifestInvalid(String)
    case indexInvalid(String)
    case unsupportedKind(String)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let url):  return "Kit directory not found: \(url.path)"
        case .manifestMissing(let url):    return "manifest.json not found at \(url.path)"
        case .indexMissing(let url):       return "index.json not found at \(url.path)"
        case .manifestInvalid(let detail): return "Invalid manifest.json: \(detail)"
        case .indexInvalid(let detail):    return "Invalid index.json: \(detail)"
        case .unsupportedKind(let k):      return "Unsupported kit kind: \(k) (expected 'home')"
        }
    }
}

// LoadedKit is the SDK's view of a fully-loaded home kit. It exposes
// the manifest, the index of routines/incidents, and lets the host
// start a RunSession for any routine by id.
public final class LoadedKit: @unchecked Sendable {
    public let directory: URL
    public let manifest: HomeKitManifest
    public let index: HomeKitIndex
    /// Delegations decoded from property.json. Empty when the kit
    /// has none or when property.json is absent/unreadable (the
    /// loader is permissive — delegations are an optional layer).
    public let delegations: [Delegation]

    init(directory: URL,
         manifest: HomeKitManifest,
         index: HomeKitIndex,
         delegations: [Delegation] = []) {
        self.directory = directory
        self.manifest = manifest
        self.index = index
        self.delegations = delegations
    }

    public var routines: [HomeKitIndex.Entry] { index.routines }
    public var incidents: [HomeKitIndex.Entry] { index.incidents ?? [] }

    /// Look up a routine by its kit-scoped id (e.g.
    /// "casa-santiago.routine.pool_clean").
    public func routine(id: String) -> HomeKitIndex.Entry? {
        routines.first { $0.id == id }
    }

    /// Loads and parses the runbook YAML for the given index entry.
    public func runbook(for entry: HomeKitIndex.Entry) throws -> Runbook {
        let url = directory.appendingPathComponent(entry.path)
        return try Runbook.load(from: url)
    }

    /// Returns the active delegate for the given routine at `date`, or
    /// nil when no delegation is active or the routine isn't covered.
    /// Mirrors gert-domain-home/pkg/delegation/policy.go so the iOS
    /// owner-side UI matches what the Go compiler/server consider the
    /// authoritative assignment.
    public func activeDelegate(forRoutineID routineID: String,
                               at date: Date = Date()) -> Delegation.Delegate? {
        let zone = routine(id: routineID)?.zone
        for d in delegations where d.isActive(on: date) {
            if d.covers(routineID: routineID, zone: zone) {
                return d.delegate
            }
        }
        return nil
    }
}

// KitLoader reads a kit directory laid out by `home-compile`:
//
//   <dir>/
//     manifest.json
//     index.json
//     property.json   (currently informational only)
//     routines/<id>.runbook.yaml
//     incidents/<id>.runbook.yaml
public enum KitLoader {
    public static func load(from url: URL) throws -> LoadedKit {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw KitLoadError.directoryNotFound(url)
        }

        let manifestURL = url.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw KitLoadError.manifestMissing(manifestURL)
        }
        let indexURL = url.appendingPathComponent("index.json")
        guard fm.fileExists(atPath: indexURL.path) else {
            throw KitLoadError.indexMissing(indexURL)
        }

        let manifest: HomeKitManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(HomeKitManifest.self, from: data)
        } catch {
            throw KitLoadError.manifestInvalid(error.localizedDescription)
        }
        guard manifest.kind == "home" else {
            throw KitLoadError.unsupportedKind(manifest.kind)
        }

        let index: HomeKitIndex
        do {
            let data = try Data(contentsOf: indexURL)
            index = try JSONDecoder().decode(HomeKitIndex.self, from: data)
        } catch {
            throw KitLoadError.indexInvalid(error.localizedDescription)
        }

        // property.json is optional and best-effort. It carries
        // delegations and other metadata the SDK doesn't strictly
        // need to start a run; if it's missing or malformed we
        // simply load with no delegations rather than failing the
        // whole kit.
        let delegations = loadDelegations(at: url.appendingPathComponent("property.json"))

        return LoadedKit(directory: url,
                         manifest: manifest,
                         index: index,
                         delegations: delegations)
    }

    private static func loadDelegations(at url: URL) -> [Delegation] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let doc = try? JSONDecoder().decode(PropertyDocument.self, from: data) else {
            return []
        }
        return doc.delegations ?? []
    }
}
