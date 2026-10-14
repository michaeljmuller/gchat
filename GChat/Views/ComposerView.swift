import AppKit
import GChatKit
import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @Binding var text: String
    /// A pasted image that goes with the text.
    @Binding var file: OutgoingFile?
    let placeholder: String
    let onSend: () -> Void

    @State private var height: CGFloat = 30
    /// Counts presses of the emoji button. The text view opens the picker on each change.
    @State private var emojiRequests = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let file {
                ComposerFileView(file: file) { self.file = nil }
                    // In line with the text field: past the emoji button.
                    .padding(.leading, 26)
            }
            row
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var row: some View {
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

            ComposerTextView(
                text: $text, height: $height, emojiRequests: emojiRequests, onSubmit: onSend,
                onPasteFile: { file = $0 })
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
    }

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && file == nil
    }
}

/// The pasted image above the text field, with a button that removes it.
struct ComposerFileView: View {
    let file: OutgoingFile
    let onRemove: () -> Void

    var body: some View {
        FileThumbnail(file: file, maxSize: CGSize(width: 200, height: 120))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Remove")
                .padding(4)
            }
            .accessibilityLabel("Pasted image \(file.filename)")
    }
}

/// A small picture of an image that is not sent yet, or the file name for
/// another kind of file.
struct FileThumbnail: View {
    let file: OutgoingFile
    let maxSize: CGSize
    private let image: NSImage?

    init(file: OutgoingFile, maxSize: CGSize) {
        self.file = file
        self.maxSize = maxSize
        self.image = file.isImage ? NSImage(data: file.data) : nil
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: min(maxSize.width, image.size.width), maxHeight: min(maxSize.height, image.size.height))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator) }
        } else {
            Label(file.filename, systemImage: "doc")
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
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
    let onPasteFile: (OutgoingFile) -> Void

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

        // The standard text view, swapped for one that takes pasted images,
        // with the same layout settings.
        let standard = scrollView.documentView as! NSTextView
        let textView = PastingTextView(frame: standard.frame)
        textView.minSize = standard.minSize
        textView.maxSize = standard.maxSize
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        textView.onPasteFile = { [weak coordinator = context.coordinator] file in
            coordinator?.parent.onPasteFile(file)
        }
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

/// The composer's text view. Paste takes an image as an attachment; text
/// pastes as usual.
final class PastingTextView: NSTextView {
    var onPasteFile: ((OutgoingFile) -> Void)?

    override func paste(_ sender: Any?) {
        if let file = PastedFile.read(from: .general) {
            onPasteFile?(file)
        } else {
            super.paste(sender)
        }
    }

    /// A plain-text view turns Paste off when the clipboard holds no text.
    /// The menu and Command-V ask here.
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(paste(_:)), PastedFile.isAvailable(on: .general) { return true }
        return super.validateMenuItem(item)
    }
}

enum PastedFile {
    private static let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]
    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, NSPasteboard.PasteboardType(UTType.jpeg.identifier), .tiff,
    ]

    /// Whether the clipboard may hold an image, without reading it. For the
    /// Paste menu item, which macOS checks often.
    static func isAvailable(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: fileOptions)
            || pasteboard.availableType(from: imageTypes) != nil
    }

    /// An image on the clipboard: a copied image file, for example from the
    /// Finder, or image data, for example a screenshot. Nil when the
    /// clipboard holds text, so that copied text with pictures, as from a web
    /// page, pastes as text.
    static func read(from pasteboard: NSPasteboard) -> OutgoingFile? {
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL])?.first,
           let data = try? Data(contentsOf: url) {
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            return OutgoingFile(data: data, filename: url.lastPathComponent, contentType: type)
        }
        if pasteboard.string(forType: .string)?.isEmpty == false { return nil }
        if let data = pasteboard.data(forType: .png) {
            return OutgoingFile(data: data, filename: "Pasted image.png", contentType: "image/png")
        }
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)) {
            return OutgoingFile(data: data, filename: "Pasted image.jpg", contentType: "image/jpeg")
        }
        // Other image data, such as TIFF, goes as PNG, which every Chat client shows.
        if let tiff = pasteboard.data(forType: .tiff),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return OutgoingFile(data: png, filename: "Pasted image.png", contentType: "image/png")
        }
        return nil
    }
}
