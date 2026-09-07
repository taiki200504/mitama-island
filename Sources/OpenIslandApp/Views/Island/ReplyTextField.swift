import SwiftUI
import OpenIslandCore

import AppKit

// MARK: - Reply TextField (NSTextField wrapper for IME-safe Enter handling)

/// NSTextField wrapper that fires `onSubmit` only when the IME composition
/// is finished — pressing Enter during Chinese/Japanese IME composition
/// confirms the candidate instead of submitting.
/// A field that takes the click that reaches it, rather than spending it on
/// making the panel key.
///
/// The island floats over other apps without activating them, so a click on the
/// reply box arrives while the app is in the background. AppKit's default is to
/// swallow that first click; the caret then never appears and the box looks
/// broken until you click a second time.
private final class ReplyField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension NSTextField {
    /// True while an input method is holding uncommitted text.
    ///
    /// The field itself never knows: editing happens in the window's shared
    /// field editor, so the question has to be asked of that.
    var isComposing: Bool {
        (currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    }
}

struct ReplyTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = ReplyField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        // The reply field draws outside SwiftUI, so it cannot read the palette
        // through the environment. Converting the theme's paper here keeps the
        // caret and the typed text the same colour as the card around them.
        let paper = NSColor(V6Palette.paper)
        field.textColor = paper
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: paper.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 13),
            ]
        )
        field.delegate = context.coordinator
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onSubmit = onSubmit

        // Writing `stringValue` while the IME is mid-composition tears down the
        // field editor's marked text, and the half-typed reading disappears.
        // Every keystroke of a Japanese word goes through that state, so the
        // binding must wait until the candidate is committed.
        guard !nsView.isComposing else { return }

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            // An input method only attaches to the active application, so the
            // island has to come forward for the length of the reply. It hands
            // the front back when the island closes.
            TextInputFocusHandoff.take()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Let AppKit handle Enter during IME composition (e.g. confirming
                // a Chinese/Japanese candidate). Only submit when no marked text.
                guard !textView.hasMarkedText() else { return false }
                onSubmit()
                return true
            }
            return false
        }
    }
}

extension String {
    var trimmedForNotificationCard: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
