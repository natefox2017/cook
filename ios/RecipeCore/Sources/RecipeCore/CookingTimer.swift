// Developer: gengyun
// Purpose: Defines deadline-based cooking timer state and transitions.

import Foundation

/// Uses an absolute deadline, so backgrounding and delayed UI ticks do not add drift.
public struct CookingTimer: Codable, Equatable, Sendable {
    public private(set) var durationSeconds: Int
    public private(set) var remainingSeconds: Int
    public private(set) var deadline: Date?

    public init(durationSeconds: Int) {
        self.durationSeconds = max(0, durationSeconds)
        self.remainingSeconds = max(0, durationSeconds)
        self.deadline = nil
    }

    /// An active deadline can have zero remaining time; the caller handles completion.
    public var isRunning: Bool { deadline != nil }

    public mutating func start(at date: Date = .now) {
        guard durationSeconds > 0 else { return }
        if deadline != nil {
            guard remaining(at: date) == 0 else { return }
            remainingSeconds = durationSeconds
        }
        if remainingSeconds == 0 { remainingSeconds = durationSeconds }
        deadline = date.addingTimeInterval(TimeInterval(remainingSeconds))
    }

    public mutating func pause(at date: Date = .now) {
        remainingSeconds = remaining(at: date)
        deadline = nil
    }

    public mutating func reset() {
        remainingSeconds = durationSeconds
        deadline = nil
    }

    public func remaining(at date: Date = .now) -> Int {
        let limit = max(0, min(durationSeconds, remainingSeconds))
        guard let deadline else { return limit }
        let interval = deadline.timeIntervalSince(date)
        guard interval > 0 else { return 0 }
        // Check before converting to Int, including an extreme restored duration.
        guard interval < Double(limit) else { return limit }
        return max(0, Int(ceil(interval)))
    }
}

/// A pure deadline-based warning plan; no foreground timer tick is required.
public struct CookingReminderPlan: Equatable, Sendable {
    public let deadline: Date
    public let earlyWarningAt: Date?

    public init?(timer: CookingTimer, warningSeconds: Int, now: Date = .now) {
        guard let deadline = timer.deadline, timer.remaining(at: now) > 0 else {
            return nil
        }
        self.deadline = deadline
        if warningSeconds > 0,
            deadline.timeIntervalSince(now) > Double(warningSeconds + 1)
        {
            earlyWarningAt = deadline.addingTimeInterval(-TimeInterval(warningSeconds))
        } else {
            earlyWarningAt = nil
        }
    }
}

/// Only exact short commands can move cooking progress; free-form speech is ignored.
public enum CookingVoiceCommand: String, Codable, Equatable, Sendable {
    case next
    case previous
    case repeatStep
    case stop
}

public enum CookingVoiceCommandParser {
    public static func parse(_ transcript: String) -> CookingVoiceCommand? {
        let words = transcript.lowercased().split { !$0.isLetter && !$0.isNumber }
        let command = words.joined(separator: " ")
        switch command {
        case "next", "next step":
            return .next
        case "previous", "previous step", "back", "go back", "privious":
            return .previous
        case "repeat", "repeat step", "read step":
            return .repeatStep
        case "stop listening":
            return .stop
        default:
            return nil
        }
    }
}
