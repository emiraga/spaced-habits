import HabitCore

/// Module marker for the SwiftData store. Models and mapping land in M2 (DESIGN.md §10).
public enum HabitStoreModule {
    public static let name = "HabitStore"
    public static let engine = HabitCoreModule.name
}
