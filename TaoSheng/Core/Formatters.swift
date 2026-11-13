import Foundation

/// 复用的日期格式化器。
///
/// `DateFormatter()` 的创建成本很高，列表里每行、每帧都新建会明显拖慢主线程；
/// 这里按格式串缓存，格式建好后不再修改，因此在 iOS 7+ 上可安全跨线程读取。
enum Fmt {
    private static let lock = NSLock()
    private static var cache: [String: DateFormatter] = [:]

    static func df(_ format: String) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let f = cache[format] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        cache[format] = f
        return f
    }

    /// 12:05
    static let hm = df("HH:mm")
    /// 11月13日
    static let monthDay = df("M月d日")
    /// 11月13日 12:05
    static let monthDayTime = df("M月d日 HH:mm")
    /// 周四
    static let weekday = df("EEEE")
    /// 2026年11月13日
    static let fullDay = df("yyyy年M月d日")

    /// 把任意标题变成安全的文件名（去掉路径分隔符与保留字符）。
    static func safeFileName(_ raw: String, fallback: String = "涛声") -> String {
        let banned = CharacterSet(charactersIn: "/\\:?%*|\"<>#\n\r\t")
        let cleaned = raw
            .components(separatedBy: banned)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return fallback }
        return String(cleaned.prefix(40))
    }
}
