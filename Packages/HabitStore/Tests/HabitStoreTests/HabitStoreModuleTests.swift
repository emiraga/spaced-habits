import HabitStore
import Testing

struct HabitStoreModuleTests {
    @Test func linksAgainstHabitCore() {
        #expect(HabitStoreModule.name == "HabitStore")
        #expect(HabitStoreModule.engine == "HabitCore")
    }
}
