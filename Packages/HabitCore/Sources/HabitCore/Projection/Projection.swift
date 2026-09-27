import Foundation

/// A habit's model as of the end of a day (§4.7 step 2), for the "ask interval over time" chart.
public struct ModelPoint: Codable, Sendable, Hashable {
    public let day: DayKey
    public let mean: Double
    public let standardDeviation: Double
    public let intervalDays: Int

    public init(day: DayKey, mean: Double, standardDeviation: Double, intervalDays: Int) {
        self.day = day
        self.mean = mean
        self.standardDeviation = standardDeviation
        self.intervalDays = intervalDays
    }
}

/// The derived, rebuildable state (DESIGN.md §3.2).
public struct Projected: Sendable, Hashable {
    /// One record per habit per day from `createdDay` through today.
    public let records: DayRecords
    /// Scheduler state as of today, for every habit.
    public let states: [UUID: SchedulerState]
    /// One point per habit per day, aligned with `records`.
    public let series: [UUID: [ModelPoint]]
}

/// Habit-keyed maps encode as JSON objects keyed by UUID string, so `.sortedKeys` output is byte-identical
/// across runs (§4.7 step 3); `[UUID: V]` would encode as an array in per-instance hash order.
extension Projected: Codable {
    private enum CodingKeys: String, CodingKey {
        case records, states, series
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decode<Value: Decodable>(_ key: CodingKeys) throws -> [UUID: Value] {
            let byString = try container.decode([String: Value].self, forKey: key)
            return try Dictionary(uniqueKeysWithValues: byString.map { string, value in
                guard let id = UUID(uuidString: string) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: key, in: container, debugDescription: "Invalid habit ID '\(string)'"
                    )
                }
                return (id, value)
            })
        }
        try self.init(records: decode(.records), states: decode(.states), series: decode(.series))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        func byString<Value>(_ map: [UUID: Value]) -> [String: Value] {
            Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, $0.value) })
        }
        try container.encode(byString(records), forKey: .records)
        try container.encode(byString(states), forKey: .states)
        try container.encode(byString(series), forKey: .series)
    }
}

/// Rebuilds day records and scheduler state from truth (DESIGN.md §4.7). Deterministic: the same truth and
/// day produce identical output.
public enum Projection {
    public static func rebuild(_ truth: Truth, clock: some Clock) throws -> Projected {
        try truth.validate()
        let today = clock.today()
        let sorted = try Dependencies.topologicallySorted(truth.habits)
        let byID = try Dependencies.index(sorted)
        let answers = Dictionary(grouping: truth.answers, by: \.habitID).mapValues { answers in
            answers.sorted { ($0.answeredAt, $0.id.uuidString) < ($1.answeredAt, $1.id.uuidString) }
        }
        let health = Dictionary(grouping: truth.healthObservations, by: \.habitID).mapValues { Set($0.map(\.day)) }

        var unavailable: [DayKey: [UUID: Unavailability]] = [:]
        if let first = sorted.map(\.createdDay).min(), first <= today {
            for day in first ... today {
                unavailable[day] = try Pauses.unavailable(on: day, sorted: sorted, byID: byID, pauses: truth.pauses)
            }
        }

        var records: DayRecords = [:]
        var states: [UUID: SchedulerState] = [:]
        var series: [UUID: [ModelPoint]] = [:]
        for habit in sorted {
            let projector = try HabitProjector(
                habit: habit,
                parentIDs: Dependencies.activeGateParentIDs(of: habit, in: byID),
                answers: answers[habit.id] ?? [],
                healthDays: health[habit.id] ?? [],
                settings: truth.settings,
                today: today
            )
            let output = try projector.run(unavailable: unavailable, parentRecords: records)
            records[habit.id] = output.records
            states[habit.id] = output.state
            series[habit.id] = output.series
        }
        return Projected(records: records, states: states, series: series)
    }
}

/// Replays one habit day by day (§4.7). Parents must already be projected.
private struct HabitProjector {
    let habit: Habit
    let parentIDs: [UUID]
    /// Sorted by `answeredAt`, then ID; later answers about a day override earlier ones.
    let answers: [Answer]
    let healthDays: Set<DayKey>
    let settings: Settings
    let today: DayKey

    struct Output {
        let records: [DayKey: DayRecord]
        let state: SchedulerState
        let series: [ModelPoint]
    }

    /// What answers say about one day. `value` is nil for "Don't remember".
    private struct AnsweredDay {
        let value: Double?
        let source: DaySource
        let questionID: UUID
    }

