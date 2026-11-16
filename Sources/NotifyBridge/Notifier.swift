import Foundation
import UserNotifications

struct NotificationMessage {
    var title: String
    var subtitle: String?
    var message: String
    var sound: Bool = true
}

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("Notification authorization error: \(error.localizedDescription)")
            } else if !granted {
                NSLog("Notification permission was not granted")
            }
        }
    }

    /// Posts the notification. `completion` receives nil on success or a human-readable error.
    func post(_ message: NotificationMessage, completion: @escaping (String?) -> Void) {
        center.getNotificationSettings { [center] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                break
            default:
                completion("notifications are not allowed for NotifyBridge; enable them in System Settings > Notifications")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = message.title
            if let subtitle = message.subtitle { content.subtitle = subtitle }
            content.body = message.message
            if message.sound { content.sound = .default }

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request) { error in
                completion(error?.localizedDescription)
            }
        }
    }

    /// Reports how macOS is currently configured to deliver this app's notifications.
    func deliverySettings(completion: @escaping ([String: String]) -> Void) {
        center.getNotificationSettings { settings in
            func name(_ setting: UNNotificationSetting) -> String {
                switch setting {
                case .enabled: return "enabled"
                case .disabled: return "disabled"
                case .notSupported: return "notSupported"
                @unknown default: return "unknown"
                }
            }
            let authorization: String
            switch settings.authorizationStatus {
            case .authorized: authorization = "authorized"
            case .provisional: authorization = "provisional"
            case .denied: authorization = "denied"
            case .notDetermined: authorization = "notDetermined"
            @unknown default: authorization = "unknown"
            }
            let style: String
            switch settings.alertStyle {
            case .none: style = "none"
            case .banner: style = "banner"
            case .alert: style = "alert"
            @unknown default: style = "unknown"
            }
            completion([
                "authorization": authorization,
                "alertStyle": style,
                "alerts": name(settings.alertSetting),
                "sound": name(settings.soundSetting),
                "notificationCenter": name(settings.notificationCenterSetting),
            ])
        }
    }

    // Show banners even if the system considers this app to be frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
