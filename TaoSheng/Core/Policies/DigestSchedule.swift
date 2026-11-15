import Foundation

enum DigestSchedule {
    static func shouldRun(enabled: Bool, byInterval: Bool, intervalMinutes: Int, hour: Int,
                          now: Date, lastRun: Date?, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        if byInterval {
            guard let last = lastRun else { return true }
            return now.timeIntervalSince(last) >= Double(max(1, intervalMinutes)) * 60
        }
        guard let scheduledAt = calendar.date(bySettingHour: min(23, max(0, hour)), minute: 0,
                                               second: 0, of: now), now >= scheduledAt else { return false }
        return lastRun.map { $0 < scheduledAt } ?? true
    }

    /// 「什么时候整理」三档：第一档（转写完就整理）由转写完成事件驱动，定时器一律不跑，
    /// 否则等于又变回按间隔整理。另外两档和以前完全一样。
    static func shouldRun(enabled: Bool, timing: DigestTiming, intervalMinutes: Int, hour: Int,
                          now: Date, lastRun: Date?, calendar: Calendar = .current) -> Bool {
        switch timing {
        case .afterTranscribe:
            return false
        case .interval:
            return shouldRun(enabled: enabled, byInterval: true, intervalMinutes: intervalMinutes,
                             hour: hour, now: now, lastRun: lastRun, calendar: calendar)
        case .clock:
            return shouldRun(enabled: enabled, byInterval: false, intervalMinutes: intervalMinutes,
                             hour: hour, now: now, lastRun: lastRun, calendar: calendar)
        }
    }
}
