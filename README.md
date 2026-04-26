# gert-sdk-ios

**Embedded gert runbook execution for iOS apps**

`gert-sdk-ios` is a Swift Package that brings the gert runbook engine to iOS. Execute structured, governed runbooks directly on-device with offline-first architecture and optional server sync.

## Features

- 📦 **Load kit bundles** — Load `.kit/` directories with manifest, tools, and runbooks
- 🚀 **Eager dependency resolution** — Validates all tool implementations at load time
- 🔐 **Capability gating** — Automatically checks camera, location, NFC, biometrics, bluetooth, and notifications availability
- 📝 **JSONL trace events** — Local trace file for every run, ready to sync
- ☁️ **Server sync** — Push completed runs to a gert server via streaming JSONL API
- 🔌 **Platform handlers** — Native Swift implementations for iOS-specific capabilities
- ⚡️ **100% async/await** — Built on Swift's structured concurrency

## Requirements

- iOS 16.0+ / macOS 13.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add `gert-sdk-ios` to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ormasoftchile/gert-sdk-ios.git", from: "0.1.0")
]
```

Or add it via Xcode:
1. File → Add Packages...
2. Enter repository URL: `https://github.com/ormasoftchile/gert-sdk-ios`
3. Select version rule and add to your target

## Quick Start

### 1. Load a Kit

```swift
import GertSDK

// Load from a local kit bundle
let kitURL = Bundle.main.url(forResource: "pool-maintenance", withExtension: "kit")!
let kit = try await GertSDK.loadKit(from: kitURL)

// Or download from a server
let kit = try await GertSDK.loadKit(named: "gert-mobile-platform", version: "1.0.0")
```

### 2. Run a Runbook

```swift
// Start a run
let session = try await kit.startRun(
    runbook: "pool-weekly-check",
    actor: "alice@example.com"
)

// Start execution
try await session.start()

// Stream events as they happen
for await event in session.events {
    switch event {
    case .stepCompleted(let step):
        print("✓ Step completed: \(step.stepID)")
    case .stepFailed(let step):
        print("✗ Step failed: \(step.error)")
    default:
        break
    }
}

// Wait for completion
let completedRun = try await session.wait()
```

### 3. Sync to Server

```swift
// Push the completed run to your gert server
try await GertSDK.syncRun(
    completedRun,
    to: URL(string: "https://gert.example.com")!,
    authToken: "your-api-token"
)
```

## Supported Capabilities

`gert-sdk-ios` includes built-in handlers for these iOS capabilities:

| Capability | Token | System Framework |
|------------|-------|------------------|
| Camera | `capability/camera` | AVFoundation |
| Location | `capability/location` | CoreLocation |
| NFC | `capability/nfc` | CoreNFC |
| Biometrics | `capability/biometrics` | LocalAuthentication |
| Bluetooth | `capability/bluetooth` | CoreBluetooth |
| Notifications | `capability/notifications` | UserNotifications |

All capabilities are checked at kit load time. If a required capability is unavailable, `loadKit()` throws `KitLoadError.missingCapability`.

## Architecture

### Kit Bundle Format

A `.kit/` directory contains:

```
pool-maintenance.kit/
  manifest.json          # Kit metadata and dependencies
  catalog/               # Tool catalog YAML
  runbooks/              # Runbook YAML definitions
  tools/                 # Tool implementation configs
  assets/                # Images, templates, etc.
```

### Platform Implementations

Tools declare platform-specific handlers in their YAML:

```yaml
name: capture-photo
impl:
  ios:
    transport: native-sdk
    handler: capability/camera
  android:
    transport: native-sdk
    handler: capability/camera
```

The iOS SDK resolves `capability/camera` to `CameraHandler` at runtime.

### Trace Format

Every run writes JSONL trace events locally:

```jsonl
{"type":"run/started","run_id":"abc123","kit_name":"pool-maintenance","runbook_name":"weekly-check","actor":"alice","timestamp":"2025-01-15T10:00:00Z"}
{"type":"step/started","run_id":"abc123","step_id":"s1","step_name":"check-ph","timestamp":"2025-01-15T10:00:01Z"}
{"type":"step/completed","run_id":"abc123","step_id":"s1","outputs":{"ph":"7.2"},"timestamp":"2025-01-15T10:00:05Z"}
{"type":"run/completed","run_id":"abc123","timestamp":"2025-01-15T10:05:00Z"}
```

These events can be synced to a gert server via `POST /api/v1/runs/ingest`.

## Custom Handlers

You can register custom platform handlers:

```swift
import GertSDK

class MyCustomHandler: GertToolHandler {
    var capability: String { "capability/my-custom" }
    
    func execute(inputs: [String: Any]) async throws -> [String: Any] {
        // Your implementation
        return ["result": "success"]
    }
    
    func checkAvailability() async -> Bool {
        // Check if available
        return true
    }
}

// Register before loading kits
PlatformHandlerRegistry.shared.register(MyCustomHandler())
```

## Examples

### Home Automation Example

Complete end-to-end SwiftUI app demonstrating the full kit lifecycle:

```
Examples/HomeAutomationExample/
├── Kitfile.yaml                      # Declares gert-domain-home dependency
├── HomeAutomationApp.swift           # SwiftUI app entry point
├── HomeAutomationViewModel.swift     # ObservableObject managing kit lifecycle
├── ContentView.swift                 # UI with event streaming
└── README.md                         # Setup and usage guide
```

**What it demonstrates:**
- Kitfile.yaml → gert kit fetch → GertSDK.loadKit → kit.startRun flow
- SwiftUI integration with async/await
- Real-time event streaming to UI
- Idiomatic iOS patterns (@Published, ObservableObject, Task)

**How to run:**
```bash
cd Examples/HomeAutomationExample
gert kit fetch  # Downloads gert-domain-home.kit bundle
open ../../Package.swift  # Open in Xcode
```

See [Examples/HomeAutomationExample/README.md](Examples/HomeAutomationExample/README.md) for full details.

## Roadmap

- [x] Core SDK structure and API surface
- [x] Kit loading and dependency resolution
- [x] Platform handler stubs
- [x] JSONL trace writer
- [x] Sync client (ingest API)
- [x] HomeAutomationExample — full e2e SwiftUI demo
- [ ] Local gert engine integration (Go via xcframework or Swift interpreter)
- [ ] Full platform handler implementations
- [ ] Background URLSession for kit pulls
- [ ] Offline queue for run sync

## License

MIT

## Contributing

This is an early-stage project. Contributions welcome!

1. Fork the repo
2. Create a feature branch
3. Add tests for your changes
4. Submit a pull request

## Links

- [gert core engine](https://github.com/ormasoftchile/gert)
- [gert mobile platform kit](https://github.com/ormasoftchile/gert-mobile-platform)
- [gert-sdk-android](https://github.com/ormasoftchile/gert-sdk-android) (Android counterpart)
