import HabitStore

public extension AppModel {
    /// Applies the other device's writes (the watch bridge, §7) and re-plans if anything changed. Not a new
    /// session, like a CloudKit merge (§10).
    func merge(_ changes: [TruthChange]) throws {
        if try store.merge(changes) {
            try reload(newSession: false)
        }
    }
}
