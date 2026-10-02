import GChatKit
import SwiftUI

/// ⌘K: type part of a name, pick with the arrow keys, Return to open.
struct QuickSwitcher: View {
    let store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    private var results: [Space] {
        let matches = query.isEmpty
            ? store.spaces
            : store.spaces.filter { store.title(for: $0).localizedCaseInsensitiveContains(query) }
        return Array(matches.prefix(10))
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Jump to a conversation", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { pick(results) }
                    .onKeyPress(.downArrow) {
                        highlighted = min(highlighted + 1, max(results.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        highlighted = max(highlighted - 1, 0)
                        return .handled
                    }
            }
            .font(.title3)
            .padding(14)

            Divider()

            VStack(spacing: 2) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, space in
                    SpaceRow(store: store, space: space)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            index == highlighted ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            highlighted = index
                            pick(results)
                        }
                }
                if results.isEmpty {
                    Text("No matches")
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .padding(8)
        }
        .frame(width: 440)
        .onAppear { isFocused = true }
        .onChange(of: query) { highlighted = 0 }
        .onExitCommand { dismiss() }
    }

    private func pick(_ results: [Space]) {
        guard results.indices.contains(highlighted) else { return }
        store.selection = results[highlighted].name
        dismiss()
    }
}
