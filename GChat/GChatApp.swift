import GChatKit
import SwiftUI

@main
struct GChatApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("GChat", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            AppCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Conversations") {
            Button("Jump to…") { model.isQuickSwitcherShown = true }
                .keyboardShortcut("k")
                .disabled(model.store == nil)
            Button("Refresh") {
                Task { await model.store?.refresh() }
            }
            .keyboardShortcut("r")
            .disabled(model.store == nil)

            if let store = model.store {
                Divider()
                ForEach(Array(store.spaces.prefix(9).enumerated()), id: \.element.id) { index, space in
                    Button(store.title(for: space)) { store.selection = space.name }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let store = model.store {
            MainView(store: store)
        } else {
            SignInView()
        }
    }
}
