import Foundation
import CoreLocation

/// Location capability handler for iOS
public class LocationHandler: GertToolHandler {
    public var capability: String {
        Capability.location.rawValue
    }
    
    private let locationManager = CLLocationManager()
    
    public func execute(inputs: [String: Any]) async throws -> [String: Any] {
        fatalError("Not yet implemented")
    }
    
    public func checkAvailability() async -> Bool {
        // Check if location services are enabled
        guard CLLocationManager.locationServicesEnabled() else {
            return false
        }
        
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined:
            return false
        case .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }
}
