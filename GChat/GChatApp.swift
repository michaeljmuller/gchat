import GChatKit
import SwiftUI

@main
struct GChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var updater: Updater

    init() {
        // Before AppModel, which connects to Google and the relay.
        Self.yieldToRunningCopy()
        _model = State(initialValue: AppModel())
        _updater = State(initialValue: Updater())
    }

    /// The Debug build and the release have the same bundle ID, and macOS
    /// lets two copies at different paths run together. Each would then post
    /// its own notifications. The copy that is already running stays; this
    /// one brings it to the front and quits.
    private static func yieldToRunningCopy() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0 != .current }
        guard let other = others.first else { return }
        other.activate()
        exit(0)
    }

    var body: some Scene {
        Window("GChat", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            AppCommands(model: model, updater: updater)
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(updater)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// By default the app keeps running without a window, so notifications
    /// still arrive. The setting makes closing the window quit the app.
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProblemReport.logVersions()
        AttachmentFiles.prune()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        UserDefaults.standard.bool(forKey: AppSettings.quitOnCloseKey)
    }
}

struct AppCommands: Commands {
    let model: AppModel
    let updater: Updater

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About GChat") { AboutPanel.show() }
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            Button("Release Notes") { ReleaseNotesPanel.show() }
                .disabled(!ReleaseNotesPanel.isAvailable)
        }
        // GChat has no help book, so the standard Help item leads nowhere.
        CommandGroup(replacing: .help) {
            Button("Report a Problem…") { ProblemReportPanel.show() }
        }
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
