import XCTest
@testable import GertSDK

final class KitLoaderTests: XCTestCase {
    
    // Use absolute path to the gert-mobile-platform kit for integration tests
    let kitURL = URL(fileURLWithPath: "/Volumes/Projects/gert-mobile-platform/gert-mobile-platform.kit")
    
    func testLoadKitFromValidBundle() async throws {
        // Load the actual gert-mobile-platform kit
        let kit = try await KitLoader.load(from: kitURL, skipCapabilityCheck: true)
        
        // Verify manifest
        XCTAssertEqual(kit.manifest.name, "gert-mobile-platform")
        XCTAssertEqual(kit.manifest.version, "0.1.0")
        
        // Verify tools are loaded (should have 6 tools)
        XCTAssertEqual(kit.tools.count, 6, "Expected 6 tools in kit")
        
        let toolNames = Set(kit.tools.map { $0.name })
        XCTAssertTrue(toolNames.contains("camera.capture"))
        XCTAssertTrue(toolNames.contains("location.read"))
        XCTAssertTrue(toolNames.contains("nfc.scan"))
        XCTAssertTrue(toolNames.contains("biometrics.confirm"))
        XCTAssertTrue(toolNames.contains("bluetooth.scan"))
        XCTAssertTrue(toolNames.contains("notifications.local"))
        
        // Verify runbooks are loaded
        XCTAssertGreaterThan(kit.runbooks.count, 0, "Expected at least one runbook")
        let runbookNames = kit.runbooks.map { $0.name }
        XCTAssertTrue(runbookNames.contains("pool-weekly-check"))
        
        // Verify pool-weekly-check runbook structure
        if let poolCheck = kit.runbooks.first(where: { $0.name == "pool-weekly-check" }) {
            XCTAssertEqual(poolCheck.steps.count, 4, "Expected 4 steps in pool-weekly-check")
            XCTAssertEqual(poolCheck.steps[0].id, "verify-location")
            XCTAssertEqual(poolCheck.steps[1].id, "take-photo")
            XCTAssertEqual(poolCheck.steps[2].id, "confirm-work")
            XCTAssertEqual(poolCheck.steps[3].id, "send-notification")
        }
    }
    
    func testLoadKitThrowsWhenManifestMissing() async throws {
        // Create a temporary directory without manifest.json
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Should throw KitLoadError.manifestMissing
        do {
            _ = try await KitLoader.load(from: tempDir, skipCapabilityCheck: true)
            XCTFail("Expected KitLoadError.manifestMissing to be thrown")
        } catch KitLoadError.manifestMissing {
            // Success
        } catch {
            XCTFail("Expected KitLoadError.manifestMissing, got \(error)")
        }
    }
    
    func testLoadKitThrowsWhenToolMissingIOSImpl() async throws {
        // Create a temporary kit with a tool missing iOS impl
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let toolsDir = tempDir.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: toolsDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create manifest.json
        let manifest = """
        {
            "name": "test-kit",
            "version": "1.0.0",
            "target": ["ios"]
        }
        """
        try manifest.write(to: tempDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        
        // Create a tool with only Android impl (no iOS impl)
        let toolYAML = """
        name: test.tool
        version: "1.0"
        apiVersion: gert.dev/v2
        description: Test tool without iOS impl
        requires-capabilities: []
        impl:
          android:
            transport: native-sdk
            handler: com.test.Tool
        """
        try toolYAML.write(to: toolsDir.appendingPathComponent("test.tool.tool.yaml"), atomically: true, encoding: .utf8)
        
        // Should throw KitLoadError.missingPlatformImpl
        do {
            _ = try await KitLoader.load(from: tempDir, skipCapabilityCheck: true)
            XCTFail("Expected KitLoadError.missingPlatformImpl to be thrown")
        } catch KitLoadError.missingPlatformImpl(let toolName, let platform) {
            XCTAssertEqual(toolName, "test.tool")
            XCTAssertEqual(platform, "ios")
        } catch {
            XCTFail("Expected KitLoadError.missingPlatformImpl, got \(error)")
        }
    }
}
