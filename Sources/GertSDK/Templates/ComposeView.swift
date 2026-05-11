//
//  ComposeView.swift
//  GertSDK / Templates
//
//  A generic SwiftUI form that drives `FormDescriptor` end-to-end.
//  Drop into any iOS/macOS app; pass a `Template` and the kit's
//  `SlotContext` (for zone/asset pickers). On save, you get a
//  `RoutineBinding` you can hand to `RoutineStore.put`.
//

#if canImport(SwiftUI)
import SwiftUI

/// State container that powers the compose view. Held as @StateObject
/// in the host so binding values survive view re-renders.
@available(iOS 16.0, macOS 13.0, *)
public final class ComposeViewModel: ObservableObject {
    public let template: Template
    public let context: SlotContext?
    public let descriptor: FormDescriptor

    @Published public var routineID: String = ""
    @Published public var stringValues: [String: String] = [:]
    @Published public var intValues: [String: Int]   = [:]
    @Published public var enumValues: [String: String] = [:]
    @Published public var toggleValues: [String: Bool] = [:]

    public init(template: Template, context: SlotContext? = nil) {
        self.template = template
        self.context = context
        self.descriptor = template.formDescriptor()

        for f in descriptor.fields {
            switch f.kind {
            case .int:
                if let d = f.defaultValue as? Int { intValues[f.id] = d }
                else if let d = f.defaultValue as? Int64 { intValues[f.id] = Int(d) }
            case .enumeration:
                if let d = f.defaultValue as? String { enumValues[f.id] = d }
            default:
                if let d = f.defaultValue as? String { stringValues[f.id] = d }
            }
        }
        for t in descriptor.toggles {
            toggleValues[t.id] = t.defaultValue
        }
    }

    /// Build a `RoutineBinding` reflecting the current form state.
    /// Empty-but-optional fields are dropped.
    public func makeBinding() -> RoutineBinding {
        var bindings: [String: Any] = [:]
        for f in descriptor.fields {
            switch f.kind {
            case .int:
                if let v = intValues[f.id] { bindings[f.id] = v }
            case .enumeration:
                if let v = enumValues[f.id], !v.isEmpty { bindings[f.id] = v }
            default:
                if let v = stringValues[f.id], !v.isEmpty { bindings[f.id] = v }
            }
        }
        return RoutineBinding(
            id: routineID,
            templateID: descriptor.templateID,
            templateVersion: descriptor.templateVersion,
            bindings: bindings,
            toggles: toggleValues
        )
    }
}

/// Minimal compose form. Hosts pass a save callback; cancel and chrome
/// are the host's job (sheets, nav bars, etc.).
@available(iOS 16.0, macOS 13.0, *)
public struct ComposeView: View {
    @ObservedObject public var model: ComposeViewModel
    public let availableZones: [String]
    public let availableAssets: [String]
    public let onSave: (RoutineBinding) -> Void

    public init(
        model: ComposeViewModel,
        availableZones: [String] = [],
        availableAssets: [String] = [],
        onSave: @escaping (RoutineBinding) -> Void
    ) {
        self.model = model
        self.availableZones = availableZones
        self.availableAssets = availableAssets
        self.onSave = onSave
    }

    public var body: some View {
        Form {
            Section(model.descriptor.title) {
                if let d = model.descriptor.description { Text(d).font(.footnote) }
                TextField("Routine id", text: $model.routineID)
                    .disableAutocorrection(true)
            }

            if !model.descriptor.fields.isEmpty {
                Section("Settings") {
                    ForEach(model.descriptor.fields, id: \.id) { field in
                        fieldView(field)
                    }
                }
            }

            if !model.descriptor.toggles.isEmpty {
                Section("Options") {
                    ForEach(model.descriptor.toggles, id: \.id) { t in
                        Toggle(t.label, isOn: Binding(
                            get: { model.toggleValues[t.id] ?? t.defaultValue },
                            set: { model.toggleValues[t.id] = $0 }
                        ))
                    }
                }
            }

            Section {
                Button("Save") { onSave(model.makeBinding()) }
                    .disabled(model.routineID.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func fieldView(_ f: FormDescriptor.Field) -> some View {
        switch f.kind {
        case .zoneRef:
            Picker(f.label, selection: pickerBinding(for: f.id)) {
                Text("Select…").tag("")
                ForEach(availableZones, id: \.self) { Text($0).tag($0) }
            }
        case .assetRef:
            Picker(f.label, selection: pickerBinding(for: f.id)) {
                Text("Select…").tag("")
                ForEach(availableAssets, id: \.self) { Text($0).tag($0) }
            }
        case .cadence, .duration, .stringShort:
            TextField(f.label, text: stringBinding(for: f.id))
                .disableAutocorrection(true)
        case let .int(min, max):
            Stepper(value: Binding(
                get: { model.intValues[f.id] ?? Int(min ?? 0) },
                set: { model.intValues[f.id] = $0 }
            ), in: Int(min ?? 0)...Int(max ?? 999_999)) {
                Text("\(f.label): \(model.intValues[f.id] ?? Int(min ?? 0))")
            }
        case let .enumeration(opts):
            Picker(f.label, selection: pickerBinding(for: f.id)) {
                Text("Select…").tag("")
                ForEach(opts, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private func stringBinding(for id: String) -> Binding<String> {
        Binding(
            get: { model.stringValues[id] ?? "" },
            set: { model.stringValues[id] = $0 }
        )
    }

    private func pickerBinding(for id: String) -> Binding<String> {
        Binding(
            get: { model.enumValues[id] ?? model.stringValues[id] ?? "" },
            set: {
                model.enumValues[id] = $0
                model.stringValues[id] = $0
            }
        )
    }
}
#endif
