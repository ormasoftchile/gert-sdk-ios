import XCTest
@testable import GertSDK

// IngestStubProtocol records every request hitting it so tests can
// assert on URL, method, headers, and body. It accepts any path.
final class IngestStubProtocol: URLProtocol {
    static let queue = DispatchQueue(label: "gert.test.ingest")
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var responseStatus: Int = 200
    nonisolated(unsafe) static var responseBody: Data = Data(#"{"run_id":"srv-123","events_received":3}"#.utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.queue.sync {
            Self.lastRequest = self.request
            // URLProtocol strips httpBody when a stream is used; read either.
            if let data = self.request.httpBody {
                Self.lastBody = data
            } else if let stream = self.request.httpBodyStream {
                Self.lastBody = Self.readAll(stream)
            }
        }
        let resp = HTTPURLResponse(
            url: self.request.url!,
            statusCode: Self.responseStatus,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        self.client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: Self.responseBody)
        self.client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var buf = Data()
        let bufSize = 4096
        var bytes = [UInt8](repeating: 0, count: bufSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&bytes, maxLength: bufSize)
            if read <= 0 { break }
            buf.append(bytes, count: read)
        }
        return buf
    }
}

final class SyncClientTests: XCTestCase {
    private func makeClient() -> SyncClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [IngestStubProtocol.self]
        return SyncClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: cfg))
    }

    private func makeRun(eventCount: Int = 3, runbookID: String = "casa-santiago.routine.pool_clean") -> CompletedRun {
        var events: [RuntimeEvent] = []
        events.append(RuntimeEvent(sequence: 0, kind: RuntimeEvent.runStarted, runID: "run-1"))
        for i in 1..<(eventCount - 1) {
            events.append(RuntimeEvent(sequence: i, kind: RuntimeEvent.stepStarted, runID: "run-1", stepID: "step-\(i)", stepIndex: i - 1))
        }
        events.append(RuntimeEvent(sequence: eventCount - 1, kind: RuntimeEvent.runCompleted, runID: "run-1"))
        return CompletedRun(
            runID: "run-1", kitName: "casa-santiago", runbookID: runbookID, actor: "alice",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_010),
            status: .succeeded, events: events
        )
    }

    func testHappyPath() async throws {
        IngestStubProtocol.responseStatus = 200
        IngestStubProtocol.responseBody = Data(#"{"run_id":"srv-abc","events_received":3}"#.utf8)
        let result = try await makeClient().uploadRun(makeRun())

        XCTAssertEqual(result.serverRunID, "srv-abc")
        XCTAssertEqual(result.eventsReceived, 3)

        let req = IngestStubProtocol.lastRequest!
        XCTAssertEqual(req.url?.path, "/api/v1/runs/ingest")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/x-ndjson")

        let body = String(data: IngestStubProtocol.lastBody ?? Data(), encoding: .utf8) ?? ""
        let lines = body.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains(#""kind":"run\/started""#) || lines[0].contains(#""kind":"run/started""#))
        XCTAssertTrue(lines[0].contains(#""runbook_id":"casa-santiago.routine.pool_clean""#))
        XCTAssertTrue(body.contains(#""sequence":0"#))
    }

    func testNonOKStatus() async throws {
        IngestStubProtocol.responseStatus = 400
        IngestStubProtocol.responseBody = Data("first event must be run/started".utf8)
        do {
            _ = try await makeClient().uploadRun(makeRun())
            XCTFail("expected failure")
        } catch SyncError.invalidStatus(let code, let body) {
            XCTAssertEqual(code, 400)
            XCTAssertTrue(body.contains("run/started"))
        }
    }

    func testRefusesEmptyRun() async {
        let run = CompletedRun(
            runID: "x", kitName: "k", runbookID: "r", actor: "a",
            startedAt: Date(), completedAt: Date(), status: .succeeded, events: []
        )
        do {
            _ = try await makeClient().uploadRun(run)
            XCTFail("expected failure")
        } catch SyncError.noEvents {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
