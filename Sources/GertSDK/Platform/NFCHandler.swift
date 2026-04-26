import Foundation
import CoreNFC

/// NFC capability handler for iOS
public class NFCHandler: GertToolHandler {
    public var capability: String {
        Capability.nfc.rawValue
    }
    
    public func execute(inputs: [String: Any]) async throws -> [String: Any] {
        fatalError("Not yet implemented")
    }
    
    public func checkAvailability() async -> Bool {
        // Check if NFC is available on this device
        if #available(iOS 13.0, *) {
            return NFCNDEFReaderSession.readingAvailable
        } else {
            return false
        }
    }
}
