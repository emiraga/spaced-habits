import HabitCore

/// A synthetic user (DESIGN.md §4.8): habits with a true daily probability, optional pauses, and a seed.
public struct Scenario: Sendable {
    public struct HabitSpec: Sendable {
        public let name: String
        /// Index into `habits` of the gate parent, if any. A child is never done on a day its parent isn't.
        public let parent: Int?
        /// Probability the habit is done on a day index (given the parent was done, for a child).
        public let probability: @Sendable (Int) -> Double
        /// `Habit.dueTime` (§4.2).
        public let dueTime: TimeOfDay?

        public init(
            name: String,
            parent: Int? = nil,
            dueTime: TimeOfDay? = nil,
            probability: @escaping @Sendable (Int) -> Double
        ) {
            self.name = name
            self.parent = parent
            self.dueTime = dueTime
            self.probability = probability
        }
    }

    /// Pauses `habit` on day indices `days` (inclusive).
    public struct PauseSpec: Sendable {
        public let habit: Int
        public let days: ClosedRange<Int>

        public init(habit: Int, days: ClosedRange<Int>) {
            self.habit = habit
            self.days = days
        }
    }

    public let name: String
    public let habits: [HabitSpec]
    public let pauses: [PauseSpec]
    public let days: Int
    public let seed: UInt64
    /// Local hour (UTC) of the daily session.
    public let sessionHour: Int

    public init(
        name: String,
        habits: [HabitSpec],
        pauses: [PauseSpec] = [],
        days: Int = 180,
        seed: UInt64 = 42,
        sessionHour: Int = 12
    ) {
        self.name = name
        self.habits = habits
        self.pauses = pauses
        self.days = days
        self.seed = seed
        self.sessionHour = sessionHour
    }

    /// Ground truth per habit per day index, drawn once from `seed`.
    public func drawTruth() -> [[Bool]] {
        var random = SeededRandomSource(seed: seed)
        var truth = habits.map { _ in [Bool](repeating: false, count: days) }
        for day in 0 ..< days {
            for (index, spec) in habits.enumerated() {
                let draw = random.bernoulli(spec.probability(day))
                truth[index][day] = draw && (spec.parent.map { truth[$0][day] } ?? true)
            }
        }
        return truth
    }
}

public extension Scenario {
    /// With a `dueTime` and a `sessionHour` before it, every session asks about days through yesterday.
    static func steady(probability: Double = 0.95, dueTime: TimeOfDay? = nil, sessionHour: Int = 12) -> Scenario {
        Scenario(
            name: "steady",
            habits: [HabitSpec(name: "Steady", dueTime: dueTime) { _ in probability }],
            sessionHour: sessionHour
        )
    }

    static func flaky(probability: Double = 0.5) -> Scenario {
        Scenario(name: "flaky", habits: [HabitSpec(name: "Flaky") { _ in probability }])
    }

    static func collapsing(before: Double = 0.95, after: Double = 0.1, collapseDay: Int = 60) -> Scenario {
        Scenario(name: "collapsing", habits: [HabitSpec(name: "Collapsing") { $0 < collapseDay ? before : after }])
    }

    static func vacation(probability: Double = 0.9, pause: ClosedRange<Int> = 60 ... 73) -> Scenario {
        Scenario(
            name: "vacation",
            habits: [HabitSpec(name: "Vacationer") { _ in probability }],
            pauses: [PauseSpec(habit: 0, days: pause)]
        )
    }

    static func dependentPair(parent: Double = 0.9, childGivenParent: Double = 0.8) -> Scenario {
        Scenario(
            name: "dependent-pair",
            habits: [
                HabitSpec(name: "Gym") { _ in parent },
                HabitSpec(name: "Shake", parent: 0) { _ in childGivenParent },
            ]
        )
    }

    /// The five §4.8 users by CLI name.
    static let all: [String: Scenario] = [
        "steady": .steady(),
        "flaky": .flaky(),
        "collapsing": .collapsing(),
        "vacation": .vacation(),
        "dependent-pair": .dependentPair(),
    ]
}
