import Foundation

/// RunEvent represents a trace event in the JSONL stream.
public enum RunEvent: Codable {
    case runStarted(RunStartedEvent)
    case stepStarted(StepStartedEvent)
    case stepCompleted(StepCompletedEvent)
    case stepFailed(StepFailedEvent)
    case runCompleted(RunCompletedEvent)
    case runFailed(RunFailedEvent)
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    enum EventType: String, Codable {
        case runStarted = "run/started"
        case stepStarted = "step/started"
        case stepCompleted = "step/completed"
        case stepFailed = "step/failed"
        case runCompleted = "run/completed"
        case runFailed = "run/failed"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)
        
        switch type {
        case .runStarted:
            self = .runStarted(try RunStartedEvent(from: decoder))
        case .stepStarted:
            self = .stepStarted(try StepStartedEvent(from: decoder))
        case .stepCompleted:
            self = .stepCompleted(try StepCompletedEvent(from: decoder))
        case .stepFailed:
            self = .stepFailed(try StepFailedEvent(from: decoder))
        case .runCompleted:
            self = .runCompleted(try RunCompletedEvent(from: decoder))
        case .runFailed:
            self = .runFailed(try RunFailedEvent(from: decoder))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .runStarted(let event):
            try event.encode(to: encoder)
        case .stepStarted(let event):
            try event.encode(to: encoder)
        case .stepCompleted(let event):
            try event.encode(to: encoder)
        case .stepFailed(let event):
            try event.encode(to: encoder)
        case .runCompleted(let event):
            try event.encode(to: encoder)
        case .runFailed(let event):
            try event.encode(to: encoder)
        }
    }
}

public struct RunStartedEvent: Codable {
    public let type = "run/started"
    public let runID: String
    public let kitName: String
    public let runbookName: String
    public let actor: String
    public let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case runID = "run_id"
        case kitName = "kit_name"
        case runbookName = "runbook_name"
        case actor, timestamp
    }
}

public struct StepStartedEvent: Codable {
    public let type = "step/started"
    public let runID: String
    public let stepID: String
    public let stepName: String
    public let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case runID = "run_id"
        case stepID = "step_id"
        case stepName = "step_name"
        case timestamp
    }
}

public struct StepCompletedEvent: Codable {
    public let type = "step/completed"
    public let runID: String
    public let stepID: String
    public let outputs: [String: String]?
    public let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case runID = "run_id"
        case stepID = "step_id"
        case outputs, timestamp
    }
}

public struct StepFailedEvent: Codable {
    public let type = "step/failed"
    public let runID: String
    public let stepID: String
    public let error: String
    public let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case runID = "run_id"
        case stepID = "step_id"
        case error, timestamp
    }
}

public struct RunCompletedEvent: Codable {
    public let type = "run/completed"
    public let runID: String
    public let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case runID = "run_id"
        case timestamp
    }
}

public struct RunFailedEvent: Codable {
    public let type = "run/failed"
    public let runID: String
    public let error: String
    public let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case runID = "run_id"
        case error, timestamp
    }
}