    func run(
        unavailable: [DayKey: [UUID: Unavailability]],
        parentRecords: DayRecords
    ) throws -> Output {
        let answered = answeredDays(parentRecords: parentRecords)
        // Paused and blocked days count as covered too (below): questions never reach into a pause.
        var lastCovered = lastCoveredByEvidence
        var model = AdherenceModel.prior
        var records: [DayKey: DayRecord] = [:]
        var series: [ModelPoint] = []
        var wasUnavailable = false
        var reentry = false

        // `stride` is empty for a habit created after today; a range would trap.
        for day in stride(from: habit.createdDay, through: today, by: 1) {
            if let reason = unavailable[day]?[habit.id] {
                // Frozen: no decay, no evidence (§4.6).
                records[day] = DayRecord(
                    habitID: habit.id,
                    day: day,
                    value: 0,
                    source: reason.source,
                    confidence: 0
                )
                lastCovered = max(lastCovered ?? day, day)
                wasUnavailable = true
                reentry = false
            } else {
                if wasUnavailable {
                    reentry = !answers.contains { $0.covers.upperBound >= day }
                    wasUnavailable = false
                }
                try model.decay(days: 1, rate: settings.decayPerDay)
                let record = record(on: day, answered: answered[day], model: model, parentRecords: parentRecords)
                try model.observe(record)
                records[day] = record
            }
            try series.append(ModelPoint(
                day: day,
                mean: model.mean,
                standardDeviation: model.standardDeviation,
                intervalDays: interval(of: model)
            ))
        }
        let state = try SchedulerState(
            habitID: habit.id,
            alpha: model.alpha,
            beta: model.beta,
            lastCoveredDay: lastCovered,
            lastAskedDay: answers.map(\.covers.upperBound).max(),
            currentIntervalDays: interval(of: model),
            forcedReentryCheck: reentry
        )
        return Output(records: records, state: state, series: series)
    }

    /// Latest day covered by answers (not delays) or health observations, before counting pauses.
    private var lastCoveredByEvidence: DayKey? {
        let answered = answers.compactMap { answer -> DayKey? in
            if case .delayed = answer.value {
                return nil
            }
            return answer.covers.upperBound
        }
        return (answered + healthDays.filter { $0 <= today }).max()
    }

    /// §4.7 step 1 precedence after pauses: health, then answers, then the conditional exclusion (§4.5),
    /// then inference (§4.3).
    private func record(
        on day: DayKey,
        answered: AnsweredDay?,
        model: AdherenceModel,
        parentRecords: DayRecords
    ) -> DayRecord {
        if healthDays.contains(day) {
            return DayRecord(habitID: habit.id, day: day, value: 1, source: .health, confidence: 1)
        }
        if let answered {
            guard let value = answered.value else {
                return DayRecord(
                    habitID: habit.id, day: day, value: model.mean, source: .unknown, confidence: 0,
                    questionID: answered.questionID
                )
            }
            return DayRecord(
                habitID: habit.id, day: day, value: value, source: answered.source, confidence: 1,
                questionID: answered.questionID
            )
        }
        let parentNotDone = parentIDs.contains { parentID in
            guard let parent = parentRecords[parentID]?[day] else { return false }
            return parent.source == .observed && parent.value == 0
        }
        if parentNotDone {
            return DayRecord(
                habitID: habit.id, day: day, value: 0, source: .observed, confidence: 1,
                conditionalDenominatorExcluded: true
            )
        }
        let deviation = model.standardDeviation
        if deviation > settings.uncertaintyThreshold {
            return DayRecord(habitID: habit.id, day: day, value: model.mean, source: .unknown, confidence: 0)
        }
        return DayRecord(
            habitID: habit.id, day: day, value: model.mean, source: .inferred,
            confidence: min(1, max(0, 1 - 2 * deviation))
        )
    }

    /// Day values stated by answers. `count` answers are spread evenly (O1): `done / total` on each day of
    /// `covers`, or for a gated habit on each known parent-done day (the days the question was about).
    private func answeredDays(parentRecords: DayRecords) -> [DayKey: AnsweredDay] {
        var result: [DayKey: AnsweredDay] = [:]
        for answer in answers {
            func set(_ days: some Sequence<DayKey>, _ value: Double?, _ source: DaySource) {
                for day in days {
                    result[day] = AnsweredDay(value: value, source: source, questionID: answer.questionID)
                }
            }
            switch answer.value {
            case .done:
                set(answer.covers, 1, .observed)
            case .notDone:
                set(answer.covers, 0, .observed)
            case let .perDay(days):
                for (day, done) in days {
                    set([day], done ? 1 : 0, .observed)
                }
            case let .count(done, total):
                let parentDone = Dependencies.parentDoneDays(
                    parentIDs: parentIDs, covers: answer.covers, records: parentRecords
                )
                let days = parentIDs.isEmpty || parentDone.isEmpty ? Array(answer.covers) : parentDone
                set(days, Double(done) / Double(total), .aggregated)
            case .dontRemember:
                set(answer.covers, nil, .unknown)
            case .delayed:
                break
            }
        }
        return result
    }

    private func interval(of model: AdherenceModel) throws -> Int {
        try model.askIntervalDays(target: habit.targetAdherence, settings: settings)
    }
}
