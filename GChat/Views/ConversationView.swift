import AppKit
import GChatKit
import SwiftUI

struct ConversationView: View {
    @Environment(AppModel.self) private var model
    let store: ChatStore
    let space: Space

    var body: some View {
        let title = store.title(for: space)
        VStack(spacing: 0) {
            TranscriptView(store: store, space: space)
            Divider()
            ComposerView(
                text: Binding(
                    get: { model.drafts[space.name] ?? "" },
                    set: { model.drafts[space.name] = $0 }),
                file: Binding(
                    get: { model.draftFiles[space.name] },
                    set: { model.draftFiles[space.name] = $0 }),
                placeholder: "Message \(title)",
                onSend: send)
        }
        .navigationTitle(title)
        .task { await store.open(space.name) }
    }

    private func send() {
        let text = model.drafts[space.name] ?? ""
        let file = model.draftFiles[space.name]
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || file != nil else { return }
        model.drafts[space.name] = ""
        model.draftFiles[space.name] = nil
        Task { await store.send(text, file: file, to: space.name) }
    }
}

struct TranscriptRow: Identifiable {
    let message: Message
    /// False when the message continues the previous sender's run.
    let showsHeader: Bool
    /// Set on the first message of a day.
    let day: Date?

    var id: String { message.name }

    static func rows(for messages: [Message]) -> [TranscriptRow] {
        let calendar = Calendar.current
        var rows: [TranscriptRow] = []
        var previous: Message?
        for message in messages {
            let time = message.createTime ?? .distantPast
            let previousTime = previous?.createTime ?? .distantPast
            let isNewDay = previous == nil || !calendar.isDate(previousTime, inSameDayAs: time)
            let continues = previous?.sender?.name == message.sender?.name
                && time.timeIntervalSince(previousTime) < 300
            rows.append(TranscriptRow(
                message: message, showsHeader: isNewDay || !continues, day: isNewDay ? time : nil))
            previous = message
        }
        return rows
    }
}

struct TranscriptView: View {
    let store: ChatStore
    let space: Space
    /// Loading older messages on scroll starts only after the first layout has settled.
    @State private var isArmed = false
    /// Whether the person is following the end of the transcript. It stays
    /// true while content grows or the app scrolls, and becomes false only
    /// when the person scrolls up. New messages scroll into view only while
    /// it is true, so reading older messages is not interrupted.
    @State private var isAtBottom = true
    /// A message arrived while the person was reading further up.
    @State private var hasNewBelow = false
    /// Until then, movement of the view is the app's own doing: content that
    /// just loaded, or a scroll that the app started.
    @State private var settlingUntil = Date.distantPast

    private static let bottomID = "transcript-bottom"
    /// Space between the last message and the composer.
    private static let bottomSpace: CGFloat = 12
    /// How close to the end counts as being at the bottom.
    private static let bottomTolerance: CGFloat = 40

    /// What the scroll view reports about its position.
    private struct ScrollState: Equatable {
        var contentHeight: CGFloat
        var offset: CGFloat
        var distanceFromBottom: CGFloat
    }

