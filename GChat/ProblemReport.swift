import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// A report for the developer: what the person writes, the versions, and the
/// log lines of GChat since it was started. GChat sends it nowhere. The
/// person reads it and then saves, shares or copies it (docs/design.md).
enum ProblemReport {
    static let subsystem = "org.themullers.gchat"
    /// A long session can log many lines. The newest ones matter.
    private static let lineLimit = 5000

    /// The versions of GChat and macOS, and when GChat was started.
    static func header() -> String {
        var build: [String: String] = [:]
        if let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
           let values = NSDictionary(contentsOf: url) as? [String: String] {
            build = values
        }
        let info = ProcessInfo.processInfo
        let organization = Bundle.main.object(forInfoDictionaryKey: "GChatOrganization") as? String ?? ""
        return [
            "GChat problem report, \(Date().formatted(.iso8601))",
            "GChat: commit \(build["commit"] ?? "unknown"), version \(build["commitCount"] ?? "unknown"), "
                + "\(build["configuration"] ?? "unknown") build"
                + (organization.isEmpty ? "" : ", for \(organization)"),
            "macOS: \(info.operatingSystemVersionString)",
            "GChat started: \(processStart?.formatted(.iso8601) ?? "unknown")",
        ].joined(separator: "\n")
    }

    /// When this process started, from the kernel.
    private static let processStart: Date? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }()

    /// The log lines that GChat wrote in this run. macOS lets a sandboxed app
    /// read only the lines of its own running process, so earlier runs are
    /// not available.
    static func logLines() async -> String {
        await Task.detached(priority: .userInitiated) {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
                let time = Date.FormatStyle(date: .omitted, time: .standard).secondFraction(.fractional(3))
                var lines: [String] = []
                for case let entry as OSLogEntryLog in entries {
                    lines.append("\(entry.date.formatted(time)) \(name(of: entry.level)) "
                        + "\(entry.category): \(entry.composedMessage)")
                }
                if lines.isEmpty { return "(GChat wrote no log lines since it was started)" }
                if lines.count > lineLimit {
                    return "(the first \(lines.count - lineLimit) lines were left out)\n"
                        + lines.suffix(lineLimit).joined(separator: "\n")
                }
                return lines.joined(separator: "\n")
            } catch {
                return "(GChat could not read its log: \(error.localizedDescription))"
            }
        }.value
    }

    private static func name(of level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "other"
        }
    }

    static func compose(notes: String, header: String, log: String) -> String {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
            \(header)

            What happened:
            \(notes.isEmpty ? "(nothing written)" : notes)

            Log:
            \(log)

            """
    }

    static var fileName: String {
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "GChat report \(stamp).txt"
    }
}

/// The report as a file for the share sheet. The file is written when a
/// sharing service asks for it.
struct ProblemReportFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { report in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(ProblemReport.fileName)
            try report.text.write(to: file, atomically: true, encoding: .utf8)
            return SentTransferredFile(file)
        }
    }
}

struct ProblemReportView: View {
    @State private var notes = ""
    @State private var log: String?
    private let header = ProblemReport.header()

    private var report: String {
        ProblemReport.compose(notes: notes, header: header, log: log ?? "(reading the log)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("""
                This report is for the developer of GChat. It contains:
                  •  what you write below
                  •  the versions of GChat and macOS
                  •  GChat's log since it was started: times, error messages, the ID numbers of people \
                and conversations, and the names of Chat apps

                It does not contain message text, names of people, your password or your sign-in.

                Nothing is sent. Read the report below, then save, share or copy it yourself.
                """)
                .fixedSize(horizontal: false, vertical: true)

            Text("What happened?").font(.headline)
            TextEditor(text: $notes)
                .font(.body)
                .frame(height: 70)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator) }

            Text("The report").font(.headline)
            ReportText(text: report)
                .frame(minHeight: 180)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator) }

            HStack {
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                ShareLink(item: ProblemReportFile(text: report), preview: SharePreview("GChat report")) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                Button("Save…") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(log == nil)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 520)
        .task { log = await ProblemReport.logLines() }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ProblemReport.fileName
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// The report in a text view that scrolls and selects, and cannot be edited.
/// A SwiftUI Text is slow with thousands of lines.
private struct ReportText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false
            view.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            view.textContainerInset = NSSize(width: 4, height: 6)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
    }
}

@MainActor
enum ProblemReportPanel {
    private static var window: NSWindow?

    /// Each time, a new window with the log up to now.
    static func show() {
        window?.close()
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        panel.title = "Report a Problem"
        panel.contentView = NSHostingView(rootView: ProblemReportView())
        panel.isReleasedWhenClosed = false
        panel.center()
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
