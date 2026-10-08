import AppKit
import CryptoKit
import GChatKit
import ImageIO
import QuickLook
import QuickLookUI
import SwiftUI
import os

// MARK: - Message text

/// Message text in a native, read-only NSTextView. Compared with SwiftUI's
/// Text this gives the pointing-hand cursor over links, Look Up and Services
/// on selected text, and the standard text context menu.
struct MessageTextView: NSViewRepresentable {
    let text: AttributedString

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        apply(text, to: textView, context: context)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        apply(text, to: textView, context: context)
    }

    private func apply(_ text: AttributedString, to textView: NSTextView, context: Context) {
        guard context.coordinator.text != text else { return }
        context.coordinator.text = text
        textView.textStorage?.setAttributedString(NSAttributedString(chatText: text))
    }

    /// The height the text needs at the width SwiftUI offers.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return nil
        }
        let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 10_000
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        return CGSize(width: proposal.width == nil ? ceil(used.width) : width, height: ceil(used.height))
    }

    final class Coordinator {
        var text: AttributedString?
    }
}

extension NSAttributedString {
    /// Converts the output of ChatMarkup, which marks styles with
    /// presentation intents, into fonts and attributes AppKit draws.
    convenience init(chatText: AttributedString) {
        let output = NSMutableAttributedString()
        let body = NSFont.preferredFont(forTextStyle: .body)
        for run in chatText.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = intent.contains(.code)
                ? NSFont.monospacedSystemFont(ofSize: body.pointSize - 1, weight: .regular)
                : body
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if !traits.isEmpty {
                font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
            if intent.contains(.code) {
                attributes[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.2)
            }
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attributes[.link] = link
            }
            output.append(NSAttributedString(string: String(chatText[run.range].characters), attributes: attributes))
        }
        self.init(attributedString: output)
    }
}

// MARK: - Downloaded files

/// Attachments downloaded through the Chat API, kept in the app's Caches folder
/// so that scrolling back or reopening a conversation does not download them
/// again. Trimmed to a size limit at launch, emptied on Sign Out.
enum AttachmentFiles {
    private static let sizeLimit = 300 * 1024 * 1024

    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("attachments", isDirectory: true)
    }

    /// The cached file for an attachment, whether or not it has been downloaded yet.
    static func location(of attachment: Attachment) -> URL? {
        guard let resource = attachment.attachmentDataRef?.resourceName else { return nil }
        let key = SHA256.hash(data: Data(resource.utf8)).map { String(format: "%02x", $0) }.joined()
        let name = (attachment.contentName ?? "Attachment").replacingOccurrences(of: "/", with: "-")
        return folder.appendingPathComponent(key, isDirectory: true).appendingPathComponent(name)
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Deletes the least recently used files until the cache is under its size limit.
    static func prune() {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey]
        guard let entries = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else {
            return
        }
        var items: [(url: URL, date: Date, size: Int)] = entries.map { entry in
            let files = (try? manager.contentsOfDirectory(at: entry, includingPropertiesForKeys: keys)) ?? []
            let values = files.compactMap { try? $0.resourceValues(forKeys: Set(keys)) }
            return (
                entry,
                values.compactMap(\.contentModificationDate).max() ?? .distantPast,
                values.compactMap(\.totalFileAllocatedSize).reduce(0, +))
        }
        var total = items.reduce(0) { $0 + $1.size }
        items.sort { $0.date < $1.date }
        for item in items where total > sizeLimit {
            try? manager.removeItem(at: item.url)
            total -= item.size
        }
    }

    /// Lets the user keep a copy of a downloaded file wherever they choose.
    @MainActor
    static func saveCopy(of file: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: file, to: destination)
    }
}

/// Downloads attachments into the cache, once per file even when several
/// views ask at the same time.
@MainActor
final class AttachmentLoader {
    static let shared = AttachmentLoader()

    private var inFlight: [URL: Task<URL, Error>] = [:]

    func file(for attachment: Attachment, store: ChatStore) async throws -> URL {
        guard let location = AttachmentFiles.location(of: attachment) else { throw URLError(.fileDoesNotExist) }
        if FileManager.default.fileExists(atPath: location.path) {
            // Marks the file as recently used for pruning.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: location.path)
            return location
        }
        if let task = inFlight[location] { return try await task.value }
        let task = Task {
            defer { inFlight[location] = nil }
            guard let data = try await store.download(attachment) else { throw URLError(.fileDoesNotExist) }
            try FileManager.default.createDirectory(
                at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: location, options: .atomic)
            return location
        }
        inFlight[location] = task
        return try await task.value
    }
}

// MARK: - Attachments

/// Log lines for a fault seen in October 2026: a click on an image opened an
/// empty Quick Look window, and a second click showed the image (to-do.md).
/// The lines say whether the file was good at the click, and whether the view
/// was rebuilt while the window was open. They name the cache folder of the
/// file, which is a hash, and never the file name.
///
///     log show --last 1h --predicate 'subsystem == "org.themullers.gchat" AND category == "preview"'
@MainActor
enum PreviewLog {
    private static let log = Logger(subsystem: "org.themullers.gchat", category: "preview")

    private static func describe(_ file: URL?) -> String {
        guard let file else { return "no file" }
        let key = file.deletingLastPathComponent().lastPathComponent.prefix(8)
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? nil
        let type = file.pathExtension.isEmpty ? "no extension" : file.pathExtension
        return "\(key) (\(type), \(size.map { "\($0) bytes" } ?? "missing"))"
    }