    var body: some View {
        let transcript = store.transcript(for: space.name)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if transcript.olderPageToken != nil {
                        earlierButton(transcript, proxy)
                    }
                    ForEach(TranscriptRow.rows(for: transcript.messages)) { row in
                        if let day = row.day { DaySeparator(day: day) }
                        MessageRowView(store: store, row: row)
                            .id(row.id)
                    }
                    ForEach(transcript.pending) { pending in
                        PendingRowView(store: store, space: space.name, pending: pending)
                    }
                    // The space below the last message is part of this marker,
                    // not padding, so that scrolling to the marker shows it.
                    Color.clear.frame(height: Self.bottomSpace).id(Self.bottomID)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: ScrollState.self) { geometry in
                // visibleRect is the part of the content that shows, in content
                // coordinates. It leaves out the area under the title bar, which
                // the offset and the container size include. A first version
                // computed the distance from those and was always 52 points off.
                ScrollState(
                    contentHeight: geometry.contentSize.height,
                    offset: geometry.visibleRect.minY,
                    distanceFromBottom: geometry.contentSize.height - geometry.visibleRect.maxY)
            } action: { old, new in
                if new.distanceFromBottom < Self.bottomTolerance {
                    // The end is in view, however it got there.
                    isAtBottom = true
                    hasNewBelow = false
                } else if new.offset < old.offset - 0.5, Date() > settlingUntil {
                    // The view moved up and the end is out of view: the person
                    // scrolled up. The app itself only ever scrolls down here,
                    // but rows that are still being laid out can shift the view
                    // up for a moment, which settlingUntil covers.
                    isAtBottom = false
                } else if new.contentHeight > old.contentHeight, isAtBottom {
                    // Content grew below while the person was at the end: a new
                    // message, or an image that finished loading. Follow it.
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: transcript.pending.count) { old, new in
                // The person sent a message: always show it.
                if new > old { scrollToBottom(proxy) }
            }
            .onChange(of: transcript.messages.last?.name) {
                settlingUntil = Date().addingTimeInterval(0.5)
                if isAtBottom {
                    scrollToBottom(proxy)
                } else if transcript.isLoaded {
                    hasNewBelow = true
                }
            }
            .overlay(alignment: .bottom) {
                if hasNewBelow {
                    Button {
                        scrollToBottom(proxy)
                    } label: {
                        Label("New messages", systemImage: "arrow.down")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .overlay { Capsule().strokeBorder(.separator) }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                    .transition(.opacity)
                }
            }
        }
        .overlay {
            if let error = transcript.loadError {
                ContentUnavailableView {
                    Label("Could not load messages", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error).textSelection(.enabled)
                } actions: {
                    Button("Try Again") { Task { await store.open(space.name) } }
                }
            } else if !transcript.isLoaded {
                ProgressView()
            } else if transcript.messages.isEmpty && transcript.pending.isEmpty {
                Text("No messages yet").foregroundStyle(.secondary)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            isArmed = true
        }
    }

    /// Scrolls to the very end, including the space below the last message.
    /// Deferred one turn, so that the new row is laid out first.
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        hasNewBelow = false
        settlingUntil = Date().addingTimeInterval(0.5)
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    private func earlierButton(_ transcript: Transcript, _ proxy: ScrollViewProxy) -> some View {
        HStack {
            Spacer()
            if transcript.isLoadingOlder {
                ProgressView().controlSize(.small)
            } else {
                Button("Load Earlier Messages") { loadOlder(transcript, proxy) }
                    .buttonStyle(.link)
            }
            Spacer()
        }
        .frame(height: 28)
        .onAppear {
            if isArmed { loadOlder(transcript, proxy) }
        }
    }

    private func loadOlder(_ transcript: Transcript, _ proxy: ScrollViewProxy) {
        let anchor = transcript.messages.first?.name
        Task {
            await store.loadOlder(in: space.name)
            // Keep the message that was at the top where it was.
            if let anchor { proxy.scrollTo(anchor, anchor: .top) }
        }
    }
}

struct DaySeparator: View {
    let day: Date

    var body: some View {
        HStack(spacing: 12) {
            VStack { Divider() }
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            VStack { Divider() }
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }
}

struct MessageRowView: View {
    let store: ChatStore
    let row: TranscriptRow
    @State private var isHovering = false
    @State private var isPickingReaction = false

    private static let avatarSize: CGFloat = 32
    /// How far the hover highlight reaches past the avatar and the text.
    private static let highlightInset: CGFloat = 6

