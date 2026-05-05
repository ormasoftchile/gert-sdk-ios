import Foundation

public enum SyncError: Error, LocalizedError {
    case invalidStatus(Int, body: String)
    case noEvents
    case missingRunStarted
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidStatus(let code, let body):
            return "Sync rejected with HTTP \(code): \(body)"
        case .noEvents:
            return "Run has no events to sync"
        case .missingRunStarted:
            return "First event must be run/started"
        case .transport(let err):
            return "Transport error: \(err.localizedDescription)"
        }
    }
}

public struct SyncResult: Sendable, Equatable {
    /// The run id assigned by the server (may differ from the local one).
    public let serverRunID: String
    public let eventsReceived: Int
}

// SyncClient uploads a CompletedRun to a gert server. It is stateless
// and safe to share. Hosts construct one with a baseURL and an
// optional URLSession (tests inject one with a URLProtocol stub).
//
// Wire format: NDJSON of trace envelopes, content-type
// application/x-ndjson. The endpoint is POST /api/v1/runs/ingest.
public struct SyncClient: Sendable {
    public let baseURL: URL
    public let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    @discardableResult
    public func uploadRun(_ run: CompletedRun) async throws -> SyncResult {
        guard !run.events.isEmpty else { throw SyncError.noEvents }
        guard run.events.first?.kind == RuntimeEvent.runStarted else {
            throw SyncError.missingRunStarted
        }

        let body = try Self.encodeNDJSON(events: run.events, runbookID: run.runbookID)

        var request = URLRequest(url: baseURL.appendingPathComponent("/api/v1/runs/ingest"))
        request.httpMethod = "POST"
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SyncError.invalidStatus(0, body: "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SyncError.invalidStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        struct IngestResponse: Decodable {
            let run_id: String
            let events_received: Int
        }
        let parsed = try JSONDecoder().decode(IngestResponse.self, from: data)
        return SyncResult(serverRunID: parsed.run_id, eventsReceived: parsed.events_received)
    }

    /// Encodes events as one TraceEnvelope JSON object per line.
    /// Internal so tests can assert on the wire format directly.
    static func encodeNDJSON(events: [RuntimeEvent], runbookID: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var buf = Data()
        for ev in events {
            let env = TraceEnvelope.from(event: ev, runbookID: runbookID)
            let line = try encoder.encode(env)
            buf.append(line)
            buf.append(0x0A) // '\n'
        }
        return buf
    }
}
