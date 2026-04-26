import Foundation

/// TraceWriter writes JSONL trace events to local storage.
public class TraceWriter {
    private let runID: String
    private let fileHandle: FileHandle
    private let fileURL: URL
    
    /// Creates a new trace writer for a run.
    /// - Parameter runID: Unique run identifier
    /// - Parameter directory: Directory to write trace file (defaults to app support)
    /// - Throws: If trace file cannot be created
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
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
        try fileHandle.seekToEnd()
    }
    
    /// Write a trace event to the JSONL file.
    /// - Parameter event: The event to write
    /// - Throws: If write fails
    public func write(_ event: RunEvent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(event)
        
        try fileHandle.write(contentsOf: data)
        try fileHandle.write(contentsOf: Data("\n".utf8))
        try fileHandle.synchronize()
    }
    
    /// Close the trace writer.
    public func close() throws {
        try fileHandle.close()
    }
    
    /// Read all events from the trace file.
    public func readAll() throws -> [RunEvent] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(separator: "\n")
        
        let decoder = JSONDecoder()
        return try lines.map { line in
            let data = Data(line.utf8)
            return try decoder.decode(RunEvent.self, from: data)
        }
    }
    
    deinit {
        try? fileHandle.close()
    }
}
