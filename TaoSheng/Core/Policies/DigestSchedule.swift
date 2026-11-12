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
}
