import Foundation

/// 整理窗口的两条真实规则（以前只在提示词里插一行分隔，等于没生效）：
/// 1) 「停多久算说完了」：距最后一段结束至少 idle 分钟、且没有还没转写的段，才整理；
/// 2) 「一直在说，最多等多久」：一次整理最多带 cap 分钟的材料，超出的留到下一轮。
public enum DigestWindow {
    public static func ready(lastEnd: Date?, now: Date, idleMin: Int, pendingSegments: Int) -> Bool {
        guard pendingSegments <= 0 else { return false }
        guard let lastEnd else { return true }
        let idle = Double(max(1, idleMin)) * 60
        return now.timeIntervalSince(lastEnd) >= idle
    }

    /// 从第一条开始、cap 分钟之内能带上的条数（至少 1 条，避免超长单段被永久卡住）
    public static func headCount(starts: [Date], capMin: Int) -> Int {
        guard let first = starts.first else { return 0 }
        let cap = Double(max(1, capMin)) * 60
        var n = 0
        for t in starts {
            if t.timeIntervalSince(first) <= cap { n += 1 } else { break }
        }
        return max(1, n)
    }
}