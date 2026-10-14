import AppKit
import GChatKit
import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    let placeholder: String
    let onSend: () -> Void

    @State private var height: CGFloat = 30
    /// Counts presses of the emoji button. The text view opens the picker on each change.
    @State private var emojiRequests = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                emojiRequests += 1
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Emoji & Symbols (Control-Command-Space)")
            .padding(.bottom, 6)

            ComposerTextView(text: $text, height: $height, emojiRequests: emojiRequests, onSubmit: onSend)
                .frame(height: height)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .padding(.leading, ComposerTextView.inset.width + 5)
                            .padding(.top, ComposerTextView.inset.height)
                            .allowsHitTesting(false)
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.separator)
                }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
            .disabled(isEmpty)
            .help("Send (Return)")
            .padding(.bottom, 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A plain-text NSTextView that grows with its content.
/// Return sends; Shift-Return and Option-Return insert a line break.
/// Emoticons and short codes change to emoji as they are typed (EmojiShortcuts).
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let emojiRequests: Int
    let onSubmit: () -> Void

    static let inset = NSSize(width: 4, height: 7)
    private static let maxLines: CGFloat = 8

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = Self.inset
        textView.string = text

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            context.coordinator.updateHeight(of: textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if emojiRequests != context.coordinator.emojiRequests {
            context.coordinator.emojiRequests = emojiRequests
            textView.window?.makeFirstResponder(textView)
            NSApp.orderFrontCharacterPalette(textView)
        }
        if textView.string != text {
            textView.string = text
            DispatchQueue.main.async { context.coordinator.updateHeight(of: textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        var emojiRequests: Int

        init(_ parent: ComposerTextView) {
            self.parent = parent
            self.emojiRequests = parent.emojiRequests
        }

        func textView(
            _ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?
        ) -> Bool {
            guard let text, text == " " || text == ":" else { return true }
            return !replaceShortcut(in: textView, before: range, trigger: Character(text))
        }

        /// Changes the word before `range` to an emoji, followed by the
        /// trigger unless it is the colon that ends a short code. True if it did.
        @discardableResult
        func replaceShortcut(in textView: NSTextView, before range: NSRange, trigger: Character?) -> Bool {
            guard UserDefaults.standard.object(forKey: AppSettings.emoticonsKey) as? Bool ?? true,
                  range.length == 0, !textView.hasMarkedText()
            else { return false }
            let string = textView.string as NSString
            let space = string.rangeOfCharacter(
                from: .whitespacesAndNewlines, options: .backwards, range: NSRange(location: 0, length: range.location))
            let wordStart = space.location == NSNotFound ? 0 : space.location + space.length
            let word = string.substring(with: NSRange(location: wordStart, length: range.location - wordStart))
            guard !word.isEmpty, let emoji = EmojiShortcuts.replacement(for: word, trigger: trigger) else {
                return false
            }
            let suffix = trigger.map { $0 == ":" ? "" : String($0) } ?? ""
            // insertText goes through undo, so Command-Z brings the text back.
            textView.insertText(
                emoji + suffix, replacementRange: NSRange(location: wordStart, length: range.location - wordStart))
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight(of: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            replaceShortcut(in: textView, before: textView.selectedRange(), trigger: nil)
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onSubmit()
            }
            return true
        }

        func updateHeight(of textView: NSTextView) {
            guard let layoutManager = textView.layoutManager, let container = textView.textContainer,
                  let font = textView.font
            else { return }
            layoutManager.ensureLayout(for: container)
            let line = layoutManager.defaultLineHeight(for: font)
            let content = max(layoutManager.usedRect(for: container).height, line)
            let height = (min(content, line * ComposerTextView.maxLines) + ComposerTextView.inset.height * 2)
                .rounded(.up)
            if abs(parent.height - height) > 0.5 {
                parent.height = height
            }
        }
    }
}
