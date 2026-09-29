/// User-tunable engine and notification settings (DESIGN.md §3.3). Truth, synced.
public struct Settings: Codable, Sendable, Hashable {
    /// Max questions presented per session (§4.4).
    public var sessionBudget: Int
    /// 0...23; see `DayCalendar`.
    public var dayStartHour: Int
    /// 0...1 per habit-day, only when the natural interval is > 7 days (§4.2 rule 5).
    public var spotCheckRate: Double
    /// Posterior sd above which a habit is due (§4.2 rule 1). Beta sd never exceeds 0.5.
    public var uncertaintyThreshold: Double
    /// Evidence decay per elapsed day (§4.1); 0.92 → half-life ≈ 8 days.
    public var decayPerDay: Double
    /// Never go longer than this without asking (§4.2 rule 3).
    public var maxIntervalDays: Int
    public var notifications: NotificationSettings

    public static let `default` = Settings(
        sessionBudget: 3,
        dayStartHour: DayCalendar.defaultDayStartHour,
        spotCheckRate: 0.05,
        uncertaintyThreshold: 0.15,
        decayPerDay: 0.92,
        maxIntervalDays: 14,
        notifications: .default
    )

    public enum ValidationError: Error, Equatable {
        case sessionBudgetOutOfRange(Int)
        case dayStartHourOutOfRange(Int)
        case spotCheckRateOutOfRange(Double)
        case uncertaintyThresholdOutOfRange(Double)
        case decayPerDayOutOfRange(Double)
        case maxIntervalDaysOutOfRange(Int)
    }

    public init(
        sessionBudget: Int,
        dayStartHour: Int,
        spotCheckRate: Double,
        uncertaintyThreshold: Double,
        decayPerDay: Double,
        maxIntervalDays: Int,
        notifications: NotificationSettings
    ) {
        self.sessionBudget = sessionBudget
        self.dayStartHour = dayStartHour
        self.spotCheckRate = spotCheckRate
        self.uncertaintyThreshold = uncertaintyThreshold
        self.decayPerDay = decayPerDay
        self.maxIntervalDays = maxIntervalDays
        self.notifications = notifications
    }

    public func validate() throws {
        guard sessionBudget >= 1 else { throw ValidationError.sessionBudgetOutOfRange(sessionBudget) }
        guard (0 ... 23).contains(dayStartHour) else { throw ValidationError.dayStartHourOutOfRange(dayStartHour) }
        guard (0 ... 1).contains(spotCheckRate) else { throw ValidationError.spotCheckRateOutOfRange(spotCheckRate) }
        guard uncertaintyThreshold > 0, uncertaintyThreshold < 0.5 else {
            throw ValidationError.uncertaintyThresholdOutOfRange(uncertaintyThreshold)
        }
        guard decayPerDay > 0, decayPerDay <= 1 else { throw ValidationError.decayPerDayOutOfRange(decayPerDay) }
        guard maxIntervalDays >= 1 else { throw ValidationError.maxIntervalDaysOutOfRange(maxIntervalDays) }
        try notifications.validate()
    }
}

public struct NotificationSettings: Codable, Sendable, Hashable {
    public enum Cadence: Codable, Sendable, Hashable {
        case timesPerDay([TimeOfDay])
        case everyNDays(Int, time: TimeOfDay)
    }

    public var cadence: Cadence
    public var quietHours: QuietHours?
    /// "You haven't reviewed in N days" (§4.6).
    public var nudgeAfterSilentDays: Int?
    public var onlyWhenQuestionsDue: Bool

    public static let `default` = NotificationSettings(
        cadence: .timesPerDay([TimeOfDay(uncheckedHour: 20, minute: 0)]),
        quietHours: nil,
        nudgeAfterSilentDays: nil,
        onlyWhenQuestionsDue: true
    )

    public enum ValidationError: Error, Equatable {
        case noTimes
        case everyNDaysNotPositive(Int)
        case nudgeNotPositive(Int)
    }

    public init(cadence: Cadence, quietHours: QuietHours?, nudgeAfterSilentDays: Int?, onlyWhenQuestionsDue: Bool) {
        self.cadence = cadence
        self.quietHours = quietHours
        self.nudgeAfterSilentDays = nudgeAfterSilentDays
        self.onlyWhenQuestionsDue = onlyWhenQuestionsDue
    }

    public func validate() throws {
        switch cadence {
        case let .timesPerDay(times):
            guard !times.isEmpty else { throw ValidationError.noTimes }
        case let .everyNDays(days, _):
            guard days >= 1 else { throw ValidationError.everyNDaysNotPositive(days) }
        }
        if let nudgeAfterSilentDays, nudgeAfterSilentDays < 1 {
            throw ValidationError.nudgeNotPositive(nudgeAfterSilentDays)
        }
    }
}

/// Local wall-clock time. Not `DateComponents`, which carries calendar and time zone baggage.
public struct TimeOfDay: Codable, Sendable, Hashable, Comparable {
    public let hour: Int
    public let minute: Int

    public enum ValidationError: Error, Equatable {
        case outOfRange(hour: Int, minute: Int)
    }

    public init(hour: Int, minute: Int) throws {
        guard (0 ... 23).contains(hour), (0 ... 59).contains(minute) else {
            throw ValidationError.outOfRange(hour: hour, minute: minute)
        }
        self.init(uncheckedHour: hour, minute: minute)
    }

    /// `minutes` after midnight, wrapped into one day.
    public init(minutesSinceMidnight minutes: Int) {
        let wrapped = (minutes % 1440 + 1440) % 1440
        self.init(uncheckedHour: wrapped / 60, minute: wrapped % 60)
    }

    /// For compile-time constants only.
    init(uncheckedHour hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hour: container.decode(Int.self, forKey: .hour),
            minute: container.decode(Int.self, forKey: .minute)
        )
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

/// Hours during which no notification fires: `[startHour, endHour)`, wrapping past midnight when
/// `startHour > endHour` (22 → 7 is 22:00–06:59). `ClosedRange<Int>` can't express the wrap.
public struct QuietHours: Codable, Sendable, Hashable {
    public let startHour: Int
    public let endHour: Int

    public enum ValidationError: Error, Equatable {
        case hourOutOfRange(Int)
        case empty
    }

    public init(startHour: Int, endHour: Int) throws {
        for hour in [startHour, endHour] where !(0 ... 23).contains(hour) {
            throw ValidationError.hourOutOfRange(hour)
        }
        guard startHour != endHour else { throw ValidationError.empty }
        self.startHour = startHour
        self.endHour = endHour
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            startHour: container.decode(Int.self, forKey: .startHour),
            endHour: container.decode(Int.self, forKey: .endHour)
        )
    }

    public func contains(hour: Int) -> Bool {
        startHour < endHour
            ? (startHour ..< endHour).contains(hour)
            : hour >= startHour || hour < endHour
    }
}
