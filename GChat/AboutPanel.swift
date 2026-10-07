import AppKit

/// The standard About window, showing what the app is, the commit it was built
/// from and a link to the source code.
enum AboutPanel {
    static let tagline = "A vibe-coded native Mac application for Google Chat."

    /// Written into the app by the "Record commit" build phase.
    private struct BuildInfo {
        var commit: String
        var commitCount: String
        var commitDate: Date?
        var isDevelopment: Bool
        var buildDate: Date?

        static func load() -> BuildInfo? {
            guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
                  let values = NSDictionary(contentsOf: url) as? [String: String]
            else { return nil }
            let formatter = ISO8601DateFormatter()
            return BuildInfo(
                commit: values["commit"] ?? "unknown",
                commitCount: values["commitCount"] ?? "",
                commitDate: values["commitDate"].flatMap(formatter.date(from:)),
                isDevelopment: values["configuration"] == "Debug",
                buildDate: values["buildDate"].flatMap(formatter.date(from:)))
        }

        /// The first part of the version line.
        var version: String {
            isDevelopment ? "development" : commit
        }

        /// The part in brackets. A release names its commit. A development
        /// build is usually made from code that is not committed, so it gives
        /// the time of the build instead.
        var detail: String {
            if isDevelopment {
                return buildDate.map { "built \(Self.format($0))" } ?? ""
            }
            return commitDate.map { "commit \(commitCount) at \(Self.format($0))" } ?? "commit \(commitCount)"
        }

        /// For example "Oct 7, 2026 12:04 PM".
        private static func format(_ date: Date) -> String {
            let day = date.formatted(.dateTime.month(.abbreviated).day().year())
            let time = date.formatted(.dateTime.hour().minute())
            return "\(day) \(time)"
        }
    }

    @MainActor
    static func show() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacing = 4
        let small: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]
        var regular = small
        regular[.foregroundColor] = NSColor.labelColor

        let credits = NSMutableAttributedString(string: tagline, attributes: regular)
        if let source = Bundle.main.object(forInfoDictionaryKey: "GChatSourceURL") as? String,
           !source.isEmpty, let url = URL(string: source) {
            var link = small
            link[.link] = url
            credits.append(NSAttributedString(string: "\n", attributes: small))
            credits.append(NSAttributedString(string: "Source code", attributes: link))
        }

        // A release shows "Version <commit> (commit <number> at <time>)", a
        // development build "Version development (built <time>)". An empty
        // second string leaves out the brackets.
        let build = BuildInfo.load()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: build?.version ?? "unknown",
            .version: build?.detail ?? "",
            .credits: credits,
        ])
        NSApp.activate()
    }
}
