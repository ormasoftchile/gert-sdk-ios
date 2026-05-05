import Foundation

// CadenceAnchor declares an absolute reference for when a routine
// first becomes due. Mirrors the schema introduced in
// gert-domain-home/specs/cadence-anchor.md. Hosts decode an anchor
// from a HomeKitIndex.Entry's metadata via `CadenceAnchor.from(_:)`.
public struct CadenceAnchor: Sendable, Equatable {
    public enum Rule: Sendable, Equatable {
        /// Recurring weekday rule (1 = Monday … 7 = Sunday, ISO 8601).
        case weekday(Int)
        /// Day of the month (1..31). Values exceeding the month's
        /// length clamp to the last day.
        case dayOfMonth(Int)
        /// One-time anchor date in the property's local time zone.
        /// The cadence repeats every interval starting from this date.
        case fixedDate(year: Int, month: Int, day: Int)
    }

    public let rule: Rule
    /// Local time of day. `nil` means start-of-day (00:00).
    public let timeOfDay: (hour: Int, minute: Int)?

    public init(rule: Rule, timeOfDay: (hour: Int, minute: Int)? = nil) {
        self.rule = rule
        self.timeOfDay = timeOfDay
    }

    public static func == (lhs: CadenceAnchor, rhs: CadenceAnchor) -> Bool {
        guard lhs.rule == rhs.rule else { return false }
        switch (lhs.timeOfDay, rhs.timeOfDay) {
        case (nil, nil): return true
        case let (l?, r?): return l == r
        default: return false
        }
    }

    /// Decodes an anchor from a routine's metadata dictionary, or
    /// returns nil when no anchor keys are present. Unrecognized
    /// values yield nil so old SDK builds reading future kits stay
    /// safe.
    public static func from(metadata: [String: String]?) -> CadenceAnchor? {
        guard let metadata else { return nil }
        let time = parseTime(metadata["anchor_time"])

        if let weekdayStr = metadata["anchor_weekday"]?.lowercased(),
           let iso = Self.weekdayMap[weekdayStr] {
            return CadenceAnchor(rule: .weekday(iso), timeOfDay: time)
        }
        if let domStr = metadata["anchor_day_of_month"], let dom = Int(domStr),
           (1...31).contains(dom) {
            return CadenceAnchor(rule: .dayOfMonth(dom), timeOfDay: time)
        }
        if let dateStr = metadata["anchor_date"],
           let parts = parseDate(dateStr) {
            return CadenceAnchor(
                rule: .fixedDate(year: parts.year, month: parts.month, day: parts.day),
                timeOfDay: time
            )
        }
        return nil
    }

    private static let weekdayMap: [String: Int] = [
        "monday": 1, "tuesday": 2, "wednesday": 3, "thursday": 4,
        "friday": 5, "saturday": 6, "sunday": 7
    ]

    private static func parseTime(_ s: String?) -> (hour: Int, minute: Int)? {
        guard let s, s.count == 5, s[s.index(s.startIndex, offsetBy: 2)] == ":" else {
            return nil
        }
        let h = Int(s.prefix(2))
        let m = Int(s.suffix(2))
        guard let hh = h, let mm = m, (0...23).contains(hh), (0...59).contains(mm) else {
            return nil
        }
        return (hh, mm)
    }

    private static func parseDate(_ s: String) -> (year: Int, month: Int, day: Int)? {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else {
            return nil
        }
        return (y, m, d)
    }
}

extension CadenceAnchor {
    /// Returns the first occurrence of this anchor on or after
    /// `reference`, evaluated in the supplied calendar (default: the
    /// user's current calendar, which honors the device time zone).
    /// If `inclusive` is false, the result is strictly after
    /// `reference` even when `reference` itself satisfies the rule.
    public func nextOccurrence(
        onOrAfter reference: Date,
        cadenceInterval: TimeInterval,
        inclusive: Bool = true,
        calendar: Calendar = .current
    ) -> Date {
        switch rule {
        case .weekday(let iso):
            return nextWeekday(iso: iso, reference: reference, inclusive: inclusive, calendar: calendar)
        case .dayOfMonth(let day):
            return nextDayOfMonth(day: day, reference: reference, inclusive: inclusive, calendar: calendar)
        case .fixedDate(let y, let m, let d):
            return nextFromFixed(year: y, month: m, day: d,
                                 reference: reference,
                                 cadenceInterval: cadenceInterval,
                                 inclusive: inclusive,
                                 calendar: calendar)
        }
    }

    private func applyTime(to date: Date, in calendar: Calendar) -> Date {
        let tod = timeOfDay ?? (0, 0)
        var c = calendar.dateComponents([.year, .month, .day], from: date)
        c.hour = tod.hour
        c.minute = tod.minute
        c.second = 0
        return calendar.date(from: c) ?? date
    }

    private func nextWeekday(iso: Int, reference: Date, inclusive: Bool, calendar: Calendar) -> Date {
        // Foundation Calendar.weekday: Sunday=1..Saturday=7.
        // Convert ISO (Mon=1..Sun=7) to Foundation: Sun=1, Mon=2, …
        let target = (iso == 7) ? 1 : iso + 1
        var candidate = applyTime(to: reference, in: calendar)
        var iterations = 0
        while iterations < 8 {
            let weekday = calendar.component(.weekday, from: candidate)
            let dueOK = inclusive
                ? candidate >= reference
                : candidate > reference
            if weekday == target && dueOK {
                return candidate
            }
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            candidate = applyTime(to: candidate, in: calendar)
            iterations += 1
        }
        return candidate
    }

    private func nextDayOfMonth(day: Int, reference: Date, inclusive: Bool, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: reference)
        for monthOffset in 0..<13 {
            guard let monthStart = calendar.date(from: comps),
                  let target = calendar.date(byAdding: .month, value: monthOffset, to: monthStart)
            else { continue }
            let range = calendar.range(of: .day, in: .month, for: target) ?? 1..<2
            let lastDay = range.upperBound - 1
            let clamped = min(day, lastDay)
            var c = calendar.dateComponents([.year, .month], from: target)
            c.day = clamped
            guard let candidateDate = calendar.date(from: c) else { continue }
            let candidate = applyTime(to: candidateDate, in: calendar)
            let dueOK = inclusive ? candidate >= reference : candidate > reference
            if dueOK { return candidate }
        }
        return reference
    }

    private func nextFromFixed(
        year: Int, month: Int, day: Int,
        reference: Date,
        cadenceInterval: TimeInterval,
        inclusive: Bool,
        calendar: Calendar
    ) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        guard let baseDate = calendar.date(from: c) else { return reference }
        var candidate = applyTime(to: baseDate, in: calendar)
        guard cadenceInterval > 0 else { return candidate }
        // Walk forward by one interval at a time. Using addingTimeInterval
        // is approximate (months/years drift by a few hours per cycle)
        // but matches how Cadence.approximateInterval is used elsewhere.
        var iterations = 0
        while iterations < 10_000 {
            let dueOK = inclusive ? candidate >= reference : candidate > reference
            if dueOK { return candidate }
            candidate = candidate.addingTimeInterval(cadenceInterval)
            iterations += 1
        }
        return candidate
    }
}
