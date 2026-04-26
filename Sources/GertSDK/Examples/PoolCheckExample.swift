// Example: Load gert-mobile-platform kit and run pool-weekly-check runbook
// This shows the full e2e path from kit load to run session start.
import Foundation

public struct PoolCheckExample {
    /// Demonstrates loading the gert-mobile-platform kit and starting a pool check runbook.
    /// In production, kitURL comes from the app bundle or downloaded from the kit registry.
    public static func run(kitURL: URL) async throws {
        let kit = try await GertSDK.loadKit(from: kitURL)
        
        guard let runbook = kit.runbooks.first(where: { $0.name == "pool-weekly-check" }) else {
            throw ExampleError.runbookNotFound("pool-weekly-check")
        }
        
        print("Loaded kit: \(kit.manifest.name) v\(kit.manifest.version)")
        print("Running: \(runbook.name) — \(runbook.steps.count) steps")
        print("Tools in kit: \(kit.tools.map { $0.name }.joined(separator: ", "))")
        print("First step: \(runbook.steps[0].name) — uses tool: \(runbook.steps[0].tool)")
    }
    
    public enum ExampleError: Error {
        case runbookNotFound(String)
    }
}
