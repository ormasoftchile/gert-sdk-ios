import SwiftUI
import GertSDK

/// HomeAutomationApp demonstrates end-to-end gert kit usage on iOS.
///
/// Flow:
/// 1. App launches → ViewModel initializes
/// 2. User taps "Load Kit" → loadKit() fetches gert-domain-home bundle
/// 3. User taps "Turn On Lights" → startRun() executes runbook
/// 4. Events stream to UI as run progresses
///
/// Prerequisites:
/// - Run `gert kit fetch` in this directory to download kit bundles
/// - Kit bundles should be in ./.gert-kits/gert-domain-home.kit/
@main
struct HomeAutomationApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
