import Foundation

// Cadence is a parsed runbook cadence string of the form "<N><unit>"
// where unit is one of d (day), w (week), M (month), y (year).
// Mirrors the gert-domain-home `model.Duration` so the SDK speaks the
// same vocabulary as the compiler.
public struct Cadence: Equatable, Sendable, Codable {
    public enum Unit: String, Sendable, Codable {
        case day   = "d"
        case week  = "w"
        case month = "M"
        case year  = "y"
    }

    public let value: Int
    public let unit: Unit

    public init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }

    /// Approximate length in seconds. Months and years use the same
    /// 30-day/365-day approximations as the compiler's ToDays().
    public var approximateInterval: TimeInterval {
        switch unit {
        case .day:   return TimeInterval(value) * 86_400
        case .week:  return TimeInterval(value) * 7 * 86_400
        case .month: return TimeInterval(value) * 30 * 86_400
        case .year:  return TimeInterval(value) * 365 * 86_400
        }
    }

    public var description: String { "\(value)\(unit.rawValue)" }
}

public enum CadenceParseError: Error, LocalizedError {
    case empty
    case invalidValue(String)
    case invalidUnit(String)
    public var errorDescription: String? {
        switch self {
        case .empty:               return "Empty cadence"
        case .invalidValue(let s): return "Invalid cadence value: '\(s)'"
        case .invalidUnit(let s):  return "Invalid cadence unit: '\(s)' (expected d, w, M, or y)"
        }
    }
}

public extension Cadence {
    static func parse(_ raw: String) throws -> Cadence {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { throw CadenceParseError.empty }

        // Split on the first non-digit character.
        let split = trimmed.firstIndex(where: { !$0.isNumber }) ?? trimmed.endIndex
        guard split != trimmed.startIndex, split != trimmed.endIndex else {
            throw CadenceParseError.invalidValue(trimmed)
        }
        let valueStr = String(trimmed[..<split])
        let unitStr  = String(trimmed[split...])

        guard let value = Int(valueStr) else {
            throw CadenceParseError.invalidValue(valueStr)
        }
        guard let unit = Unit(rawValue: unitStr) else {
            throw CadenceParseError.invalidUnit(unitStr)
        }
        return Cadence(value: value, unit: unit)
    }
}
