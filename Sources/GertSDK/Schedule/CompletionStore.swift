import Foundation

// CompletionStore records when a routine was last completed. The
// Scheduler reads from it to decide what's due. The protocol exists
// so a host can plug in CoreData / SQLite / a sync-backed store
// without the SDK caring how the data is persisted.
public protocol CompletionStore: Sendable {
    /// The most recent completion time for `routineID`, or nil if the
    /// routine has never been completed.
    func lastCompletion(routineID: String) async -> Date?

    /// Records a successful completion at `at`.
    func recordCompletion(routineID: String, at: Date) async
}

// InMemoryCompletionStore is a minimal default for tests, demos, and
// single-session use. Persisting hosts should provide their own.
public actor InMemoryCompletionStore: CompletionStore {
    private var completions: [String: Date] = [:]

    public init(seed: [String: Date] = [:]) {
        self.completions = seed
    }

    public func lastCompletion(routineID: String) async -> Date? {
        completions[routineID]
    }

    public func recordCompletion(routineID: String, at: Date) async {
        if let existing = completions[routineID], existing >= at { return }
        completions[routineID] = at
    }

    public func snapshot() -> [String: Date] { completions }
}

// UserDefaultsCompletionStore persists completions in UserDefaults so
// they survive app launches. Suitable for a single-user app like the
// Casa Santiago demo. Stores all entries under one key, encoded as
// [routineID: ISO-8601 date string].
public actor UserDefaultsCompletionStore: CompletionStore {
    private let defaults: UserDefaults
    private let key: String
    private var completions: [String: Date]

    public init(defaults: UserDefaults = .standard, key: String = "gert.completions") {
        self.defaults = defaults
        self.key = key
        if let raw = defaults.dictionary(forKey: key) as? [String: String] {
            let formatter = ISO8601DateFormatter()
            var parsed: [String: Date] = [:]
            for (k, v) in raw {
                if let d = formatter.date(from: v) { parsed[k] = d }
            }
            self.completions = parsed
        } else {
            self.completions = [:]
        }
    }

    public func lastCompletion(routineID: String) async -> Date? {
        completions[routineID]
    }

    public func recordCompletion(routineID: String, at: Date) async {
        if let existing = completions[routineID], existing >= at { return }
        completions[routineID] = at
        persist()
    }

    public func snapshot() -> [String: Date] { completions }

    private func persist() {
        let formatter = ISO8601DateFormatter()
        let encoded = completions.mapValues { formatter.string(from: $0) }
        defaults.set(encoded, forKey: key)
    }
}
