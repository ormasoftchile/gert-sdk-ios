import Foundation

/// SyncClient handles pulling kits and pushing runs to a gert server.
public class SyncClient {
    private let serverURL: URL
    private let authToken: String?
    private let session: URLSession
    
    /// Initialize a sync client
    /// - Parameters:
    ///   - serverURL: Base URL of the gert server
    ///   - authToken: Optional authentication token
    ///   - session: URLSession to use (defaults to .shared)
    public init(serverURL: URL, authToken: String? = nil, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.authToken = authToken
        self.session = session
    }
    
    /// Pull a kit by name from the server's kit registry
    /// - Parameters:
    ///   - name: Kit name
    ///   - version: Kit version (optional, defaults to latest)
    /// - Returns: URL to the downloaded kit bundle
    /// - Throws: If download fails
    public func pullKit(name: String, version: String? = nil) async throws -> URL {
        fatalError("Not yet implemented")
    }
    
    /// Push a completed run to the server
    /// - Parameter run: The completed run to sync
    /// - Throws: If upload fails
    public func pushRun(_ run: CompletedRun) async throws {
        let ingestClient = IngestClient(serverURL: serverURL, authToken: authToken, session: session)
        try await ingestClient.ingest(run)
    }
}
