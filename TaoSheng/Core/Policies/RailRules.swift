import Foundation

/// 右侧小时刻度的几何（纯逻辑，可单测）。
///
/// 抄的是原版安卓 `HourIndex.kt` 的算法：每个小时占的高度按事件数分，少于最小高度就抬到最小高度，
/// 其余按比例收缩——这样「事件很少」时刻度不会拉满整屏，最后几个小时也不会挤在一起。
public struct RailSlot: Equatable {
    public var hour: Int
    /// 这个小时里有几件事
    public var count: Int
    /// 这个小时第一件事在扁平列表里的下标
    public var start: Int
    /// 这个小时第一件事的 key（跳转用）
    public var firstKey: String

    public init(hour: Int, count: Int, start: Int, firstKey: String) {
        self.hour = hour
        self.count = count
        self.start = start
        self.firstKey = firstKey
    }
}

public enum RailRules {
    /// 只保留有事件的小时，按时间正序。`entries` 必须已经按显示顺序排好。
    public static func slots(_ entries: [(key: String, hour: Int)]) -> [RailSlot] {
        var out: [RailSlot] = []
        for (i, e) in entries.enumerated() {
            if let last = out.last, last.hour == e.hour {
                out[out.count - 1].count += 1
            } else {
                out.append(RailSlot(hour: e.hour, count: 1, start: i, firstKey: e.key))
            }
        }
        return out
    }

    /// 刻度总高：事件少的时候不拉满整屏
    public static func railHeight(slotCount: Int, entryCount: Int, available: Double, minSlot: Double = 24) -> Double {
        guard slotCount > 0 else { return 0 }
        let natural = max(Double(slotCount) * minSlot, Double(entryCount) * minSlot * 0.8)
        return min(available, natural)
    }

    /// 各小时高度：先按事件数比例分，低于最小高度的抬到最小高度，剩下的按比例收缩
    public static func heights(counts: [Int], total: Double, minSlot: Double = 24) -> [Double] {
        let sum = max(1, counts.reduce(0, +))
        let raw = counts.map { Double($0) / Double(sum) * total }
        let smallCount = raw.filter { $0 < minSlot }.count
        let rest = max(0, total - Double(smallCount) * minSlot)
        let bigSum = max(1, raw.filter { $0 >= minSlot }.reduce(0, +))
        return raw.map { $0 < minSlot ? minSlot : $0 / bigSum * rest }
    }

    /// 每个小时的顶边
    public static func tops(_ heights: [Double]) -> [Double] {
        var out: [Double] = []
        var acc = 0.0
        for h in heights {
            out.append(acc)
            acc += h
        }
        return out
    }

    /// 某个 y 落在第几个小时
    public static func slot(at y: Double, tops: [Double]) -> Int {
        guard !tops.isEmpty else { return 0 }
        var idx = 0
        for (i, t) in tops.enumerated() where t <= y { idx = i }
        return min(max(0, idx), tops.count - 1)
    }

    /// y 落在该小时的第几件事（连续拖动时用，不吸附到整点）
    public static func entryOffset(at y: Double, slot: Int, tops: [Double], heights: [Double], count: Int, snap: Bool) -> Int {
        guard slot >= 0, slot < tops.count, slot < heights.count, count > 0 else { return 0 }
        let h = max(1, heights[slot])
        let frac = min(0.999, max(0, (y - tops[slot]) / h))
        if snap { return 0 }
        return min(count - 1, Int(frac * Double(count)))
    }

    /// 第 index 件事在刻度上的 y（滑块与气泡定位）
    public static func y(ofIndex index: Int, slots: [RailSlot], tops: [Double], heights: [Double]) -> Double {
        guard !slots.isEmpty, index >= 0 else { return 0 }
        var s = 0
        for (i, slot) in slots.enumerated() where slot.start <= index { s = i }
        let n = max(1, slots[s].count)
        let within = Double(index - slots[s].start) + 0.5
        let h = s < heights.count ? heights[s] : 0
        let t = s < tops.count ? tops[s] : 0
        return t + h * (within / Double(n))
    }
}
