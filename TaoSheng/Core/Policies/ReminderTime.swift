import Foundation

/// 待办提醒时间。
///
/// 只有日期、没有钟点的待办（due 落在当天 00:00，例如「今天完成」「明天交」），
/// 提醒放在当天 09:00；如果 9 点已经过了，就顺延到次日 09:00。
///
/// 关键顺序：**先算出真正的提醒时间，再判断有没有过期**。
/// 直接拿 00:00 去和「创建时间」比，会把上午新增的当日待办判成过期，
/// 后面「改成 9 点提醒」那一步根本没机会执行，提醒就被吞掉了。
enum ReminderTime {
    static let defaultHour = 9

    static func resolve(due: Date, now: Date = Date()) -> Date? {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: due)
        let dateOnly = (comps.hour ?? 0) == 0 && (comps.minute ?? 0) == 0

        var target = due
        if dateOnly {
            target = cal.date(bySettingHour: defaultHour, minute: 0, second: 0, of: due) ?? due
        }
        if target > now { return target }

        // 带钟点的已经过去：不再补提醒
        guard dateOnly else { return nil }
        // 只有日期的：顺延到明天同一时刻（已经是对齐好的 9 点）
        return cal.date(byAdding: .day, value: 1, to: target)
    }
}
