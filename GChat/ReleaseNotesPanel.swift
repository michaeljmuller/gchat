import AppKit
import WebKit

/// A window with the release notes of this version and the earlier ones. The
/// page is inside the app, so the window needs no network. A release gets the
/// page from scripts/release.sh. Other builds have none.
@MainActor
enum ReleaseNotesPanel {
    private static var window: NSWindow?

    private static var page: URL? {
        Bundle.main.url(forResource: "ReleaseNotes", withExtension: "html")
    }

    static var isAvailable: Bool { page != nil }

    static func show() {
        if window == nil, let page, let notes = try? String(contentsOf: page, encoding: .utf8) {
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 420))
            // The page is a fragment without a head, so name the encoding here.
            view.loadHTMLString("<meta charset=\"utf-8\">" + notes, baseURL: nil)

            let panel = NSWindow(
                contentRect: view.frame,
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            panel.title = "Release Notes"
            panel.contentView = view
            panel.contentMinSize = NSSize(width: 320, height: 200)
            panel.isReleasedWhenClosed = false
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
