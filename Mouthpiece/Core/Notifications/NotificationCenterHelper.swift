import Foundation
import UserNotifications
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "Notify")

/// 简单包装系统通知。失败静默忽略——通知不是核心路径。
@MainActor
enum NotificationCenterHelper {

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    log.error("Notification auth failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    log.notice("Notification auth granted=\(granted)")
                }
            }
        }
    }

    /// Show a transient banner. Caller decides whether to gate by settings.
    static func showTranscriptionDone(text: String) {
        let content = UNMutableNotificationContent()
        content.title = "嘴替"
        content.body = "已粘贴：\(text.prefix(60))"
        content.sound = nil  // 我们已经有 floating bar 视觉反馈
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { err in
            if let err {
                log.error("notify failed: \(err.localizedDescription, privacy: .public)")
            }
        }
    }

    static func showError(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "嘴替出错了"
        content.body = message
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { _ in }
    }
}
