import SwiftUI

/// ComposeExample — Track A end-to-end demo.
///
/// Loads template definitions from the bundle, lets the user fill a
/// generic form to compose a routine, persists the resulting binding
/// through `FileRoutineStore` in the app's Documents directory.
///
/// Run on macOS:
///     swift run HomeAutomationExample        (the existing runtime demo)
///     swift run ComposeExample               (this one)
@main
struct ComposeExampleApp: App {
    var body: some Scene {
        WindowGroup("Compose") {
            if #available(iOS 16.0, macOS 13.0, *) {
                ComposeFlowView()
            } else {
                Text("Requires iOS 16 / macOS 13.")
            }
        }
    }
}
