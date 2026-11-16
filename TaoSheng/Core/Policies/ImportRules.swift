import Foundation

/// 文件夹导入的去重与结果判定。
/// 以前只记 `lastPathComponent`，不同子目录里的同名录音会被误判成「已导入」；
/// 现在用「文件名 + 字节数 + 修改时间」做键，同名不同内容也能各导一次。
public enum ImportRules {
    public static func key(name: String, size: Int, modifiedEpoch: Int) -> String {
        "\(name)|\(size)|\(modifiedEpoch)"
    }

    public static func shouldImport(key: String, seen: Set<String>) -> Bool {
        !key.isEmpty && !seen.contains(key)
    }

    /// 批量结果文案：成功 N 个、失败 M 个（失败要能看见文件名，便于下次重试）
    public static func summary(added: Int, failedNames: [String]) -> String {
        if failedNames.isEmpty {
            return added > 0 ? "导入 \(added) 段，已排队转写" : "没有导入任何文件"
        }
        let head = "导入 \(added) 段，\(failedNames.count) 个失败"
        return head + "：" + failedNames.prefix(3).joined(separator: "、")
    }
}