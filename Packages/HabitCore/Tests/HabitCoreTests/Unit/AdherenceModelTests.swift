import Foundation
import HabitCore
import Testing

private let rate = Settings.default.decayPerDay
private let threshold = Settings.default.uncertaintyThreshold

private func isClose(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-12) -> Bool {
    abs(lhs - rhs) <= tolerance
}

/// `days` consecutive days of the same answer, decaying between them like the projection will.
private func model(answering value: Double, days: Int) throws -> AdherenceModel {
    var model = AdherenceModel.prior
    for _ in 0 ..< days {
        try model.decay(days: 1, rate: rate)
        try model.observe(value: value, weight: 1)
    }
    return model
}

struct AdherenceModelTests {
    @Test func priorIsUniform() {
        let prior = AdherenceModel.prior
        #expect(prior.mean == 0.5)
        #expect(isClose(prior.standardDeviation, (0.25 / 3).squareRoot()))
        #expect(prior.standardDeviation > threshold)
    }

    @Test func observeMovesPseudoCounts() throws {
        var model = AdherenceModel.prior
        try model.observe(value: 1, weight: 1)
        #expect(model.alpha == 2 && model.beta == 1)
        #expect(isClose(model.mean, 2.0 / 3))
        try model.observe(value: 0.25, weight: 1)
        #expect(model.alpha == 2.25 && model.beta == 1.75)
        try model.observe(value: 1, weight: 0)
        #expect(model.alpha == 2.25 && model.beta == 1.75)
    }

    @Test func recordWeightsFollowSource() throws {
        let day = try #require(DayKey("2026-09-27"))
        for source in DaySource.allCases {
            var model = AdherenceModel.prior
            try model.observe(DayRecord(habitID: UUID(), day: day, value: 1, source: source, confidence: 1))
            #expect(model.alpha == (source.feedsModel ? 2 : 1), "\(source)")
        }
    }

    @Test func conditionallyExcludedDaysDoNotFeedModel() throws {
        let day = try #require(DayKey("2026-09-27"))
        var model = AdherenceModel.prior
        try model.observe(DayRecord(
            habitID: UUID(), day: day, value: 0, source: .observed, confidence: 1,
            conditionalDenominatorExcluded: true
        ))
        #expect(model == .prior)
    }

    @Test func decayShrinksEvidenceTowardPrior() throws {
        var model = AdherenceModel(alpha: 11, beta: 3)
        try model.decay(days: 1, rate: 0.5)
        #expect(model.alpha == 6 && model.beta == 2)
        try model.decay(days: 0, rate: 0.5)
        #expect(model.alpha == 6 && model.beta == 2)
        try model.decay(days: 1, rate: 1)
        #expect(model.alpha == 6 && model.beta == 2)
        try model.decay(days: 2000, rate: rate)
        #expect(isClose(model.alpha, 1) && isClose(model.beta, 1))
    }

    @Test func multiDayDecayEqualsRepeatedSingleDays() throws {
        var once = AdherenceModel(alpha: 9.3, beta: 2.1)
        var stepwise = once
        try once.decay(days: 13, rate: rate)
        for _ in 0 ..< 13 {
            try stepwise.decay(days: 1, rate: rate)
        }
        #expect(isClose(once.alpha, stepwise.alpha) && isClose(once.beta, stepwise.beta))
    }

