//
//  RoutineStore.swift
//  GertSDK / Templates
//
//  Pluggable persistence for composed routines. The default
//  implementation writes one YAML file per routine into a directory
//  the host app owns (e.g. App Support/Routines/). Swap in any
//  RoutineStore conformer for cloud sync, encryption, etc.
//

import Foundation

/// Identifier + payload for a stored routine.
public struct StoredRoutine: Hashable {
    public let id: String
    public let bytes: String
    public init(id: String, bytes: String) {
        self.id = id
        self.bytes = bytes
    }
}

public protocol RoutineStore {
    /// Returns ids of all stored routines, sorted ascending.
    func list() throws -> [String]
    func get(id: String) throws -> StoredRoutine?
    func put(_ routine: StoredRoutine) throws
    func delete(id: String) throws
}

public enum StoreError: Error, CustomStringConvertible {
    case invalidID(String)
    case ioFailed(String, Error)
    public var description: String {
        switch self {
        case let .invalidID(id):    return "invalid routine id \"\(id)\""
        case let .ioFailed(p, e):   return "io failed at \(p): \(e)"
        }
    }
}

/// File-system store. Files are named `<id>.routine.yaml`. Routine
/// ids must match `^[a-z][a-z0-9_]*$` (same conservative shape used
/// by the Go compiler).
public final class FileRoutineStore: RoutineStore {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    private static let idRegex = try! NSRegularExpression(
        pattern: #"^[a-z][a-z0-9_]*$"#
    )

    private func validate(_ id: String) throws {
        let ns = id as NSString
        if FileRoutineStore.idRegex.firstMatch(
            in: id, range: NSRange(location: 0, length: ns.length)
        ) == nil {
            throw StoreError.invalidID(id)
        }
    }

    private func url(for id: String) -> URL {
        directory.appendingPathComponent("\(id).routine.yaml")
    }

    public func list() throws -> [String] {
        let fm = FileManager.default
        let names: [String]
        do {
            names = try fm.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw StoreError.ioFailed(directory.path, error)
        }
        let suffix = ".routine.yaml"
        return names
            .filter { $0.hasSuffix(suffix) }
            .map { String($0.dropLast(suffix.count)) }
            .sorted()
    }

    public func get(id: String) throws -> StoredRoutine? {
        try validate(id)
        let u = url(for: id)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        do {
            let bytes = try String(contentsOf: u, encoding: .utf8)
            return StoredRoutine(id: id, bytes: bytes)
        } catch {
            throw StoreError.ioFailed(u.path, error)
        }
    }

    public func put(_ routine: StoredRoutine) throws {
        try validate(routine.id)
        let u = url(for: routine.id)
        do {
            try routine.bytes.write(to: u, atomically: true, encoding: .utf8)
        } catch {
            throw StoreError.ioFailed(u.path, error)
        }
    }

    public func delete(id: String) throws {
        try validate(id)
        let u = url(for: id)
        let fm = FileManager.default
        if !fm.fileExists(atPath: u.path) { return }
        do {
            try fm.removeItem(at: u)
        } catch {
            throw StoreError.ioFailed(u.path, error)
        }
    }
}
