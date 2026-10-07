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
                placeholder: "Message \(title)",
                onSend: send)
        }
        .navigationTitle(title)
        .task { await store.open(space.name) }
    }

    private func send() {
        let text = model.drafts[space.name] ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.drafts[space.name] = ""
        Task { await store.send(text, to: space.name) }
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
    /// Whether the end of the transcript is in view. New messages scroll into
    /// view only then, so reading older messages is not interrupted.
    @State private var isAtBottom = true
    /// A message arrived while the person was reading further up.
    @State private var hasNewBelow = false

    private static let bottomID = "transcript-bottom"
    /// Space between the last message and the composer.
    private static let bottomSpace: CGFloat = 12
    /// How close to the end counts as being at the bottom.
    private static let bottomTolerance: CGFloat = 40

    /// What the scroll view reports about its position.
    private struct ScrollState: Equatable {
        var contentHeight: CGFloat
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
                ScrollState(
                    contentHeight: geometry.contentSize.height,
                    distanceFromBottom: geometry.contentSize.height + geometry.contentInsets.bottom
                        - geometry.contentOffset.y - geometry.containerSize.height)
            } action: { old, new in
                // Content grew while the end was in view: a new message, or an
                // image that finished loading. Keep the end in view.
                if new.contentHeight > old.contentHeight, old.distanceFromBottom < Self.bottomTolerance,
                   new.distanceFromBottom >= Self.bottomTolerance {
                    scrollToBottom(proxy)
                    return
                }
                isAtBottom = new.distanceFromBottom < Self.bottomTolerance
                if isAtBottom { hasNewBelow = false }
            }
            .onChange(of: transcript.pending.count) { old, new in
                // The person sent a message: always show it.
                if new > old { scrollToBottom(proxy) }
            }
            .onChange(of: transcript.messages.last?.name) {
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

    private static let avatarSize: CGFloat = 32

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
            }
            Spacer(minLength: 0)
        }
        .padding(.top, row.showsHeader ? 10 : 3)
        .help(message.createTime?.formatted(date: .abbreviated, time: .shortened) ?? "")
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
                Text(pending.text)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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
