import Foundation

// Delegation describes a window during which routines/zones are
// handed off to another person (e.g. a neighbour while the owner is
// travelling). It is decoded from the `Delegations` array in a
// property.json file produced by the gert engine.
//
// Property.json uses Pascal-case keys because it's emitted via Go's
// default json encoding. The keys here are declared via CodingKeys
// so Swift call sites can stay camelCase.
public struct Delegation: Codable, Sendable, Equatable {
    public let delegate: Delegate
    public let active: ActiveWindow
    public let assigns: [Assignment]
    public let permissions: Permissions
    public let notifications: DelegationNotifications?

    public init(delegate: Delegate,
                active: ActiveWindow,
                assigns: [Assignment],
                permissions: Permissions,
                notifications: DelegationNotifications? = nil) {
        self.delegate = delegate
        self.active = active
        self.assigns = assigns
        self.permissions = permissions
        self.notifications = notifications
    }

    enum CodingKeys: String, CodingKey {
        case delegate     = "Delegate"
        case active       = "Active"
        case assigns      = "Assigns"
        case permissions  = "Permissions"
        case notifications = "Notifications"
    }

    public struct Delegate: Codable, Sendable, Equatable {
        public let name: String
        public let contact: String?
        public let email: String?

        public init(name: String, contact: String? = nil, email: String? = nil) {
            self.name = name
            self.contact = contact
            self.email = email
        }

        enum CodingKeys: String, CodingKey {
            case name    = "Name"
            case contact = "Contact"
            case email   = "Email"
        }
    }

    public struct ActiveWindow: Codable, Sendable, Equatable {
        /// ISO-8601 date (YYYY-MM-DD), inclusive.
        public let from: String
        /// ISO-8601 date (YYYY-MM-DD), inclusive.
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }

        enum CodingKeys: String, CodingKey {
            case from = "From"
            case to   = "To"
        }
    }

    public struct Assignment: Codable, Sendable, Equatable {
        /// Routine id (without kit prefix), e.g. "water_plants".
        public let routine: String
        /// Zone id, e.g. "pool".
        public let zone: String

        public init(routine: String, zone: String) {
            self.routine = routine
            self.zone = zone
        }

        enum CodingKeys: String, CodingKey {
            case routine = "Routine"
            case zone    = "Zone"
        }
    }

    public struct Permissions: Codable, Sendable, Equatable {
        public let canReportIncidents: Bool
        public let canModifyRoutines: Bool
        public let canViewHistory: Bool

        public init(canReportIncidents: Bool,
                    canModifyRoutines: Bool,
                    canViewHistory: Bool) {
            self.canReportIncidents = canReportIncidents
            self.canModifyRoutines = canModifyRoutines
            self.canViewHistory = canViewHistory
        }

        enum CodingKeys: String, CodingKey {
            case canReportIncidents = "CanReportIncidents"
            case canModifyRoutines  = "CanModifyRoutines"
            case canViewHistory     = "CanViewHistory"
        }
    }

    public struct DelegationNotifications: Codable, Sendable, Equatable {
        public let remindDelegateHoursBefore: Int?
        public let notifyOwnerOnCompletion: Bool?
        public let notifyOwnerIfOverdue: Bool?

        public init(remindDelegateHoursBefore: Int? = nil,
                    notifyOwnerOnCompletion: Bool? = nil,
                    notifyOwnerIfOverdue: Bool? = nil) {
            self.remindDelegateHoursBefore = remindDelegateHoursBefore
            self.notifyOwnerOnCompletion = notifyOwnerOnCompletion
            self.notifyOwnerIfOverdue = notifyOwnerIfOverdue
        }

        enum CodingKeys: String, CodingKey {
            case remindDelegateHoursBefore = "RemindDelegateHoursBefore"
            case notifyOwnerOnCompletion   = "NotifyOwnerOnCompletion"
            case notifyOwnerIfOverdue      = "NotifyOwnerIfOverdue"
        }
    }
}

// PropertyDocument is the minimal shape of property.json the SDK
// cares about. The file contains many other fields (zones, assets,
// inventory) that the SDK ignores today; adding more is a matter of
// extending this struct without touching the loader.
struct PropertyDocument: Decodable {
    let delegations: [Delegation]?

    enum CodingKeys: String, CodingKey {
        case delegations = "Delegations"
    }
}

public extension Delegation {

    /// Returns true if `date` falls within `[active.from, active.to]`
    /// inclusive. Comparison is done in the calendar's current time
    /// zone so a delegation valid "until 2026-05-10" stays active for
    /// the entirety of the 10th.
    func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        guard let from = Self.parseDate(active.from, calendar: calendar),
              let to   = Self.parseDate(active.to,   calendar: calendar) else {
            return false
        }
        let day = calendar.startOfDay(for: date)
        return day >= from && day <= to
    }

    /// Returns true if the delegation covers the given routine id
    /// (which may be either kit-scoped "casa-santiago.routine.foo" or
    /// the bare "foo" — both are accepted) or any zone the routine
    /// lives in.
    func covers(routineID: String, zone: String?) -> Bool {
        let bare = routineID.split(separator: ".").last.map(String.init) ?? routineID
        for a in assigns {
            if !a.routine.isEmpty && (a.routine == bare || a.routine == routineID) {
                return true
            }
            if !a.zone.isEmpty, let zone, a.zone == zone {
                return true
            }
        }
        return false
    }

    /// Returns true when this delegation's active window intersects
    /// `other`'s AND at least one assignment (routine or zone) is
    /// shared between them. Used by the wizard's conflict guard so
    /// the owner can see when they're double-booking the same work.
    func overlaps(_ other: Delegation, calendar: Calendar = .current) -> Bool {
        guard let aFrom = Self.parseDate(active.from, calendar: calendar),
              let aTo   = Self.parseDate(active.to,   calendar: calendar),
              let bFrom = Self.parseDate(other.active.from, calendar: calendar),
              let bTo   = Self.parseDate(other.active.to,   calendar: calendar) else {
            return false
        }
        // Date windows are inclusive on both ends.
        guard aFrom <= bTo && bFrom <= aTo else { return false }

        let myRoutines = Set(assigns.map(\.routine).filter { !$0.isEmpty })
        let myZones    = Set(assigns.map(\.zone).filter    { !$0.isEmpty })
        for a in other.assigns {
            if !a.routine.isEmpty && myRoutines.contains(a.routine) { return true }
            if !a.zone.isEmpty    && myZones.contains(a.zone)       { return true }
        }
        return false
    }

    private static func parseDate(_ s: String, calendar: Calendar) -> Date? {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
