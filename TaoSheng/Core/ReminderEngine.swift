import Foundation
import UserNotifications

/// 像闹钟一样的待办强提醒：本地通知 + 时间敏感级别 + 稍后提醒
final class ReminderEngine {
    static let shared = ReminderEngine()

    private init() {}

    func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 权限被拒时调用方要提示「去设置里打开」，否则提醒静默失效，用户以为 App 坏了
    func authDenied(_ done: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { done(s.authorizationStatus == .denied) }
        }
    }

    /// 清掉所有涛声排的本地通知（清空数据 / 退出登录时用）
    func cancelAllPending() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map { $0.identifier }.filter { $0.hasPrefix("ts-") }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
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

        // 一次性提醒如果时间已经过去，排上去会被系统立刻触发一次「该做了」，
        // 用户看到的是莫名其妙的过期提醒。
        if !r.repeatDaily, r.fireAt <= Date() { return }

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
        let center = UNUserNotificationCenter.current()
        // 只清手动提醒那批：ts-quick-（整理自动排的）和 ts-daily-（回顾/打卡）不能被连带删掉
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map { $0.identifier }.filter { $0.hasPrefix("ts-reminder-") }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
            for r in list { self.schedule(r) }
        }
    }

    /// App 启动时把「整理出来、带明确时间」的待办提醒重新排一遍。
    /// quick 提醒不落 reminder 表，重启后系统里那条通知还在，但换机/重装会丢，这里补一次。
    func rescheduleQuick(_ items: [(id: String, title: String, due: Date)]) {
        for it in items {
            guard let fire = ReminderTime.resolve(due: it.due) else { continue }
            scheduleQuick(id: it.id, title: it.title, at: fire)
        }
    }

    /// 整理出「有明确时间」的待办时顺手排一条，不写 reminder 表
    /// （避免和手动添加的提醒重复，取消也不会互相影响）
    func scheduleQuick(id: String, title: String, at date: Date) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "涛声 · 该做了"
        content.body = title
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        content.userInfo = ["quick": id]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: "ts-quick-\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func cancelQuick(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ts-quick-\(id)"])
    }

}
