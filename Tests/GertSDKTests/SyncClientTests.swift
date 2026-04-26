import XCTest
@testable import GertSDK

final class SyncClientTests: XCTestCase {
    
    func testPushRunSuccess() async throws {
        // TODO: Implement test
        // 1. Create a mock URLSession that returns 200
        // 2. Create a CompletedRun
        // 3. Call syncClient.pushRun()
        // 4. Verify request was made with correct JSONL payload
    }
    
    func testPushRunThrowsOnHTTPError() async throws {
        // TODO: Implement test
        // Should throw IngestError.httpError when server returns 4xx/5xx
    }
    
    func testPullKitSuccess() async throws {
        // TODO: Implement test
        // 1. Mock server response with kit bundle
        // 2. Call syncClient.pullKit(name: "test-kit")
        // 3. Verify kit is downloaded to local URL
    }
}
