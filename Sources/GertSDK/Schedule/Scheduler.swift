import Foundation

// ScheduledRoutine pairs a kit index entry with its computed status
// at a given reference time. The Scheduler returns one per routine
// in the kit, sorted by urgency.
public struct ScheduledRoutine: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// Never completed, or no cadence declared. Always actionable.
        case neverCompleted
        /// Past its due date by `by` seconds.
        case overdue(by: TimeInterval)
        /// Due now (within `dueWindow` of the reference time).
        case dueNow
        /// Not yet due; will become due in `in` seconds.
        case upcoming(in: TimeInterval)
    }

    public let entry: HomeKitIndex.Entry
    public let cadence: Cadence?
    public let lastCompleted: Date?
    public let nextDue: Date?
    public let status: Status

    /// Sort key used by Scheduler. Smaller = more urgent.
    var urgency: Double {
        switch status {
        case .neverCompleted:     return -.infinity
        case .overdue(let by):    return -by               // more overdue → smaller
        case .dueNow:             return 0
        case .upcoming(let inSec): return inSec
        }
    }
}

// Scheduler computes routine status for an entire kit at a given
// reference time. It is pure: same inputs → same outputs, no clocks
// or stores hidden inside. Hosts inject `now` for tests.
public struct Scheduler: Sendable {
    /// How close to the due date counts as "due now" rather than
    /// "upcoming". One hour by default.
    public let dueWindow: TimeInterval

    public init(dueWindow: TimeInterval = 3600) {
        self.dueWindow = dueWindow
    }

    /// Returns one ScheduledRoutine per routine in the kit, sorted by
    /// urgency (overdue first, then dueNow, then upcoming).
    public func schedule(
        kit: LoadedKit,
        completions: CompletionStore,
        now: Date = Date()
    ) async -> [ScheduledRoutine] {
        var out: [ScheduledRoutine] = []
        out.reserveCapacity(kit.routines.count)

        for entry in kit.routines {
            let cadence = entry.cadence.flatMap { try? Cadence.parse($0) }
            let anchor = CadenceAnchor.from(metadata: entry.metadata)
            let last = await completions.lastCompletion(routineID: entry.id)
            out.append(makeScheduled(
                entry: entry, cadence: cadence, anchor: anchor, last: last, now: now
            ))
        }
        out.sort { $0.urgency < $1.urgency }
        return out
    }

    private func makeScheduled(
        entry: HomeKitIndex.Entry,
        cadence: Cadence?,
        anchor: CadenceAnchor?,
        last: Date?,
        now: Date
    ) -> ScheduledRoutine {
        guard let cadence else {
            // No cadence → treat as always actionable but never urgent.
            return ScheduledRoutine(
                entry: entry, cadence: nil,
                lastCompleted: last, nextDue: nil,
                status: last == nil ? .neverCompleted : .dueNow
            )
        }

        // When the kit author declared an absolute anchor, scheduling
        // is driven by the anchor rule rather than a relative offset
        // from `last`. Anchor wins on conflict (a late completion
        // does not shift the cadence to a new weekday).
        if let anchor {
            let reference = last ?? now
            // For first-time scheduling we want the next occurrence on
            // or after `now`. Once a completion exists we want strictly
            // after the completion so the same anchor isn't reused.
            let inclusive = (last == nil)
            let next = anchor.nextOccurrence(
                onOrAfter: reference,
                cadenceInterval: cadence.approximateInterval,
                inclusive: inclusive
            )
            let delta = next.timeIntervalSince(now)
            let status: ScheduledRoutine.Status
            if delta < -dueWindow {
                status = .overdue(by: -delta)
            } else if delta <= dueWindow {
                status = .dueNow
            } else {
                status = .upcoming(in: delta)
            }
            return ScheduledRoutine(
                entry: entry, cadence: cadence,
                lastCompleted: last, nextDue: next, status: status
            )
        }

        guard let last else {
            return ScheduledRoutine(
                entry: entry, cadence: cadence,
                lastCompleted: nil, nextDue: nil,
                status: .neverCompleted
            )
        }

        let next = last.addingTimeInterval(cadence.approximateInterval)
        let delta = next.timeIntervalSince(now)
        let status: ScheduledRoutine.Status
        if delta < -dueWindow {
            status = .overdue(by: -delta)
        } else if delta <= dueWindow {
            status = .dueNow
        } else {
            status = .upcoming(in: delta)
        }
        return ScheduledRoutine(
            entry: entry, cadence: cadence,
            lastCompleted: last, nextDue: next, status: status
        )
    }
}

public extension Scheduler {
    /// Convenience: filter the schedule to actionable routines
    /// (everything except `upcoming`).
    func actionable(
        kit: LoadedKit,
        completions: CompletionStore,
        now: Date = Date()
    ) async -> [ScheduledRoutine] {
        let all = await schedule(kit: kit, completions: completions, now: now)
        return all.filter {
            switch $0.status {
            case .upcoming: return false
            default:        return true
            }
        }
    }
}
