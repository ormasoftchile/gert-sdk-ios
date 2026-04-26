import Foundation

/// Writes RuntimeEvent JSONL trace lines to local storage.
public class TraceWriter {
    private let runID:      String
    private let fileHandle: FileHandle
    private let fileURL:    URL

    /// Creates a new trace writer for a run.
    /// - Parameters:
    ///   - runID: Unique run identifier
    ///   - directory: Directory to write the trace file (defaults to app support)
    /// - Throws: If the trace file cannot be created
    public init(runID: String, directory: URL? = nil) throws {
        self.runID = runID

        let traceDir = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("gert/traces")

        try FileManager.default.createDirectory(
            at: traceDir,
            withIntermediateDirectories: true
        )

        self.fileURL = traceDir.appendingPathComponent("\(runID).jsonl")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        self.fileHandle = try FileHandle(forWritingTo: fileURL)
        try fileHandle.seekToEnd()
    }

    /// Append a RuntimeEvent as a JSON line to the trace file.
    /// - Throws: If encoding or writing fails.
    public func write(_ event: RuntimeEvent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(event)
        try fileHandle.write(contentsOf: data)
        try fileHandle.write(contentsOf: Data("\n".utf8))
        try fileHandle.synchronize()
    }

    /// Close the trace file handle.
    public func close() throws {
        try fileHandle.close()
    }

    /// Read all events from the trace file.
    /// - Throws: If reading or decoding fails.
    public func readAll() throws -> [RuntimeEvent] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = JSONDecoder()
        return try content
            .split(separator: "\n")
            .map { try decoder.decode(RuntimeEvent.self, from: Data($0.utf8)) }
    }

    deinit {
        try? fileHandle.close()
    }
}
