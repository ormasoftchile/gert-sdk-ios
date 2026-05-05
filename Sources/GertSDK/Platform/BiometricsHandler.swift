import Foundation

#if os(iOS)
import LocalAuthentication

// BiometricsHandler implements `biometrics.confirm` — a one-shot
// Face ID / Touch ID prompt used to sign off on a routine ("I am the
// person who completed this chore"). Falls back to device passcode
// when biometrics aren't enrolled, unless `args.passcode_fallback`
// is explicitly false.
//
// Args:
//   reason: human-readable string shown in the prompt
//   passcode_fallback: bool (default true)
public final class BiometricsHandler: GertToolHandler, @unchecked Sendable {
    public let toolName = "biometrics.confirm"

    public init() {}

    public func isAvailable() async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    public func execute(action: String, args: [String: Any]) async throws -> [String: Any] {
        let reason = (args["reason"] as? String) ?? "Confirm your identity"
        let allowPasscode = (args["passcode_fallback"] as? Bool) ?? true
        let policy: LAPolicy = allowPasscode
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(policy, error: &err) else {
            throw BiometricsError.unavailable(err?.localizedDescription ?? "policy not available")
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ctx.evaluatePolicy(policy, localizedReason: reason) { success, evalErr in
                if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: evalErr ?? BiometricsError.cancelled)
                }
            }
        }

        return [
            "confirmed":    true,
            "method":       methodName(for: ctx.biometryType),
            "confirmed_at": ISO8601DateFormatter().string(from: Date()),
        ]
    }

    private func methodName(for type: LABiometryType) -> String {
        switch type {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none:    return "passcode"
        @unknown default: return "unknown"
        }
    }
}

public enum BiometricsError: Error, LocalizedError {
    case unavailable(String)
    case cancelled
    public var errorDescription: String? {
        switch self {
        case .unavailable(let d): return "Biometrics unavailable: \(d)"
        case .cancelled:          return "Biometrics confirmation cancelled"
        }
    }
}
#endif
