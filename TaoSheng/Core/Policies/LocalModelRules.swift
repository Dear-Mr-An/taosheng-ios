import Foundation

/// 本地语音模型的纯规则：进度、容量、校验、状态文案。
///
/// Android 原版是「下载 SenseVoice 压缩包 → 解包 → 校验 SHA-256 → 换进去」，
/// iOS 这边改成直接下两个文件（模型 + tokens），少一层解包，校验的哈希与字节数
/// 和原版 `LocalModels.cpu` 完全一致，这样同一个模型两边认得是同一个东西。
public enum LocalModelRules {
    /// 与 Android `LocalModels.cpu.modelBytes` 一致
    public static let modelBytes = 239_233_841
    /// 与 Android `LocalModels.cpu.modelHash` 一致（model.int8.onnx 的 SHA-256）
    public static let modelSHA256 = "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"
    /// tokens.txt 原版只校验「非空且小于 1 MB」
    public static let tokensRange: ClosedRange<Int64> = 1...1_000_000

    /// 下载百分比（0…100，向上取整，避免一直显示 0%）
    public static func percent(received: Int64, total: Int64) -> Int {
        guard total > 0 else { return 0 }
        let raw = Double(received) / Double(total) * 100
        return min(100, max(0, Int(raw.rounded(.up))))
    }

    /// 「下载 42% · 68/228 MB」
    public static func progressText(received: Int64, total: Int64) -> String {
        let p = percent(received: received, total: total)
        return "下载 \(p)% · \(mb(received))/\(mb(total)) MB"
    }

    /// 228 MB / 1.2 GB
    public static func sizeText(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        }
        return "\(mb(bytes)) MB"
    }

    public static func mb(_ bytes: Int64) -> Int {
        Int(max(0, bytes) / 1_000_000)
    }

    /// 两个文件都在、字节数对：可以先当「已就绪」用（哈希只在下载完成时算一次）
    public static func isComplete(modelBytes: Int64, tokensBytes: Int64) -> Bool {
        modelBytes == Int64(LocalModelRules.modelBytes) && tokensRange.contains(tokensBytes)
    }

    /// 断点续传：本地已有一部分、且比目标小，就从那里接着下
    public static func resumeOffset(existing: Int64, total: Int64) -> Int64 {
        guard existing > 0, existing < total else { return 0 }
        return existing
    }

    /// 下载/校验阶段的状态文案
    public static func phaseText(_ phase: Phase) -> String {
        switch phase {
        case .absent: return "还没下载"
        case .downloading(let received, let total): return progressText(received: received, total: total)
        case .verifying: return "校验文件…"
        case .ready: return "已就绪 · 离网也能转写"
        case .failed(let reason): return "没下完：\(reason)"
        }
    }

    public enum Phase: Equatable {
        case absent
        case downloading(received: Int64, total: Int64)
        case verifying
        case ready
        case failed(String)
    }

    /// 大小不够时先告诉用户，不要下到一半才失败
    public static func enoughSpace(free: Int64) -> Bool {
        free > Int64(modelBytes) + 40_000_000
    }
}
