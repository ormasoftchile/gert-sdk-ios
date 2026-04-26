import SwiftUI
import GertSDK

/// Main view for the Home Automation example app.
/// Demonstrates SwiftUI integration with GertSDK using async/await.
struct ContentView: View {
    @StateObject private var viewModel = HomeAutomationViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Kit Status Section
                    kitStatusSection
                    
                    // Action Buttons Section
                    if case .loaded = viewModel.kitStatus {
                        actionsSection
                    }
                    
                    // Run Status Section
                    if viewModel.runStatus != .idle {
                        runStatusSection
                    }
                    
                    // Events Stream Section
                    if !viewModel.events.isEmpty {
                        eventsSection
                    }
                    
                    // Error Section
                    if let error = viewModel.errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Home Automation")
        }
    }
    
    // MARK: - View Components
    
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
                Button(action: {
                    Task {
                        await viewModel.loadKit()
                    }
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Load gert-domain-home Kit")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            
            if case .loaded(let name, let version) = viewModel.kitStatus,
               let kit = viewModel.loadedKit {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kit: \(name) v\(version)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Runbooks: \(kit.runbooks.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Tools: \(kit.tools.count)")
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
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Text("Workflows")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: {
                Task {
                    await viewModel.turnOnLights()
                }
            }) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                    Text("Turn On Lights")
                    Spacer()
                    if viewModel.runStatus == .running {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.runStatus == .running)
            
            Button(action: {
                Task {
                    await viewModel.checkPresence()
                }
            }) {
                HStack {
                    Image(systemName: "sensor.fill")
                    Text("Check Presence")
                    Spacer()
                    if viewModel.runStatus == .running {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.runStatus == .running)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var runStatusSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: runStatusIcon)
                    .foregroundColor(runStatusColor)
                Text(viewModel.runStatus.description)
                    .font(.headline)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run Events (\(viewModel.events.count))")
                .font(.headline)
            
            ForEach(Array(viewModel.events.enumerated()), id: \.offset) { index, event in
                EventRowView(event: event, index: index)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func errorSection(_ message: String) -> some View {
        HStack {
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
    
    // MARK: - Helpers
    
    private var kitStatusIcon: String {
        switch viewModel.kitStatus {
        case .notLoaded:
            return "circle"
        case .loading:
            return "arrow.down.circle"
        case .loaded:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }
    
    private var kitStatusColor: Color {
        switch viewModel.kitStatus {
        case .notLoaded:
            return .gray
        case .loading:
            return .blue
        case .loaded:
            return .green
        case .error:
            return .red
        }
    }
    
    private var runStatusIcon: String {
        switch viewModel.runStatus {
        case .idle:
            return "circle"
        case .running:
            return "arrow.clockwise.circle"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    private var runStatusColor: Color {
        switch viewModel.runStatus {
        case .idle:
            return .gray
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

/// Displays a single run event with appropriate icon and details.
struct EventRowView: View {
    let event: RunEvent
    let index: Int
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let detail = detail {
                    Text(detail)
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
        switch event {
        case .runStarted:
            return "play.circle.fill"
        case .stepStarted:
            return "arrow.right.circle"
        case .stepCompleted:
            return "checkmark.circle"
        case .stepFailed:
            return "xmark.circle"
        case .runCompleted:
            return "checkmark.circle.fill"
        case .runFailed:
            return "xmark.circle.fill"
        }
    }
    
    private var color: Color {
        switch event {
        case .runStarted, .stepStarted:
            return .blue
        case .stepCompleted, .runCompleted:
            return .green
        case .stepFailed, .runFailed:
            return .red
        }
    }
    
    private var title: String {
        switch event {
        case .runStarted(let e):
            return "Run Started: \(e.runbookName)"
        case .stepStarted(let e):
            return "Step: \(e.stepName)"
        case .stepCompleted(let e):
            if let outputs = e.outputs, !outputs.isEmpty {
                return "Step Completed (outputs: \(outputs.count))"
            }
            return "Step Completed"
        case .stepFailed(let e):
            return "Step Failed: \(e.error)"
        case .runCompleted:
            return "Run Completed"
        case .runFailed(let e):
            return "Run Failed: \(e.error)"
        }
    }
    
    private var detail: String? {
        switch event {
        case .runStarted(let e):
            return "Actor: \(e.actor)"
        case .stepStarted(let e):
            return "ID: \(e.stepID)"
        case .stepCompleted(let e):
            if let outputs = e.outputs {
                return outputs.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            }
            return nil
        case .stepFailed:
            return nil
        case .runCompleted, .runFailed:
            return nil
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
