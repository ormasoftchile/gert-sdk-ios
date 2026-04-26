import Foundation
import AVFoundation
import UIKit

/// Camera capability handler for iOS
public class CameraHandler: GertToolHandler {
    public var capability: String {
        Capability.camera.rawValue
    }
    
    public func execute(inputs: [String: Any]) async throws -> [String: Any] {
        fatalError("Not yet implemented")
    }
    
    public func checkAvailability() async -> Bool {
        // Check if camera is available and authorized
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return false
        }
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            // Could request permission, but for availability check just return false
            return false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
