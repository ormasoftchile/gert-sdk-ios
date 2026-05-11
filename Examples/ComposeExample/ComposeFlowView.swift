import SwiftUI
import GertSDK

/// Browser + composer screen. Lists every template the kit knows about,
/// opens `ComposeView` in a sheet on tap, and persists the resulting
/// `RoutineBinding` through `FileRoutineStore`. Saved routines appear
/// in the lower section and can be inspected or deleted.
@available(iOS 16.0, macOS 13.0, *)
struct ComposeFlowView: View {
    @StateObject private var model = ComposeFlowViewModel()
    @State private var pickedTemplate: Template?
    @State private var inspectedRoutine: String?

    /// Where the example loads templates from.
    ///
    /// Resolution order:
    ///   1. SPM bundle (`Bundle.module`) — used when the example is
    ///      built as the `HomeAutomationExample` SPM executable. Set
    ///      via the `resources: [.copy("Resources/templates")]` clause
    ///      in `Package.swift`.
    ///   2. `Bundle.main` resource subdirectory `templates/routine/` —
    ///      used when the example is built from an Xcode project that
    ///      adds the `Resources/templates` folder as a folder reference.
    ///   3. Workspace sibling `gert-domain-home/templates/routine/` —
    ///      a developer-machine fallback for ad-hoc dev.
    private var templatesDir: URL {
        #if SWIFT_PACKAGE
        if let bundled = Bundle.module.url(
            forResource: "routine", withExtension: nil, subdirectory: "templates"
        ) {
            return bundled
        }
        #endif
        if let bundled = Bundle.main.url(
            forResource: "routine", withExtension: nil, subdirectory: "templates"
        ) {
            return bundled
        }
        let here = URL(fileURLWithPath: #filePath)
        let workspace = here
            .deletingLastPathComponent() // HomeAutomationExample
            .deletingLastPathComponent() // Examples
            .deletingLastPathComponent() // gert-sdk-ios
            .deletingLastPathComponent() // workspace
        return workspace.appendingPathComponent("gert-domain-home/templates/routine")
    }

    private var storeDir: URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        return docs.appendingPathComponent("composed-routines")
    }

    var body: some View {
        NavigationView {
            List {
                if let err = model.loadError {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }
                if let err = model.saveError {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }

                Section("Templates") {
                    if model.templates.isEmpty {
                        Text("No templates loaded.").foregroundColor(.secondary)
                    } else {
                        ForEach(model.templates, id: \.id) { tpl in
                            Button {
                                pickedTemplate = tpl
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(tpl.title ?? tpl.id).font(.headline)
                                    if let d = tpl.description {
                                        Text(d).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Saved routines") {
                    if model.savedRoutines.isEmpty {
                        Text("None yet — pick a template above.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(model.savedRoutines, id: \.self) { id in
                            HStack {
                                Text(id)
                                Spacer()
                                Button("View") { inspectedRoutine = id }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .onDelete { idx in
                            for i in idx { model.delete(id: model.savedRoutines[i]) }
                        }
                    }
                }
            }
            .navigationTitle("Compose")
            .onAppear {
                model.load(templatesDir: templatesDir, storeDir: storeDir)
            }
            .sheet(item: $pickedTemplate) { tpl in
                ComposeSheet(
                    template: tpl,
                    availableZones: model.availableZones,
                    availableAssets: model.availableAssets,
                    onSave: { binding in
                        model.save(binding)
                        pickedTemplate = nil
                    },
                    onCancel: { pickedTemplate = nil }
                )
            }
            .sheet(item: Binding(
                get: { inspectedRoutine.map { Inspect(id: $0) } },
                set: { inspectedRoutine = $0?.id }
            )) { item in
                NavigationView {
                    ScrollView {
                        Text(model.loadSaved(id: item.id) ?? "(missing)")
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(item.id)
                }
            }
        }
    }

    private struct Inspect: Identifiable { let id: String }
}

extension Template: Identifiable {}

@available(iOS 16.0, macOS 13.0, *)
private struct ComposeSheet: View {
    let template: Template
    let availableZones: [String]
    let availableAssets: [String]
    let onSave: (RoutineBinding) -> Void
    let onCancel: () -> Void

    @StateObject private var vm: ComposeViewModel

    init(template: Template, availableZones: [String], availableAssets: [String],
         onSave: @escaping (RoutineBinding) -> Void, onCancel: @escaping () -> Void) {
        self.template = template
        self.availableZones = availableZones
        self.availableAssets = availableAssets
        self.onSave = onSave
        self.onCancel = onCancel
        _vm = StateObject(wrappedValue: ComposeViewModel(template: template))
    }

    var body: some View {
        NavigationView {
            ComposeView(
                model: vm,
                availableZones: availableZones,
                availableAssets: availableAssets,
                onSave: onSave
            )
            .navigationTitle(template.title ?? template.id)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
