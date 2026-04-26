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
