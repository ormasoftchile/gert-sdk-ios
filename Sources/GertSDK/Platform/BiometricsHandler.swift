import Foundation
import LocalAuthentication

/// Biometrics capability handler for iOS (Face ID / Touch ID)
public class BiometricsHandler: GertToolHandler {
    public var capability: String {
        Capability.biometrics.rawValue
    }
    
    public func execute(inputs: [String: Any]) async throws -> [String: Any] {
        fatalError("Not yet implemented")
    }
    
    public func checkAvailability() async -> Bool {
        let context = LAContext()
        var error: NSError?
        
        // Check if biometric authentication is available
        let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        
        return canEvaluate
    }
}