    @Test func rejectsInvalidInput() {
        var model = AdherenceModel.prior
        #expect(throws: AdherenceModel.InputError.valueOutOfRange(1.5)) { try model.observe(value: 1.5, weight: 1) }
        #expect(throws: AdherenceModel.InputError.negativeWeight(-1)) { try model.observe(value: 1, weight: -1) }
        #expect(throws: AdherenceModel.InputError.negativeDays(-1)) { try model.decay(days: -1, rate: rate) }
        #expect(throws: AdherenceModel.InputError.decayRateOutOfRange(0)) { try model.decay(days: 1, rate: 0) }
        #expect(throws: AdherenceModel.InputError.maxDaysNotPositive(0)) {
            try model.askIntervalDays(threshold: threshold, target: 0.8, decayRate: rate, maxDays: 0)
        }
        #expect(model == .prior)
    }

    /// Daily "yes" converges to alpha ≈ 1 + 1/(1 - d) = 13.5, beta = 1: confident, asked every ~2 weeks.
    /// Rule 1 alone (sd) would wait ~16 days; the 14-day ceiling (rule 3) comes first.
    @Test func steadyYesBecomesConfidentWithLongInterval() throws {
        let steady = try model(answering: 1, days: 60)
        #expect(isClose(steady.alpha, 1 + (1 - pow(0.92, 60)) / (1 - 0.92), tolerance: 1e-9))
        #expect(steady.mean > 0.9)
        #expect(steady.standardDeviation < 0.07)
        let interval = try steady.askIntervalDays(threshold: threshold, target: 0.8, decayRate: rate, maxDays: 30)
        #expect((15 ... 17).contains(interval))
        #expect(try steady.askIntervalDays(target: 0.8, settings: .default) == Settings.default.maxIntervalDays)
    }

    /// A 50/50 habit is below the sd threshold too, so only the mean < target rule keeps it daily (§4.2 rule 2).
    @Test func flakyHabitIsConfidentlyMediocre() throws {
        var flaky = AdherenceModel.prior
        for day in 0 ..< 60 {
            try flaky.decay(days: 1, rate: rate)
            try flaky.observe(value: day.isMultiple(of: 2) ? 1 : 0, weight: 1)
        }
        #expect(abs(flaky.mean - 0.5) < 0.05)
        #expect(flaky.standardDeviation < threshold)
        #expect(flaky.mean < Habit.defaultTargetAdherence)
        // So its ask interval is 1; with a target it meets, it follows the sd crossing.
        #expect(try flaky.askIntervalDays(threshold: threshold, target: 0.8, decayRate: rate, maxDays: 30) == 1)
        #expect(try flaky.askIntervalDays(threshold: threshold, target: 0.4, decayRate: rate, maxDays: 30) > 1)
    }

    /// Decay pulls `mean` toward 0.5 but leaves `answeredMean` alone, so silence alone never makes a
    /// habit "below target" (O6). Only new evidence moves it.
    @Test func answeredMeanIgnoresDecay() throws {
        #expect(AdherenceModel.prior.answeredMean == nil)
        #expect(!AdherenceModel.prior.isBelowTarget(0.8))
        var mostly = AdherenceModel.prior
        for day in 0 ..< 20 {
            try mostly.decay(days: 1, rate: rate)
            try mostly.observe(value: day % 10 == 0 ? 0 : 1, weight: 1)
        }
        let answered = try #require(mostly.answeredMean)
        #expect(answered == mostly.mean)
        #expect(answered > 0.8)
        try mostly.decay(days: 30, rate: rate)
        #expect(mostly.mean < 0.8)
        #expect(mostly.answeredMean == answered)
        #expect(!mostly.isBelowTarget(0.8))
        // Zero-weight days (inferred, paused, ...) are not answers either.
        try mostly.observe(value: 0, weight: 0)
        #expect(mostly.answeredMean == answered)
        try mostly.observe(value: 0, weight: 1)
        #expect(mostly.isBelowTarget(0.8))
    }

    /// Rule 2 holds now or never, so a target only matters when the evidence is already below it.
    @Test func targetDoesNotShortenIntervalAboveIt() throws {
        let steady = try model(answering: 1, days: 60)
        let lenient = try steady.askIntervalDays(threshold: threshold, target: 0.8, decayRate: rate, maxDays: 30)
        let strict = try steady.askIntervalDays(threshold: threshold, target: 0.9, decayRate: rate, maxDays: 30)
        #expect(strict == lenient)
        let mediocre = try model(answering: 0.7, days: 60)
        #expect(try mediocre.askIntervalDays(threshold: threshold, target: 0.8, decayRate: rate, maxDays: 30) == 1)
    }

    @Test func intervalGrowsWithEvidenceAndIsCapped() throws {
        let intervals = try [1, 3, 7, 14, 30].map {
            try model(answering: 1, days: $0)
                .askIntervalDays(threshold: threshold, target: 0.8, decayRate: rate, maxDays: 30)
        }
        #expect(intervals == intervals.sorted())
        #expect(try AdherenceModel.prior
            .askIntervalDays(threshold: threshold, target: 0, decayRate: rate, maxDays: 30) == 1)
        let confident = AdherenceModel(alpha: 500, beta: 1)
        #expect(try confident.askIntervalDays(threshold: threshold, target: 0.8, decayRate: 0.999, maxDays: 30) == 30)
    }

    @Test func schedulerStateExposesModel() {
        var state = SchedulerState.initial(habitID: UUID())
        #expect(state.adherence == .prior)
        state.adherence = AdherenceModel(alpha: 4, beta: 2)
        #expect(state.alpha == 4 && state.beta == 2)
    }
}
