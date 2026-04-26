import Foundation

/// IngestClient streams completed runs to POST /api/v1/runs/ingest
public class IngestClient {
    private let serverURL: URL
    private let authToken: String?
    private let session: URLSession
    
    init(serverURL: URL, authToken: String?, session: URLSession) {
        self.serverURL = serverURL
        self.authToken = authToken
        self.session = session
    }
    
    /// Ingest a completed run by streaming events as JSONL
    /// - Parameter run: The completed run to ingest
    /// - Throws: If the request fails
    public func ingest(_ run: CompletedRun) async throws {
        let ingestURL = serverURL.appendingPathComponent("/api/v1/runs/ingest")
        
        var request = URLRequest(url: ingestURL)
        request.httpMethod = "POST"
        request.setValue("application/jsonl", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Encode events as JSONL
        let jsonlData = try encodeEventsAsJSONL(run.events)
        request.httpBody = jsonlData
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IngestError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw IngestError.httpError(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
    }
    
    private func encodeEventsAsJSONL(_ events: [RunEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        
        var result = Data()
        for (index, event) in events.enumerated() {
            let eventData = try encoder.encode(event)
            result.append(eventData)
            if index < events.count - 1 {
                result.append(Data("\n".utf8))
            }
        }
        
        return result
    }
}

public enum IngestError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let body):
            if let body = body {
                return "HTTP \(code): \(body)"
            } else {
                return "HTTP \(code)"
            }
        }
    }
}
