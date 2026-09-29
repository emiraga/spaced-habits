@testable import SpacedHabits
import Testing

struct EmojiFieldTests {
    @Test func keepsTheTypedEmoji() {
        #expect(EmojiField.picked("🏋️") == "🏋️")
        #expect(EmojiField.picked("👍🏽") == "👍🏽")
    }

    @Test func keepsTheLastOfSeveralPasted() {
        #expect(EmojiField.picked("📚 🧘") == "🧘")
    }

    @Test func deleteOrBlanksPickNothing() {
        #expect(EmojiField.picked("") == nil)
        #expect(EmojiField.picked("  ") == nil)
    }
}
