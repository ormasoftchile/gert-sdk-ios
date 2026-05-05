import Foundation

#if os(iOS)
import UserNotifications

// NotificationsHandler implements `notifications.local` by scheduling
// a UNCalendarNotificationTrigger or UNTimeIntervalNotificationTrigger
// based on the runbook args. Permission is requested on first use.
//
// Args:
//   action: "schedule" | "cancel"
//   id (cancel): notification id to cancel
//   title (schedule): banner title
//   body  (schedule): banner body
//   at    (schedule): ISO-8601 datetime to fire at
//   in_seconds (schedule): alternative — fire N seconds from now
public final class NotificationsHandler: GertToolHandler, @unchecked Sendable {
    public let toolName = "notifications.local"

    public init() {}

    public func isAvailable() async -> Bool { true }

    public func execute(action: String, args: [String: Any]) async throws -> [String: Any] {
        switch action {
        case "schedule": return try await schedule(args: args)
        case "cancel":   return try await cancel(args: args)
        default:         throw NotificationsError.unsupportedAction(action)
        }
    }

    private func schedule(args: [String: Any]) async throws -> [String: Any] {
        try await ensurePermission()

        let title = args["title"] as? String ?? "Reminder"
        let body  = args["body"] as? String ?? ""

        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        let trigger: UNNotificationTrigger = try buildTrigger(args: args)
        let id = (args["id"] as? String) ?? UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try await UNUserNotificationCenter.current().add(request)
        return [
            "notification_id": id,
            "scheduled_at":    ISO8601DateFormatter().string(from: Date()),
        ]
    }

    private func cancel(args: [String: Any]) async throws -> [String: Any] {
        guard let id = args["id"] as? String else {
            throw NotificationsError.missingArgument("id")
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        return ["cancelled_id": id]
    }

    private func buildTrigger(args: [String: Any]) throws -> UNNotificationTrigger {
        if let isoString = args["at"] as? String {
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: isoString) else {
                throw NotificationsError.invalidDate(isoString)
            }
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date
            )
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        }
        if let seconds = args["in_seconds"] as? Double, seconds > 0 {
            return UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        }
        if let seconds = args["in_seconds"] as? Int, seconds > 0 {
            return UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        }
        throw NotificationsError.missingArgument("at or in_seconds")
    }

    private func ensurePermission() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            throw NotificationsError.permissionDenied
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted { throw NotificationsError.permissionDenied }
        @unknown default:
            throw NotificationsError.permissionDenied
        }
    }
}

public enum NotificationsError: Error, LocalizedError {
    case permissionDenied
    case unsupportedAction(String)
    case missingArgument(String)
    case invalidDate(String)
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:        return "Notifications permission denied"
        case .unsupportedAction(let a): return "Unsupported notifications action: \(a)"
        case .missingArgument(let a):   return "Missing argument: \(a)"
        case .invalidDate(let s):       return "Invalid ISO-8601 date: \(s)"
        }
    }
}
#endif
