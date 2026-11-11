import Foundation
import UserNotifications

/// 像闹钟一样的待办强提醒：本地通知 + 时间敏感级别 + 稍后提醒
final class ReminderEngine {
    static let shared = ReminderEngine()

    private init() {}

    func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func schedule(_ r: Reminder) {
        guard r.enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "涛声 · 该做了"
        content.body = r.title
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        content.userInfo = ["reminderId": r.id]

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireAt)
        if r.repeatDaily {
            comps = cal.dateComponents([.hour, .minute], from: r.fireAt)
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: r.repeatDaily)
        let req = UNNotificationRequest(identifier: "ts-reminder-\(r.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ts-reminder-\(id)"])
    }

    func rescheduleAll(_ list: [Reminder]) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for r in list { schedule(r) }
    }

    /// 每日回顾 / 整理完成的轻提醒
    func scheduleDaily(kind: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "ts-daily-\(kind)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
