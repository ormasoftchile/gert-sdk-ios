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
import Foundation
import GertSDK
import Combine

/// ViewModel managing home automation kit lifecycle and execution.
@MainActor
class HomeAutomationViewModel: ObservableObject {
    // MARK: - Published State
    
    @Published var kitStatus: KitStatus = .notLoaded
    @Published var loadedKit: LoadedKit?
    @Published var runStatus: RunStatus = .idle
    @Published var events: [RunEvent] = []
    @Published var errorMessage: String?
    
    // MARK: - Kit Management
    
    /// Load the gert-domain-home kit from the local bundle directory.
    /// In production, this would point to a kit bundle downloaded via `gert kit fetch`
    /// or bundled with the app.
    func loadKit() async {
        kitStatus = .loading
        errorMessage = nil
        
        do {
            // Path to the kit bundle - in production this would be:
            // - Downloaded to Application Support via SDK fetch API
            // - Bundled with the app in Resources/
            // - Located via FileManager in .gert-kits/
            let kitBundleURL = Bundle.main.url(
                forResource: "gert-domain-home",
                withExtension: "kit"
            ) ?? Self.localKitBundleURL()
            
            let kit = try await GertSDK.loadKit(from: kitBundleURL)
            
            loadedKit = kit
            kitStatus = .loaded(name: kit.manifest.name, version: kit.manifest.version)
        } catch let error as KitLoadError {
            kitStatus = .error
            errorMessage = error.localizedDescription
        } catch {
            kitStatus = .error
            errorMessage = "Unexpected error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Runbook Execution
    
    /// Execute the "turn-on-lights" runbook from the home automation kit.
    /// This demonstrates a typical home automation workflow:
    /// - Check room presence
    /// - Get current light state
    /// - Turn on lights if needed
    func turnOnLights() async {
        guard let kit = loadedKit else {
            errorMessage = "Kit not loaded. Please load the kit first."
            return
        }
        
        runStatus = .running
        events = []
        errorMessage = nil
        
        do {
            let session = try await kit.startRun(
                runbook: "turn-on-lights",
                actor: "ios-user-\(UUID().uuidString.prefix(8))"
            )
            
            // Stream events to UI
            for await event in session.events {
                events.append(event)
                
                // Update run status based on terminal events
                switch event {
                case .runCompleted:
                    runStatus = .completed
                case .runFailed(let failure):
                    runStatus = .failed
                    errorMessage = failure.error
                default:
                    break
                }
            }
            
            // If no terminal event received yet, wait for completion
            if case .running = runStatus {
                _ = try await session.wait()
                runStatus = .completed
            }
        } catch let error as KitError {
            runStatus = .failed
            errorMessage = error.localizedDescription
        } catch {
            runStatus = .failed
            errorMessage = "Run failed: \(error.localizedDescription)"
        }
    }
    
    /// Check room presence using the "check-presence" runbook.
    /// Demonstrates a read-only workflow that queries sensor state.
    func checkPresence() async {
        guard let kit = loadedKit else {
            errorMessage = "Kit not loaded. Please load the kit first."
            return
        }
        
        runStatus = .running
        events = []
        errorMessage = nil
        
        do {
            let session = try await kit.startRun(
                runbook: "check-presence",
                actor: "ios-user-\(UUID().uuidString.prefix(8))",
                inputs: ["room": "living-room"]
            )
            
            for await event in session.events {
                events.append(event)
                
                switch event {
                case .runCompleted:
                    runStatus = .completed
                case .runFailed(let failure):
                    runStatus = .failed
                    errorMessage = failure.error
                default:
                    break
                }
            }
            
            if case .running = runStatus {
                _ = try await session.wait()
                runStatus = .completed
            }
        } catch let error as KitError {
            runStatus = .failed
            errorMessage = error.localizedDescription
        } catch {
            runStatus = .failed
            errorMessage = "Run failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Helpers
    
    /// Returns the local kit bundle URL for development.
    /// In production, use the kit registry or app bundle.
    private static func localKitBundleURL() -> URL {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        return currentDirectory
            .appendingPathComponent(".gert-kits")
            .appendingPathComponent("gert-domain-home.kit")
    }
}

// MARK: - State Types

enum KitStatus {
    case notLoaded
    case loading
    case loaded(name: String, version: String)
    case error
    
    var description: String {
        switch self {
        case .notLoaded:
            return "Not loaded"
        case .loading:
            return "Loading..."
        case .loaded(let name, let version):
            return "Loaded \(name) v\(version)"
        case .error:
            return "Load failed"
        }
    }
}

enum RunStatus {
    case idle
    case running
    case completed
    case failed
    
    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .running:
            return "Running..."
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
}
