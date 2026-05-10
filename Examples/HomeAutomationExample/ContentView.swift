import SwiftUI
import GertSDK

/// Main view for the Home Automation example app.
///
/// The UI is generic over routines: it lists every routine the loaded
/// kit ships and runs whichever one the user taps. To add a new chore,
/// add a routine to the home DSL and recompile the kit — no Swift
/// change is required.
struct ContentView: View {
    @StateObject private var viewModel = HomeAutomationViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    kitStatusSection

                    if case .loaded = viewModel.kitStatus {
                        routinesSection
                    }

                    if viewModel.runningRoutineID != nil || viewModel.lastRunStatus != .none {
                        runStatusSection
                    }

                    if !viewModel.events.isEmpty {
                        eventsSection
                    }

                    if let error = viewModel.errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Home Automation")
        }
    }

    // MARK: - Sections

    private var kitStatusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: kitStatusIcon)
                    .foregroundColor(kitStatusColor)
                Text(viewModel.kitStatus.description)
                    .font(.headline)
                Spacer()
            }

            if case .notLoaded = viewModel.kitStatus {
                Button {
                    Task { await viewModel.loadKit() }
                } label: {
                    Label("Load Kit", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }

            if case .loaded = viewModel.kitStatus, let kit = viewModel.loadedKit {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Property: \(kit.index.propertyName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Routines: \(kit.routines.count) · Incidents: \(kit.incidents.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Routines")
                .font(.headline)

            if viewModel.routines.isEmpty {
                Text("This kit has no routines.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.routines) { routine in
                    RoutineRow(
                        routine: routine,
                        isRunning: viewModel.runningRoutineID == routine.id,
                        anyRunning: viewModel.runningRoutineID != nil
                    ) {
                        Task { await viewModel.runRoutine(id: routine.id) }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var runStatusSection: some View {
        HStack {
            Image(systemName: runStatusIcon)
                .foregroundColor(runStatusColor)
            VStack(alignment: .leading) {
                if let id = viewModel.runningRoutineID {
                    Text("Running \(id)")
                        .font(.subheadline)
                } else {
                    Text(viewModel.lastRunStatus.description)
                        .font(.headline)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Events (\(viewModel.events.count))")
                .font(.headline)

            ForEach(Array(viewModel.events.enumerated()), id: \.offset) { index, event in
                EventRow(event: event, index: index)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func errorSection(_ message: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Status helpers

    private var kitStatusIcon: String {
        switch viewModel.kitStatus {
        case .notLoaded: return "circle"
        case .loading:   return "arrow.down.circle"
        case .loaded:    return "checkmark.circle.fill"
        case .error:     return "xmark.circle.fill"
        }
    }

    private var kitStatusColor: Color {
        switch viewModel.kitStatus {
        case .notLoaded: return .gray
        case .loading:   return .blue
        case .loaded:    return .green
        case .error:     return .red
        }
    }

    private var runStatusIcon: String {
        if viewModel.runningRoutineID != nil { return "arrow.clockwise.circle" }
        switch viewModel.lastRunStatus {
        case .none:      return "circle"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }

    private var runStatusColor: Color {
        if viewModel.runningRoutineID != nil { return .blue }
        switch viewModel.lastRunStatus {
        case .none:      return .gray
        case .completed: return .green
        case .failed:    return .red
        }
    }
}

// MARK: - Routine row

private struct RoutineRow: View {
    let routine: HomeKitIndex.Entry
    let isRunning: Bool
    let anyRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "play.circle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let zone = routine.zone {
                        Text("Zone: \(zone)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let asset = routine.asset {
                        Text("Asset: \(asset)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isRunning {
                    ProgressView().progressViewStyle(.circular)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(anyRunning && !isRunning ? Color.gray : Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(anyRunning)
    }
}

// MARK: - Event row

private struct EventRow: View {
    let event: RuntimeEvent
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.kind)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let stepID = event.stepID {
                    Text("step: \(stepID)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let tool = event.toolName {
                    Text("tool: \(tool)\(event.action.map { ".\($0)" } ?? "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text("#\(index + 1)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch event.kind {
        case RuntimeEvent.runStarted:        return "play.circle.fill"
        case RuntimeEvent.stepStarted:       return "arrow.right.circle"
        case RuntimeEvent.stepCompleted:     return "checkmark.circle"
        case RuntimeEvent.stepFailed:        return "xmark.circle"
        case RuntimeEvent.stepAwaitingInput: return "questionmark.circle"
        case RuntimeEvent.toolInvoked:       return "wrench.and.screwdriver"
        case RuntimeEvent.toolCompleted:     return "checkmark.seal"
        case RuntimeEvent.toolFailed:        return "exclamationmark.triangle"
        case RuntimeEvent.runCompleted:      return "checkmark.circle.fill"
        case RuntimeEvent.runFailed:         return "xmark.circle.fill"
        case RuntimeEvent.runCancelled:      return "stop.circle.fill"
        default:                             return "circle"
        }
    }

    private var color: Color {
        switch event.kind {
        case RuntimeEvent.runStarted, RuntimeEvent.stepStarted, RuntimeEvent.toolInvoked:
            return .blue
        case RuntimeEvent.stepCompleted, RuntimeEvent.toolCompleted, RuntimeEvent.runCompleted:
            return .green
        case RuntimeEvent.stepFailed, RuntimeEvent.toolFailed, RuntimeEvent.runFailed:
            return .red
        case RuntimeEvent.stepAwaitingInput:
            return .orange
        case RuntimeEvent.runCancelled:
            return .gray
        default:
            return .secondary
        }
    }
}
