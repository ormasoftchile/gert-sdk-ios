import Foundation
import GertSDK

/// ViewModel managing home kit lifecycle and runbook execution.
///
/// Generic over routines: the UI lists whatever routines the loaded
/// kit ships, and `runRoutine(id:)` drives them through the SDK.
/// No chore-specific knowledge lives here.
@MainActor
final class HomeAutomationViewModel: ObservableObject {

    // MARK: - Published State

    @Published var kitStatus: KitStatus = .notLoaded
    @Published var loadedKit: LoadedKit?
    @Published var runningRoutineID: String?
    @Published var lastRunStatus: LastRunStatus = .none
    @Published var events: [RuntimeEvent] = []
    @Published var errorMessage: String?

    private var runtime: GertRuntime?

    // MARK: - Kit Lifecycle

    func loadKit() async {
        kitStatus = .loading
        errorMessage = nil

        do {
            let kitURL = Self.localKitBundleURL()
            let kit = try KitLoader.load(from: kitURL)
            self.loadedKit = kit
            self.runtime = GertRuntime(kit: kit)
            self.kitStatus = .loaded(name: kit.manifest.name, version: kit.manifest.version)
        } catch let error as KitLoadError {
            kitStatus = .error
            errorMessage = error.localizedDescription
        } catch {
            kitStatus = .error
            errorMessage = "Unexpected error: \(error.localizedDescription)"
        }
    }

    // MARK: - Routine Execution

    /// Lists all routines from the loaded kit. Empty when no kit is loaded.
    var routines: [HomeKitIndex.Entry] { loadedKit?.routines ?? [] }

    /// Runs a routine by its kit-scoped id. Drains the event stream
    /// into `events` and updates `lastRunStatus` on terminal events.
    func runRoutine(id: String) async {
        guard let runtime else {
            errorMessage = "Kit not loaded. Load the kit first."
            return
        }
        runningRoutineID = id
        lastRunStatus = .none
        events = []
        errorMessage = nil

        do {
            let session = try runtime.startRun(
                routineID: id,
                actor: "ios-user-\(UUID().uuidString.prefix(8))"
            )

            for await event in session.events {
                events.append(event)
                switch event.kind {
                case RuntimeEvent.runCompleted:
                    lastRunStatus = .completed
                case RuntimeEvent.runFailed, RuntimeEvent.runCancelled:
                    lastRunStatus = .failed
                default:
                    break
                }
            }

            // Fall back to the session summary if no terminal event
            // was observed on the stream.
            if lastRunStatus == .none {
                _ = try await session.wait()
                lastRunStatus = .completed
            }
        } catch let error as GertRuntimeError {
            lastRunStatus = .failed
            errorMessage = error.localizedDescription
        } catch {
            lastRunStatus = .failed
            errorMessage = "Run failed: \(error.localizedDescription)"
        }

        runningRoutineID = nil
    }

    // MARK: - Helpers

    /// Local kit bundle path used for development. In production use
    /// `Bundle.main.url(forResource:withExtension:)` or fetch via the
    /// kit registry.
    private static func localKitBundleURL() -> URL {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        return cwd
            .appendingPathComponent(".gert-kits")
            .appendingPathComponent("casa-santiago.home.kit")
    }
}

// MARK: - State Types

enum KitStatus: Equatable {
    case notLoaded
    case loading
    case loaded(name: String, version: String)
    case error

    var description: String {
        switch self {
        case .notLoaded:                     return "Not loaded"
        case .loading:                       return "Loading…"
        case .loaded(let name, let version): return "Loaded \(name) v\(version)"
        case .error:                         return "Load failed"
        }
    }
}

enum LastRunStatus: Equatable {
    case none
    case completed
    case failed

    var description: String {
        switch self {
        case .none:      return "Idle"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        }
    }
}
