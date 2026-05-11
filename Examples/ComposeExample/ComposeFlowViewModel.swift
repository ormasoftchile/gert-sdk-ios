import Foundation
import GertSDK

/// View model for the template compose flow. Loads a `TemplateKit`
/// from a directory of `*.template.yaml` files, persists composed
/// routines through a `RoutineStore`, and exposes the saved bindings
/// for the UI to list.
///
/// This is intentionally separate from `HomeAutomationViewModel` —
/// composition (authoring) and runtime (execution) are two distinct
/// use cases of the SDK.
@MainActor
final class ComposeFlowViewModel: ObservableObject {

    @Published var templates: [Template] = []
    @Published var savedRoutines: [String] = []
    @Published var loadError: String?
    @Published var saveError: String?

    private var kit: TemplateKit?
    private var store: RoutineStore?

    /// The set of zone ids the user can pick. In a real app this comes
    /// from the loaded property file. The example seeds a small fixture
    /// so the form is usable in isolation.
    let availableZones: [String] = ["pool", "front_lawn", "garage", "driveway", "backyard"]
    let availableAssets: [String] = ["pool_pump", "riding_mower", "front_gate"]

    private struct ExampleCtx: SlotContext {
        let zones: Set<String>
        let assets: Set<String>
        func hasZone(_ id: String) -> Bool { zones.contains(id) }
        func hasAsset(_ id: String) -> Bool { assets.contains(id) }
    }

    func load(templatesDir: URL, storeDir: URL) {
        let ctx = ExampleCtx(zones: Set(availableZones),
                              assets: Set(availableAssets))
        let (loaded, errors) = TemplateKit.load(directory: templatesDir, context: ctx)
        if !errors.isEmpty {
            loadError = errors.map { "\($0.0.lastPathComponent): \($0.1)" }
                              .joined(separator: "\n")
        } else {
            loadError = nil
        }
        kit = loaded
        templates = loaded.templates

        do {
            store = try FileRoutineStore(directory: storeDir)
            try refreshSavedList()
        } catch {
            loadError = "Store init: \(error)"
        }
    }

    func template(id: String) -> Template? { kit?.template(id: id) }

    func save(_ binding: RoutineBinding) {
        guard let store else { return }
        let yaml = RoutineBindingEncoder.encode(binding)
        do {
            try store.put(.init(id: binding.id, bytes: yaml))
            try refreshSavedList()
            saveError = nil
        } catch {
            saveError = "\(error)"
        }
    }

    func delete(id: String) {
        guard let store else { return }
        do {
            try store.delete(id: id)
            try refreshSavedList()
        } catch {
            saveError = "\(error)"
        }
    }

    func loadSaved(id: String) -> String? {
        try? store?.get(id: id)?.bytes
    }

    private func refreshSavedList() throws {
        savedRoutines = (try store?.list()) ?? []
    }
}
