import Foundation
import UserNotifications

/// Notifications capability handler for iOS
public class NotificationsHandler: GertToolHandler {
    public var capability: String {
        Capability.notifications.rawValue
    }
    
    public func execute(inputs: [String: Any]) async throws -> [String: Any] {
        fatalError("Not yet implemented")
    }
    
    public func checkAvailability() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied, .notDetermined:
            return false
        case .ephemeral:
            return true
        @unknown default:
            return false
        }
    }
}
