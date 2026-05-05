import XCTest
@testable import GertSDK

// EndToEndTests load the real Casa Santiago home kit produced by
// `home-compile` in the sibling gert-domain-home repository, register
// stub handlers for the platform tools the kit references, and run a
// full routine end-to-end.
//
// The test resolves the kit path relative to this source file so it
// works in the local workspace without copying fixtures. If the kit
// is not present (e.g. the SDK repo is checked out standalone), the
// tests are skipped rather than failed.
final class EndToEndTests: XCTestCase {

    // MARK: - Stub handlers

    private struct StubLocation: GertToolHandler {
        let toolName = "location.read"
        func execute(action: String, args: [String : Any]) async throws -> [String : Any] {
            ["lat": 33.45, "lon": -70.66, "accuracy_m": 12.0]
        }
    }

    private struct StubCamera: GertToolHandler {
        let toolName = "camera.capture"
        func execute(action: String, args: [String : Any]) async throws -> [String : Any] {
            ["asset_id": "asset-123", "uri": "file:///tmp/photo.jpg"]
        }
    }

    private struct StubCollector: CollectorResolver {
        func resolve(step: Step, runID: String) async throws -> [String : JSONValue] {
            // Echo a value for every declared field so we exercise the
            // full collector schema regardless of which routine runs.
            var out: [String: JSONValue] = [:]
            for f in step.fields ?? [] {
                out[f.name] = .string("stub-\(f.name)")
            }
            return out
        }
    }

    // MARK: - Helpers

    private func kitURL() throws -> URL {
        // Sources/GertSDK/... has no test resources; resolve from the
        // test file location up to the workspace root.
        let here = URL(fileURLWithPath: #filePath)
        let workspace = here.deletingLastPathComponent()  // GertSDKTests
            .deletingLastPathComponent()                  // Tests
            .deletingLastPathComponent()                  // gert-sdk-ios
            .deletingLastPathComponent()                  // <workspace root>
        let kit = workspace
            .appendingPathComponent("gert-domain-home")
            .appendingPathComponent("examples")
            .appendingPathComponent("casa-santiago.home.kit")
        if !FileManager.default.fileExists(atPath: kit.path) {
            throw XCTSkip("casa-santiago kit not found at \(kit.path)")
        }
        return kit
    }

    // MARK: - Tests

    func testLoadKit() throws {
        let kit = try KitLoader.load(from: try kitURL())
        XCTAssertEqual(kit.manifest.kind, "home")
        XCTAssertEqual(kit.manifest.propertyID, "casa-santiago")
        XCTAssertGreaterThan(kit.routines.count, 0)
        XCTAssertNotNil(kit.routine(id: "casa-santiago.routine.pool_clean"))
    }

    func testRunnableRoutinesGatedByHandlers() throws {
        let kit = try KitLoader.load(from: try kitURL())
        let runtime = GertRuntime(kit: kit)

        // No handlers registered → only routines without tool_deps run.
        let bare = runtime.runnableRoutines().map(\.id)
        XCTAssertFalse(bare.contains("casa-santiago.routine.pool_clean"))

        runtime.handlers.register(StubLocation())
        runtime.handlers.register(StubCamera())
        let withHandlers = runtime.runnableRoutines().map(\.id)
        XCTAssertTrue(withHandlers.contains("casa-santiago.routine.pool_clean"))
    }

    func testRunPoolClean() async throws {
        let kit = try KitLoader.load(from: try kitURL())
        let runtime = GertRuntime(kit: kit)
        runtime.handlers.register(StubLocation())
        runtime.handlers.register(StubCamera())

        let session = try runtime.startRun(
            routineID: "casa-santiago.routine.pool_clean",
            actor: "test-user",
            collector: StubCollector()
        )

        let summary = try await session.wait()
        XCTAssertEqual(summary.status, .succeeded)
        XCTAssertEqual(summary.runbookID, "casa-santiago.routine.pool_clean")

        let kinds = summary.events.map(\.kind)
        XCTAssertEqual(kinds.first, RuntimeEvent.runStarted)
        XCTAssertEqual(kinds.last, RuntimeEvent.runCompleted)
        XCTAssertTrue(kinds.contains(RuntimeEvent.toolInvoked))
        XCTAssertTrue(kinds.contains(RuntimeEvent.toolCompleted))

        // Three steps in the runbook: location.read, camera.capture, collector.
        let started = summary.events.filter { $0.kind == RuntimeEvent.stepStarted }
        XCTAssertEqual(started.count, 3)
    }
}
