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

    // MARK: - Delegations

    /// Pushes the full delegation list for a property to the server.
    /// Idempotent: server replaces the prior value. Used by the
    /// owner-side app whenever UserDelegationsStore mutates.
    @discardableResult
    public func putDelegations(propertyID: String, delegations: [Delegation]) async throws -> Int {
        struct Body: Encodable { let delegations: [Delegation] }
        let body = try JSONEncoder().encode(Body(delegations: delegations))
        var req = URLRequest(url: baseURL.appendingPathComponent(
            "/api/v1/properties/\(propertyID)/delegations"
        ))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidStatus(code, body: String(data: data, encoding: .utf8) ?? "")
        }
        struct R: Decodable { let stored: Int }
        return ((try? JSONDecoder().decode(R.self, from: data))?.stored) ?? 0
    }

    /// Issues an invite token resolving to the supplied delegation.
    /// The owner-side app shows `url` in a share sheet so the
    /// delegate can open it on their device.
    public struct InviteResult: Sendable, Equatable {
        public let token: String
        public let url: URL
        public let expiresAt: String
    }

    public func createInvite(propertyID: String,
                             delegation: Delegation,
                             ttlHours: Int = 168) async throws -> InviteResult {
        struct Body: Encodable {
            let propertyID: String
            let delegation: Delegation
            let ttlHours: Int
        }
        let body = try JSONEncoder().encode(
            Body(propertyID: propertyID, delegation: delegation, ttlHours: ttlHours)
        )
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/v1/invites"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidStatus(code, body: String(data: data, encoding: .utf8) ?? "")
        }
        struct R: Decodable { let token: String; let url: String; let expiresAt: String }
        let parsed = try JSONDecoder().decode(R.self, from: data)
        guard let url = URL(string: parsed.url) else {
            throw SyncError.invalidStatus(http.statusCode, body: "invalid URL: \(parsed.url)")
        }
        return InviteResult(token: parsed.token, url: url, expiresAt: parsed.expiresAt)
    }

    /// Redeems an invite token. On success the server returns the
    /// property id and the delegation the token was bound to. The
    /// delegate-side app pins this and switches identity to it.
    public struct RedeemResult: Sendable, Equatable {
        public let propertyID: String
        public let delegation: Delegation
    }

    public func redeemInvite(token: String) async throws -> RedeemResult {
        var req = URLRequest(url: baseURL.appendingPathComponent(
            "/api/v1/invites/\(token)/redeem"
        ))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw SyncError.invalidStatus(code, body: String(data: data, encoding: .utf8) ?? "")
        }
        struct R: Decodable { let propertyID: String; let delegation: Delegation }
        let parsed = try JSONDecoder().decode(R.self, from: data)
        return RedeemResult(propertyID: parsed.propertyID, delegation: parsed.delegation)
    }
}
