import Foundation

/// Beta posterior over the probability that the user does a habit on a given day (DESIGN.md §4.1).
///
/// Evidence decays toward the uniform prior once per elapsed non-paused day, so confidence fades and
/// the habit becomes due again; consistent answers build enough evidence to push that further out.
public struct AdherenceModel: Sendable, Hashable {
    public static let priorAlpha = 1.0
    public static let priorBeta = 1.0
    public static let prior = AdherenceModel(alpha: priorAlpha, beta: priorBeta)

    /// Pseudo-count for "did it".
    public private(set) var alpha: Double
    /// Pseudo-count for "didn't".
    public private(set) var beta: Double

    public enum InputError: Error, Equatable {
        case valueOutOfRange(Double)
        case negativeWeight(Double)
        case negativeDays(Int)
        case decayRateOutOfRange(Double)
        case maxDaysNotPositive(Int)
    }

    public init(alpha: Double, beta: Double) {
        self.alpha = alpha
        self.beta = beta
    }

    /// Total evidence `alpha + beta`.
    public var evidence: Double {
        alpha + beta
    }

    public var mean: Double {
        alpha / evidence
    }

    public var variance: Double {
        mean * (1 - mean) / (evidence + 1)
    }

    /// 0...0.5. Compared against `Settings.uncertaintyThreshold` (§4.2 rule 1).
    public var standardDeviation: Double {
        variance.squareRoot()
    }

    /// Weight of a day with `source` in the model update: 1 for observed/aggregated/health, 0 otherwise (§4.1).
    public static func weight(for source: DaySource) -> Double {
        source.feedsModel ? 1 : 0
    }

    /// Applies `days` elapsed days of decay at `rate` per day. Paused days must not be passed here (§4.6).
    public mutating func decay(days: Int, rate: Double) throws {
        guard days >= 0 else { throw InputError.negativeDays(days) }
        guard rate > 0, rate <= 1 else { throw InputError.decayRateOutOfRange(rate) }
        let factor = pow(rate, Double(days))
        alpha = Self.priorAlpha + (alpha - Self.priorAlpha) * factor
        beta = Self.priorBeta + (beta - Self.priorBeta) * factor
    }

    /// Adds one day of evidence: `value` in 0...1 (expected done), `weight` ≥ 0.
    public mutating func observe(value: Double, weight: Double) throws {
        guard (0 ... 1).contains(value) else { throw InputError.valueOutOfRange(value) }
        guard weight >= 0 else { throw InputError.negativeWeight(weight) }
        alpha += value * weight
        beta += (1 - value) * weight
    }

    /// Weight of a projected day: its source weight, or 0 when it is excluded from a gated habit's
    /// conditional metric (the model estimates P(child | parents), §4.5).
    public static func weight(for record: DayRecord) -> Double {
        record.conditionalDenominatorExcluded ? 0 : weight(for: record.source)
    }

    /// Adds a projected day (inferred/unknown/paused/blocked and conditionally excluded days add nothing).
    public mutating func observe(_ record: DayRecord) throws {
        try observe(value: record.value, weight: Self.weight(for: record))
    }

    /// The "ask interval" (§4.1): days from now until decay alone makes the habit due by §4.2 rules 1–3
    /// (`sd > threshold`, `mean < target`, or `maxDays` reached), in `1...maxDays`. 1 if rule 1 or 2
    /// already holds. Shown in the UI and charts, and the "> 7 days" test of rule 5.
    public func askIntervalDays(threshold: Double, target: Double, decayRate: Double, maxDays: Int) throws -> Int {
        guard maxDays >= 1 else { throw InputError.maxDaysNotPositive(maxDays) }
        func isDue(_ model: AdherenceModel) -> Bool {
            model.standardDeviation > threshold || model.mean < target
        }
        guard !isDue(self) else { return 1 }
        // Decay moves the mean monotonically toward 0.5 and only grows sd: the first crossing wins.
        var model = self
        for day in 1 ... maxDays {
            try model.decay(days: 1, rate: decayRate)
            if isDue(model) {
                return day
            }
        }
        return maxDays
    }

    /// `askIntervalDays` with the engine settings and a habit's target.
    public func askIntervalDays(target: Double, settings: Settings) throws -> Int {
        try askIntervalDays(
            threshold: settings.uncertaintyThreshold,
            target: target,
            decayRate: settings.decayPerDay,
            maxDays: settings.maxIntervalDays
        )
    }
}

public extension SchedulerState {
    /// The adherence posterior stored in this state.
    var adherence: AdherenceModel {
        get { AdherenceModel(alpha: alpha, beta: beta) }
        set {
            alpha = newValue.alpha
            beta = newValue.beta
        }
    }

    /// Fresh state for a habit with no evidence.
    static func initial(habitID: UUID) -> SchedulerState {
        SchedulerState(habitID: habitID, alpha: AdherenceModel.priorAlpha, beta: AdherenceModel.priorBeta)
    }
}
