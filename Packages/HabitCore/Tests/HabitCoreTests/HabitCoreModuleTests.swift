import HabitCore
import Testing

struct HabitCoreModuleTests {
    @Test func moduleIsLinked() {
        #expect(HabitCoreModule.name == "HabitCore")
    }
}
