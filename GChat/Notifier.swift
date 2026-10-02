import AppKit
import UserNotifications

/// Posts message notifications and keeps the dock badge current.
@MainActor
final class Notifier {
    /// Called with a space name when its notification is clicked.
    var onOpen: ((String) -> Void)?

    private let delegate = NotificationDelegate()

    init() {
        delegate.onOpen = { [weak self] space in self?.onOpen?(space) }
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// Asks once; macOS remembers the answer. Calls back with whether
    /// notifications are allowed.
    func requestAuthorization(then update: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in update(granted) }
        }
    }

    /// Whether macOS currently lets the app show notifications. Checked again
    /// when the app becomes active, since the user may have changed it in
    /// System Settings.
    func checkAuthorization(then update: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            Task { @MainActor in update(allowed) }
        }
    }

    /// Opens GChat's page in System Settings > Notifications.
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    func post(space: String, title: String, subtitle: String?, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = body
        content.sound = .default
        content.threadIdentifier = space
        content.userInfo = [NotificationDelegate.spaceKey: space]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func setBadge(_ count: Int) {
        NSApp?.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let spaceKey = "space"

    var onOpen: (@MainActor (String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let space = response.notification.request.content.userInfo[Self.spaceKey] as? String
        DispatchQueue.main.async {
            if let space { self.onOpen?(space) }
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
