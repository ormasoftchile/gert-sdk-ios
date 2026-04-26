# Home Automation Example

A complete end-to-end SwiftUI app demonstrating gert kit usage on iOS.

## What This Example Demonstrates

This example shows the full flow of loading and executing a domain kit (`gert-domain-home`) on iOS:

1. **Kit Declaration** — `Kitfile.yaml` declares dependencies on `gert-domain-home` and `gert-mobile-platform`
2. **Kit Fetching** — Use `gert kit fetch` to download kit bundles locally
3. **Kit Loading** — `GertSDK.loadKit(from:)` loads the kit bundle and validates all tools have iOS implementations
4. **Runbook Execution** — `kit.startRun()` executes a runbook with async/await
5. **Event Streaming** — Real-time event stream updates the SwiftUI UI as the run progresses

## Architecture

```
HomeAutomationApp.swift          SwiftUI app entry point
├── ContentView.swift            Main UI with kit status and action buttons
└── HomeAutomationViewModel.swift ObservableObject managing kit lifecycle
    ├── loadKit()                Loads gert-domain-home kit bundle
    ├── turnOnLights()           Executes "turn-on-lights" runbook
    └── checkPresence()          Executes "check-presence" runbook
```

## Prerequisites

### 1. Install gert CLI

```bash
brew install gert
# or
go install github.com/ormasoftchile/gert/cmd/gert@latest
```

### 2. Fetch Kit Bundles

Before opening in Xcode, fetch the required kits:

```bash
cd Examples/HomeAutomationExample
gert kit fetch
```

This downloads kit bundles to `.gert-kits/`:

```
.gert-kits/
├── gert-domain-home.kit/
│   ├── manifest.json
│   ├── runbooks/
│   │   ├── turn-on-lights.runbook.yaml
│   │   └── check-presence.runbook.yaml
│   └── tools/
│       └── ...
└── gert-mobile-platform.kit/
    └── ...
```

### 3. Open in Xcode

```bash
cd ../..
open Package.swift
```

## How to Run

1. **Build** the GertSDK framework in Xcode
2. **Run** the HomeAutomationExample target
3. **Tap "Load Kit"** to load the `gert-domain-home` kit bundle
4. **Tap "Turn On Lights"** or **"Check Presence"** to execute a runbook
5. **Watch events** stream in real-time as the run progresses

## API Flow

```swift
// 1. Load kit from local bundle
let kitURL = URL(fileURLWithPath: ".gert-kits/gert-domain-home.kit")
let kit = try await GertSDK.loadKit(from: kitURL)

// 2. Start a runbook execution
let session = try await kit.startRun(
    runbook: "turn-on-lights",
    actor: "alice@example.com"
)

// 3. Stream events as they occur
for await event in session.events {
    switch event {
    case .runStarted(let e):
        print("Run started: \(e.runbookName)")
    case .stepStarted(let e):
        print("Step started: \(e.stepName)")
    case .stepCompleted(let e):
        print("Step completed with outputs: \(e.outputs ?? [:])")
    case .runCompleted:
        print("Run completed successfully")
    default:
        break
    }
}

// 4. Wait for final result
let result = try await session.wait()
```

## SwiftUI Integration

The example demonstrates idiomatic SwiftUI patterns:

- **`@StateObject`** for ViewModel lifecycle
- **`@Published`** properties for reactive UI updates
- **`Task {}`** for async/await in button actions
- **`AsyncStream`** consumed with `for await` loop
- **`ObservableObject`** for MVVM architecture

## Kit Bundle Structure

The `gert-domain-home` kit follows the standard `.kit/` bundle format:

```
gert-domain-home.kit/
├── manifest.json              Kit metadata and dependencies
├── runbooks/
│   ├── turn-on-lights.runbook.yaml    Runbook: check presence → get state → turn on
│   └── check-presence.runbook.yaml    Runbook: query motion sensor
└── tools/
    ├── motion-sensor.tool.yaml        Tool: read motion sensor state
    ├── smart-light.tool.yaml          Tool: control smart lights
    └── ...
```

Each tool declares platform implementations:

```yaml
name: smart-light
description: Control Philips Hue smart lights
requires-capabilities:
  - capability/bluetooth
impl:
  ios:
    transport: native-sdk
    handler: SmartLightHandler
  android:
    transport: native-sdk
    handler: com.gert.platform.SmartLightHandler
```

## Error Handling

The SDK provides structured errors:

- **`KitLoadError.missingPlatformImpl`** — Tool lacks iOS implementation
- **`KitLoadError.missingCapability`** — Required capability unavailable (e.g., Bluetooth disabled)
- **`KitLoadError.manifestMissing`** — Kit bundle missing manifest.json
- **`KitError.runbookNotFound`** — Requested runbook not in kit

All errors conform to `LocalizedError` for user-friendly messages.

## Production Deployment

In a production app:

1. **Bundle kits** in app Resources/ folder, or
2. **Download kits** at runtime via `GertSDK.loadKit(named:version:)` (coming soon)
3. **Sync completed runs** to gert server via `GertSDK.syncRun()` (coming soon)

## Next Steps

- Add input parameters to runbooks (e.g., `inputs: ["room": "bedroom"]`)
- Implement offline-first sync (local execution → background sync)
- Add capability permission UI flows (Camera, Location, Bluetooth)
- Build custom platform handlers for domain-specific tools

## See Also

- [GertSDK API Documentation](../../docs/API.md)
- [Platform Handler Guide](../../docs/PlatformHandlers.md)
- [Kit Bundle Format Spec](https://github.com/ormasoftchile/gert/blob/main/docs/kit-bundle-format.md)
