import Foundation

/// CAM++ 声纹模型的纯规则：下载、校验、认人阈值、取样窗口。
///
/// 与原版 Android 是同一份 `campplus.onnx`（28 281 138 B，SHA-256 一致），
/// 下载框架沿用 0.8.3 的 SenseVoice：先落 `.part`，校验通过才换进正式目录。
public enum SpeakerModelRules {
    /// 与原版 `src/app/src/main/assets/voiceprint/campplus.onnx` 同一个文件
    public static let modelBytes = 28_281_138
    public static let modelSHA256 = "f682b514c05d947ee3fa91cd6ec6c5c7543479a128373fa29b1faedccd21fd11"

    /// CAM++ 输出的 embedding 维度
    public static let embeddingDim = 192
    /// 没有模型时的本机粗特征（24 维 log-mel 均值 + 标准差）
    public static let fallbackDim = 48

    /// 原版 `VoiceprintThresholds.SURE`：CAM++ 相似度到这个分数才报名字
    public static let camThreshold: Double = 0.65
    /// 48 维粗特征的阈值（比 CAM++ 保守）
    public static let melThreshold: Double = 0.82
    /// 未知说话人聚簇：原版分人用 `FastClusteringConfig(threshold = 0.7)`
    public static let camClusterThreshold: Double = 0.70
    public static let melClusterThreshold: Double = 0.80
    /// 认出一个人还要与第二名拉开这么多（照原版 `SpeakerIdentity.match`）
    public static let margin: Double = 0.08

    /// 一段至少 1.5 秒才取样（原版 `VoiceprintAudio.MIN_SAMPLES` = 24 000）
    public static let minSeconds: Double = 1.5
    /// 每次取 3 秒窗（原版 `SpeakerPrecheck.WINDOW`），整段均匀取最多 8 个
    public static let windowSeconds: Double = 3
    public static let maxWindows = 8

    public static func threshold(forDim dim: Int) -> Double {
        dim == embeddingDim ? camThreshold : melThreshold
    }

    public static func clusterThreshold(forDim dim: Int) -> Double {
        dim == embeddingDim ? camClusterThreshold : melClusterThreshold
    }

    /// 旧样本的维度与当前引擎不一致，就得重算
    public static func needsRebuild(storedDim: Int) -> Bool {
        storedDim != embeddingDim
    }

    // MARK: 取样窗口

    /// 返回每个窗的起始样本下标。整段不足 1.5 秒返回空。
    ///
    /// 窗口贴着结尾均匀铺开：开头常常是静音或音乐，只看前 3 秒容易把噪声当音色。
    public static func windowStarts(totalSamples: Int, sampleRate: Int = 16_000) -> [Int] {
        let minSamples = Int(minSeconds * Double(sampleRate))
        guard totalSamples >= minSamples else { return [] }
        let win = Int(windowSeconds * Double(sampleRate))
        guard totalSamples > win else { return [0] }
        let count = min(maxWindows, max(1, totalSamples / win))
        guard count > 1 else { return [0] }
        return (0..<count).map { i in (totalSamples - win) * i / (count - 1) }
    }

    // MARK: 下载与状态

    public static func isComplete(bytes: Int64) -> Bool {
        bytes == Int64(modelBytes)
    }

    /// 空间不够就别开下：模型之外再留 40 MB
    public static func enoughSpace(free: Int64) -> Bool {
        free > Int64(modelBytes) + 40_000_000
    }

    public static func percent(received: Int64, total: Int64) -> Int {
        guard total > 0 else { return 0 }
        let raw = Double(received) / Double(total) * 100
        return min(100, max(0, Int(raw.rounded(.up))))
    }

    /// 「下载 42% · 12/28 MB」
    public static func progressText(received: Int64, total: Int64) -> String {
        let p = percent(received: received, total: total)
        return "下载 \(p)% · \(mb(received))/\(mb(total)) MB"
    }

    public static func sizeText(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        }
        return "\(mb(bytes)) MB"
    }

    public static func mb(_ bytes: Int64) -> Int {
        Int(max(0, bytes) / 1_000_000)
    }

    public static func phaseText(_ phase: Phase) -> String {
        switch phase {
        case .absent: return "还没下载 · 先用本机 48 维粗特征"
        case .downloading(let received, let total): return progressText(received: received, total: total)
        case .verifying: return "校验文件…"
        case .ready: return "已就绪 · 用 192 维声纹认人"
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
}
