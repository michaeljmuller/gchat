import AppKit

/// The standard About window, showing what the app is, the commit it was built
/// from, the build number, the build date and a link to the source code.
enum AboutPanel {
    static let tagline = "A vibe-coded native Mac application for Google Chat."

    @MainActor
    static func show() {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            guard let value = info[key] as? String, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
            return value
        }

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

        var lines = [NSAttributedString(string: tagline, attributes: regular)]
        if let date = value("GChatBuildDate") {
            lines.append(NSAttributedString(string: "Built \(date)", attributes: small))
        }
        if let source = value("GChatSourceURL"), let url = URL(string: source) {
            var link = small
            link[.link] = url
            lines.append(NSAttributedString(string: "Source code", attributes: link))
        }
        let credits = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { credits.append(NSAttributedString(string: "\n", attributes: small)) }
            credits.append(line)
        }

        // A release shows "Version <commit> (<build>)". A development build has
        // no commit or build number of its own, so it shows "Version development"
        // only: an empty build string leaves out the brackets.
        let commit = value("GChatCommit")
        let isRelease = commit != nil && commit != "development"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: commit ?? "development",
            .version: isRelease ? (value("CFBundleVersion") ?? "") : "",
            .credits: credits,
        ])
        NSApp.activate()
    }
}
