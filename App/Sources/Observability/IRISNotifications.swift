import Foundation
import UserNotifications

/// v1.44 — Wrapper UserNotifications pour push natives macOS.
/// Used par EventBusBridge sur signalEmitted importance critical (si toggle Settings on).
public enum IRISNotifications {
    private static let enabledKey = "iris.notifications.enabled"

    /// Settings toggle persisté UserDefaults.
    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Request authorization auprès de macOS. À appeler quand user toggle on.
    public static func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            return granted
        } catch {
            return false
        }
    }

    /// Check authorization status courant sans request.
    public static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    /// Push une notification. Skip silencieusement si !isEnabled ou autorization pas granted.
    public static func push(title: String, body: String, identifier: String = UUID().uuidString) async {
        guard isEnabled else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // immediate
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