    /// A click or the Open command, before the preview is asked for.
    static func clicked(_ file: URL?, in view: String) {
        let keyWindow = NSApp.keyWindow?.title ?? "none"
        log.notice("""
            \(view, privacy: .public) clicked: \(describe(file), privacy: .public), \
            app active \(NSApp.isActive), key window \(keyWindow, privacy: .public)
            """)
    }

    /// The file that the view asks Quick Look to show changed. Nil is a closed preview.
    static func changed(from old: URL?, to new: URL?, in view: String) {
        if let new {
            let visible = QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
            log.notice("""
                \(view, privacy: .public) preview opens: \(describe(new), privacy: .public), \
                Quick Look window already visible \(visible)
                """)
        } else {
            log.notice("\(view, privacy: .public) preview closed: \(describe(old), privacy: .public)")
        }
    }

    /// The view was rebuilt or removed. With an open preview, the Quick Look window loses its file.
    static func viewChanged(_ event: String, open file: URL?, in view: String) {
        guard let file else { return }
        log.notice("""
            \(view, privacy: .public) \(event, privacy: .public) while its preview was open: \
            \(describe(file), privacy: .public)
            """)
    }
}

/// An image uploaded to Chat, shown in the transcript. Click to open it in
/// Quick Look.
struct InlineImageView: View {
    let store: ChatStore
    let attachment: Attachment
    @State private var image: NSImage?
    @State private var pixelSize: CGSize?
    @State private var file: URL?
    @State private var failed = false
    @State private var previewURL: URL?

    private static let maxSize = CGSize(width: 360, height: 270)
    private static let placeholderSize = CGSize(width: 240, height: 160)

    var body: some View {
        Group {
            if let image, let pixelSize {
                let size = Self.displaySize(for: pixelSize)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
                    .contentShape(Rectangle())
                    .onTapGesture { preview() }
                    .contextMenu {
                        Button("Open") { preview() }
                        if let file {
                            Button("Save As…") { AttachmentFiles.saveCopy(of: file) }
                        }
                    }
                    .quickLookPreview($previewURL)
                    .onChange(of: previewURL) { old, new in
                        PreviewLog.changed(from: old, to: new, in: "image")
                    }
                    .onDisappear { PreviewLog.viewChanged("disappeared", open: previewURL, in: "image") }
                    .help(attachment.contentName ?? "Image")
                    .accessibilityLabel(attachment.contentName ?? "Image")
                    .accessibilityAddTraits(.isImage)
            } else if failed {
                AttachmentChip(store: store, attachment: attachment)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: Self.placeholderSize.width, height: Self.placeholderSize.height)
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .task(id: attachment.attachmentDataRef?.resourceName) { await load() }
    }

    private func preview() {
        PreviewLog.clicked(file, in: "image")
        previewURL = file
    }

    private func load() async {
        PreviewLog.viewChanged("loaded again", open: previewURL, in: "image")
        do {
            let file = try await AttachmentLoader.shared.file(for: attachment, store: store)
            guard let thumbnail = await Self.thumbnail(of: file) else {
                failed = true
                return
            }
            self.file = file
            pixelSize = thumbnail.pixelSize
            image = thumbnail.image
        } catch {
            failed = true
        }
    }

    /// Fits the image into the maximum size, treating pixels as Retina pixels
    /// and never enlarging.
    private static func displaySize(for pixels: CGSize) -> CGSize {
        let natural = CGSize(width: pixels.width / 2, height: pixels.height / 2)
        let scale = min(1, maxSize.width / max(natural.width, 1), maxSize.height / max(natural.height, 1))
        return CGSize(width: max(natural.width * scale, 24), height: max(natural.height * scale, 24))
    }

    /// Decodes a reduced copy off the main thread, so large photos do not stall scrolling.
    private static func thumbnail(of file: URL) async -> (image: NSImage, pixelSize: CGSize)? {
        let maxPixels = max(maxSize.width, maxSize.height) * 2
        return await Task.detached(priority: .userInitiated) { () -> (NSImage, CGSize)? in
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                  let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
            else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            // EXIF orientation can swap the stored width and height.
            let rotated = cgImage.width < cgImage.height && width > height
            return (image, rotated ? CGSize(width: height, height: width) : CGSize(width: width, height: height))
        }.value
    }
}

/// A file attached to a message. Files uploaded to Chat are downloaded with
/// the user's sign-in and shown in Quick Look. Others, such as Google Drive
/// files, open in the browser.
struct AttachmentChip: View {
    let store: ChatStore
    let attachment: Attachment
    @State private var isLoading = false
    @State private var previewURL: URL?

    var body: some View {
        let label = HStack(spacing: 5) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "paperclip")
            }
            Text(attachment.contentName ?? "Attachment").lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

        if attachment.attachmentDataRef?.resourceName != nil {
            Button { open { preview($0) } } label: { label }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .help("Open")
                .contextMenu {
                    Button("Open") { open { preview($0) } }
                    Button("Save As…") { open { AttachmentFiles.saveCopy(of: $0) } }
                }
                .quickLookPreview($previewURL)
                .onChange(of: previewURL) { old, new in
                    PreviewLog.changed(from: old, to: new, in: "file")
                }
                .onDisappear { PreviewLog.viewChanged("disappeared", open: previewURL, in: "file") }
        } else if let url = attachment.url {
            Link(destination: url) { label }
                .buttonStyle(.plain)
                .help("Open in browser")
        } else {
            label
        }
    }

    private func preview(_ file: URL) {
        PreviewLog.clicked(file, in: "file")
        previewURL = file
    }

    private func open(then action: @escaping (URL) -> Void) {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                action(try await AttachmentLoader.shared.file(for: attachment, store: store))
            } catch {
                store.alertMessage = "Could not open the attachment: \(error.localizedDescription)"
            }
        }
    }
}