    var body: some View {
        let message = row.message
        let sender = store.name(for: message.sender)
        HStack(alignment: .top, spacing: 10) {
            if row.showsHeader {
                AvatarView(
                    url: message.sender.flatMap { store.profile(for: $0.name)?.photoURL },
                    name: sender, size: Self.avatarSize)
            } else {
                Color.clear.frame(width: Self.avatarSize, height: 1)
            }
            VStack(alignment: .leading, spacing: 3) {
                if row.showsHeader {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(sender).font(.headline)
                        if let time = message.createTime {
                            Text(time, format: .dateTime.hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                // On the time only. On the whole row, it showed
                                // together with the names of a reaction.
                                .help(time.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
                if !message.markup.isEmpty {
                    MessageTextView(text: rendered(message))
                }
                ForEach(message.attachment ?? [], id: \.self) { attachment in
                    if attachment.isDownloadableImage {
                        InlineImageView(store: store, attachment: attachment)
                    } else {
                        AttachmentChip(store: store, attachment: attachment)
                    }
                }
                let reactions = store.reactions(on: message)
                if !reactions.isEmpty {
                    ReactionBar(store: store, message: message, reactions: reactions) {
                        isPickingReaction = true
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Self.highlightInset)
        // The message that the reaction control belongs to is highlighted.
        .background(
            Color.primary.opacity(showsControl ? 0.06 : 0),
            in: RoundedRectangle(cornerRadius: 6))
        // The control stays inside the row. Where it stuck out, moving the
        // pointer onto it left the row, which hid it, and it flickered.
        .overlay(alignment: .topTrailing) {
            if showsControl {
                QuickReactions(store: store, message: message) { isPickingReaction = true }
                    .popover(isPresented: $isPickingReaction, arrowEdge: .bottom) {
                        ReactionPicker { emoji in
                            isPickingReaction = false
                            Task { await store.toggleReaction(emoji, on: message) }
                        }
                    }
                    .padding(.top, QuickReactions.inset)
                    .padding(.trailing, QuickReactions.inset)
            }
        }
        .contentShape(Rectangle())
        // After the overlay, so that the pointer over the control counts as over the message.
        .onHover { isHovering = $0 }
        .padding(.top, row.showsHeader ? 7 : 0)
        .padding(.horizontal, -Self.highlightInset)
        .contextMenu {
            Menu("Add Reaction") {
                ForEach(ReactionPicker.quick, id: \.self) { emoji in
                    Button(emoji) { Task { await store.toggleReaction(Emoji(unicode: emoji), on: message) } }
                }
                Divider()
                Button("More…") { isPickingReaction = true }
            }
        }
        // Who reacted is not part of the message. Loaded again when the counts change.
        .task(id: message.emojiReactionSummaries) { await store.loadReactions(on: message) }
    }

    private var showsControl: Bool {
        // Not while GChat is in the background, so that a click that brings
        // it to the front cannot react.
        (isHovering && store.isAppActive) || isPickingReaction
    }

    private func rendered(_ message: Message) -> AttributedString {
        let mentions = message.mentionNames
        return ChatMarkup.render(message.markup) { user in
            mentions[user] ?? store.profile(for: user)?.displayName.map { "@\($0)" }
        }
    }
}

struct PendingRowView: View {
    let store: ChatStore
    let space: String
    let pending: PendingMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Color.clear.frame(width: 32, height: 1)
            VStack(alignment: .leading, spacing: 4) {
                if !pending.text.isEmpty {
                    Text(pending.text)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let file = pending.file {
                    // Faded until Google has it, like the text.
                    FileThumbnail(file: file, maxSize: CGSize(width: 360, height: 270))
                        .opacity(0.6)
                }
                if let error = pending.error {
                    HStack(spacing: 8) {
                        Label("Not sent: \(error)", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Button("Try Again") { Task { await store.retry(pending, in: space) } }
                        Button("Delete") { store.discard(pending, in: space) }
                    }
                    .font(.caption)
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }
}

// MARK: - Reactions

/// The reactions below a message. A click on one adds the same reaction, or
/// removes the signed-in person's own.
struct ReactionBar: View {
    let store: ChatStore
    let message: Message
    let reactions: [ReactionGroup]
    let onAdd: () -> Void
    /// The reaction under the pointer.
    @State private var hovered: String?
    /// The reaction whose names show above it.
    @State private var showsNames: String?
    /// When GChat last came to the front.
    @State private var activatedAt = Date.distantPast

    /// A click that brings the window to the front must not add or remove a
    /// reaction. That click comes within this time of the activation.
    /// allowsWindowActivationEvents(false) did not stop it on these buttons,
    /// and the appearsActive environment value did not change reliably.
    private static let activationGrace: TimeInterval = 0.5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(reactions) { reaction in
                // Over the person's own reaction, a red X in place of the
                // count shows that a click removes it.
                // Not while the window is in the background, where a click
                // only brings it to the front.
                let removes = reaction.isMine && hovered == reaction.id && store.isAppActive
                Button {
                    guard Date().timeIntervalSince(activatedAt) > Self.activationGrace else { return }
                    Task { await store.toggleReaction(reaction.emoji, on: message) }
                } label: {
                    HStack(spacing: 3) {
                        Text(reaction.emoji.label)
                        // The count stays in the layout, so the chip keeps its width.
                        Text(reaction.count, format: .number)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(reaction.isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .opacity(removes ? 0 : 1)
                            .overlay {
                                if removes {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.red)
                                }
                            }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        reaction.isMine ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                        in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(reaction.isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
                    }
                }
                .buttonStyle(.plain)
                // Drawn by the view and not a .help tooltip, which did not
                // show on these buttons.
                .overlay(alignment: .topLeading) {
                    if showsNames == reaction.id {
                        ReactionNames(text: names(reaction))
                    }
                }
                .zIndex(showsNames == reaction.id ? 1 : 0)
                .onHover { inside in
                    if inside {
                        hovered = reaction.id
                    } else if hovered == reaction.id {
                        hovered = nil
                    }
                }
                .accessibilityLabel("\(reaction.emoji.label) \(reaction.count): \(names(reaction))")
            }
            Button {
                guard Date().timeIntervalSince(activatedAt) > Self.activationGrace else { return }
                onAdd()
            } label: {
                Image(systemName: "face.smiling")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .help("Add Reaction")
        }
        .arrowCursor()
        .onChange(of: store.isAppActive) { _, isActive in
            if isActive { activatedAt = Date() }
        }
        // The names show after a short pause on a reaction, like a tooltip.
        .task(id: hovered) {
            showsNames = nil
            guard let hovered else { return }
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { showsNames = hovered }
        }
        .padding(.top, 2)
    }

    private func names(_ reaction: ReactionGroup) -> String {
        guard !reaction.users.isEmpty else { return "\(reaction.count) reacted" }
        return reaction.users
            .map { $0.name == store.me?.user ? "You" : store.name(for: $0) }
            .formatted(.list(type: .and))
    }
}

/// The names of the people who added a reaction, above it.
struct ReactionNames: View {
    let text: String
    @State private var height: CGFloat = 0

    /// The space between the label and the reaction.
    private static let gap: CGFloat = 6

    var body: some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.separator) }
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            // The widest it gets. A shorter text keeps its own width.
            .frame(width: 280, alignment: .leading)
            // From the top of the reaction to clear above it, so that it
            // does not cover the reaction.
            .offset(y: -(height + Self.gap))
            .allowsHitTesting(false)
    }
}

/// The control that shows while the pointer is over a message: common
/// reactions, and a button for the rest.
struct QuickReactions: View {
    let store: ChatStore
    let message: Message
    let onMore: () -> Void

    /// Fits inside the row of a one-line message, about 22 points tall, with
    /// the same space above as at the side.
    static let height: CGFloat = 18
    static let inset: CGFloat = 2

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ReactionPicker.quick.prefix(5), id: \.self) { emoji in
                Button {
                    Task { await store.toggleReaction(Emoji(unicode: emoji), on: message) }
                } label: {
                    Text(emoji)
                        .font(.system(size: 12))
                        .frame(width: 24, height: QuickReactions.height)
                }
                .buttonStyle(.plain)
                .help("React with \(emoji)")
            }
            Divider().frame(height: 12)
            Button(action: onMore) {
                Image(systemName: "face.smiling")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: QuickReactions.height)
            }
            .buttonStyle(.plain)
            .help("More Reactions")
        }
        .padding(.horizontal, 3)
        // Solid, so that it stands apart from the highlight of the message.
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator) }
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .arrowCursor()
    }
}

extension View {
    /// Shows the arrow over a control. The message text is an NSTextView,
    /// which sets the text cursor, and nothing in SwiftUI sets the arrow
    /// again when the pointer leaves it. So the arrow is set on each move.
    func arrowCursor() -> some View {
        onContinuousHover { phase in
            if case .active = phase { NSCursor.arrow.set() }
        }
    }
}

/// A grid of common emoji, and a field for any other, which takes the emoji
/// picker of macOS.
struct ReactionPicker: View {
    let onPick: (Emoji) -> Void
    @State private var other = ""
    @FocusState private var isFieldFocused: Bool

