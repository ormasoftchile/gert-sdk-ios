import Foundation

#if os(iOS)
import CoreLocation

// LocationHandler implements `location.read` using CoreLocation. It
// asks for when-in-use permission on first use, requests a single
// fix, and returns a flat dictionary of lat/lon/accuracy/timestamp.
//
// One-shot semantics fit how runbooks use location: as a check-in or
// proof-of-presence at the start of a step, not a continuous stream.
public final class LocationHandler: NSObject, GertToolHandler, CLLocationManagerDelegate, @unchecked Sendable {
    public let toolName = "location.read"

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private let queue = DispatchQueue(label: "gert.location")

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    public func isAvailable() async -> Bool {
        CLLocationManager.locationServicesEnabled()
    }

    public func execute(action: String, args: [String: Any]) async throws -> [String: Any] {
        let loc = try await requestSingleFix()
        return [
            "lat":          loc.coordinate.latitude,
            "lon":          loc.coordinate.longitude,
            "accuracy_m":   loc.horizontalAccuracy,
            "altitude_m":   loc.altitude,
            "captured_at":  ISO8601DateFormatter().string(from: loc.timestamp),
        ]
    }

    private func requestSingleFix() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CLLocation, Error>) in
            queue.async { [weak self] in
                guard let self else { return }
                self.continuation = cont
                let status = self.manager.authorizationStatus
                switch status {
                case .notDetermined:
                    self.manager.requestWhenInUseAuthorization()
                case .denied, .restricted:
                    self.finish(.failure(LocationError.permissionDenied))
                    return
                default:
                    break
                }
                self.manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        switch result {
        case .success(let loc): cont.resume(returning: loc)
        case .failure(let err): cont.resume(throwing: err)
        }
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        finish(.success(loc))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .denied, .restricted:
            finish(.failure(LocationError.permissionDenied))
        case .authorizedWhenInUse, .authorizedAlways:
            // Trigger the fix now that we have permission.
            manager.requestLocation()
        default:
            break
        }
    }
}

public enum LocationError: Error, LocalizedError {
    case permissionDenied
    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Location permission denied"
        }
    }
}
#endif
