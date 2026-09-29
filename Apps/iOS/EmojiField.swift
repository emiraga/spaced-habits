import SwiftUI
import UIKit

/// The habit's badge: a circle in its color holding its emoji. Tapping it opens the emoji keyboard;
/// picking an emoji closes it, and delete clears it.
struct EmojiField: View {
    @Binding var emoji: String?
    let colorHex: String

    var body: some View {
        let color = Color(hex: colorHex)
        EmojiTextField(emoji: $emoji)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.2), in: Circle())
            .overlay {
                if emoji == nil {
                    Image(systemName: "face.smiling")
                        .font(.title2)
                        .foregroundStyle(color)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// A `UITextField` that asks for the emoji keyboard, which SwiftUI's `TextField` can't do.
private struct EmojiTextField: UIViewRepresentable {
    @Binding var emoji: String?

    func makeUIView(context: Context) -> EmojiKeyboardTextField {
        let field = EmojiKeyboardTextField()
        field.textAlignment = .center
        field.font = .systemFont(ofSize: 26)
        field.tintColor = .clear
        field.accessibilityLabel = String(localized: "Emoji")
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.required, for: .horizontal)
        return field
    }

    func updateUIView(_ field: EmojiKeyboardTextField, context _: Context) {
        if field.text != emoji ?? "" {
            field.text = emoji
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(emoji: $emoji)
    }

    @MainActor
    final class Coordinator: NSObject {
        let emoji: Binding<String?>

        init(emoji: Binding<String?>) {
            self.emoji = emoji
        }

        /// Keeps the last character typed, so the field holds one emoji; empty clears it.
        @objc func changed(_ field: UITextField) {
            let last = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).last.map(String.init)
            emoji.wrappedValue = last
            field.text = last
            if last != nil {
                field.resignFirstResponder()
            }
        }
    }
}

/// Closes its keyboard on a tap anywhere else (a color, a toggle), which still reaches what was tapped.
final class EmojiKeyboardTextField: UITextField, UIGestureRecognizerDelegate {
    private lazy var outsideTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(tappedOutside))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        return tap
    }()

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            window?.addGestureRecognizer(outsideTap)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        outsideTap.view?.removeGestureRecognizer(outsideTap)
        return super.resignFirstResponder()
    }

    @objc private func tappedOutside() {
        _ = resignFirstResponder()
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view.map { !$0.isDescendant(of: self) } ?? true
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }

    /// The emoji keyboard when the user has it enabled (the default), else their current keyboard.
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }

    /// Without its own context, iOS reopens whichever keyboard the user last used here.
    override var textInputContextIdentifier: String? {
        ""
    }
}