    static let quick = ["👍", "❤️", "😂", "🎉", "😮", "😢", "🙏", "👀"]
    private static let more = [
        "👎", "👏", "🙌", "💪", "👌", "✌️", "🤞", "👋",
        "😀", "😄", "😁", "😅", "🤣", "😊", "😍", "😘",
        "😎", "🤔", "🙄", "😐", "😕", "😬", "😱", "😭",
        "😡", "🤯", "🥳", "😴", "🤷", "🤦", "🙈", "💀",
        "🔥", "✨", "💯", "✅", "❌", "⚠️", "🚀", "💡",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 2), count: 8), spacing: 2) {
                ForEach(Self.quick + Self.more, id: \.self) { emoji in
                    Button {
                        onPick(Emoji(unicode: emoji))
                    } label: {
                        Text(emoji).font(.title3).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Other emoji", text: $other)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .onChange(of: other) { pick(from: other) }
                    .onSubmit { pick(from: other) }
                Button("All Emoji") {
                    isFieldFocused = true
                    DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
                }
                .help("Emoji & Symbols (Control-Command-Space)")
            }
        }
        .padding(12)
        .frame(width: 270)
    }

    private func pick(from text: String) {
        guard let emoji = EmojiShortcuts.firstEmoji(in: text) else { return }
        other = ""
        onPick(Emoji(unicode: emoji))
    }
}
