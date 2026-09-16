import Foundation
import UIKit
import UserNotifications

final class PushService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushService()

    var onToken: ((String) -> Void)?
    /// Called on remote wake / notification tap. Returns number of newly unread messages.
    var onRemoteWake: (() async -> Int)?

    private static let privacyCategory = "AESMS_PRIVACY_MAIL"

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Privacy-safe local notification: title only, no sender or body text.
    static func postPrivacyNewMailNotification(badge: Int) {
        let content = UNMutableNotificationContent()
        content.title = "AeSMS"
        content.body = "New message"
        content.sound = .default
        content.badge = NSNumber(value: badge)
        content.categoryIdentifier = privacyCategory
        let req = UNNotificationRequest(
            identifier: "aesms.privacy.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // App open: update badge only; in-app LIVE/fetch covers awareness.
        completionHandler([.badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task {
            _ = await onRemoteWake?()
            completionHandler()
        }
    }
}

extension PushService {
    static func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        shared.onToken?(hex)
    }

    static func handleRemoteNotification(
        userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let aps = userInfo["aps"] as? [String: Any]
        let hasAlert = aps?["alert"] != nil
        Task {
            let n = await shared.onRemoteWake?() ?? 0
            // Silent/content-available wakes: ensure Notification Center still gets a privacy banner.
            if n > 0 && !hasAlert {
                await MainActor.run {
                    let badge = UIApplication.shared.applicationIconBadgeNumber
                    postPrivacyNewMailNotification(badge: max(badge, 1))
                }
            }
            completionHandler(n > 0 ? .newData : .noData)
        }
    }
}
