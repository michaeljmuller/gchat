import GChatKit
import SwiftUI

@main
struct GChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// By default the app keeps running without a window, so notifications
    /// still arrive. The setting makes closing the window quit the app.
    func applicationDidFinishLaunching(_ notification: Notification) {
        AttachmentFiles.removeAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AttachmentFiles.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        UserDefaults.standard.bool(forKey: AppSettings.quitOnCloseKey)
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Conversation…") { model.isNewConversationShown = true }
                .keyboardShortcut("n")
                .disabled(model.store == nil)
        }
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
                let recent = store.spaces.filter { !AppSettings.isHidden($0, in: store) }
                ForEach(Array(recent.prefix(9).enumerated()), id: \.element.id) { index, space in
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
