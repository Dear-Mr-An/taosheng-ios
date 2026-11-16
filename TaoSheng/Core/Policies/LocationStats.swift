import Foundation

/// 足迹页的统计：在家 / 外出分钟数、移动距离。
/// 之前这几个数字是写死的 0，页面看着像功能，其实没读数据。
public enum LocationStats {
    public struct Visit: Equatable {
        public var arriveAt: Date
        public var leaveAt: Date
        public var isHome: Bool
        public var latitude: Double
        public var longitude: Double

        public init(arriveAt: Date, leaveAt: Date, isHome: Bool, latitude: Double, longitude: Double) {
            self.arriveAt = arriveAt
            self.leaveAt = leaveAt
            self.isHome = isHome
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public struct Totals: Equatable {
        public var homeMinutes: Int
        public var awayMinutes: Int
        public var kilometers: Double
    }

    public static func totals(_ visits: [Visit]) -> Totals {
        var home = 0.0
        var away = 0.0
        for v in visits {
            let s = max(0, v.leaveAt.timeIntervalSince(v.arriveAt))
            if v.isHome { home += s } else { away += s }
        }
        var meters = 0.0
        let sorted = visits.sorted { $0.arriveAt < $1.arriveAt }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            meters += distance(a.latitude, a.longitude, b.latitude, b.longitude)
        }
        return Totals(homeMinutes: Int(home / 60), awayMinutes: Int(away / 60),
                      kilometers: (meters / 1000 * 10).rounded() / 10)
    }

    /// 两点球面距离（米），Haversine
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}