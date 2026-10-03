import AppKit

/// The standard About window, showing the commit the app was built from,
/// the build number, the build date and a link to the source code.
enum AboutPanel {
    @MainActor
    static func show() {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            guard let value = info[key] as? String, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
            return value
        }

        var lines: [NSAttributedString] = []
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]
        if let date = value("GChatBuildDate") {
            lines.append(NSAttributedString(string: "Built \(date)", attributes: attributes))
        }
        if let source = value("GChatSourceURL"), let url = URL(string: source) {
            var link = attributes
            link[.link] = url
            lines.append(NSAttributedString(string: "Source code", attributes: link))
        }
        let credits = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { credits.append(NSAttributedString(string: "\n", attributes: attributes)) }
            credits.append(line)
        }

        // Shown as "Version <commit> (<build>)".
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: value("GChatCommit") ?? "development",
            .version: value("CFBundleVersion") ?? "",
            .credits: credits,
        ])
        NSApp.activate()
    }
}
