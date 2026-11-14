import Foundation

/// 长会议切块与跨块说话人对号（纯逻辑，可单测）。
///
/// 豆包极速版单次请求有音频时长/文件大小上限（官方文档：录音文件识别极速版，单次不超过 2 小时、
/// 100MB，链接见 README 0.6.1 章节）。董事长的会经常开一个多小时，整场一次送上去会直接失败，
/// 所以超过上限 80% 就按顺序切块识别，最后在本地把各块的说话人对上号。
public enum ChunkRules {
    /// 官方上限（秒）与文件大小（字节）。没有真机密钥验证过实际边界，取官方值再打 8 折。
    public static let flashMaxSeconds: Double = 7200
    public static let flashMaxBytes: Double = 100 * 1024 * 1024
    /// 每块不超过上限的 80%
    public static let safeRatio: Double = 0.8

    /// 是否需要切块
    public static func needsChunking(bytes: Double, seconds: Double) -> Bool {
        bytes > flashMaxBytes * safeRatio || seconds > flashMaxSeconds * safeRatio
    }

    /// 按段时长切块，返回每块包含的段下标（保持顺序，不跨块重排）。
    /// 单段就超上限时独占一块——总比整场失败好，日志里也看得见是哪一段超了。
    public static func chunks(segmentDurations: [Double], limit: Double = flashMaxSeconds * safeRatio) -> [[Int]] {
        guard !segmentDurations.isEmpty else { return [] }
        var out: [[Int]] = []
        var current: [Int] = []
        var acc = 0.0
        for (i, d) in segmentDurations.enumerated() {
            let dur = max(0, d)
            if !current.isEmpty, acc + dur > limit {
                out.append(current)
                current = []
                acc = 0
            }
            current.append(i)
            acc += dur
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// 余弦相似度；任一向量为零向量时返回 0
    public static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// 一块里某个说话人的声纹参考
    public struct SpeakerRef: Equatable {
        public var chunk: Int
        public var label: String
        public var vector: [Double]

        public init(chunk: Int, label: String, vector: [Double]) {
            self.chunk = chunk
            self.label = label
            self.vector = vector
        }
    }

    /// 跨块对号：按块顺序、块内首次出现顺序遍历，跟已有簇的中心比余弦，够像就并进这个簇，
    /// 不够像就新开一个说话人。返回 ["块号|标签": "说话人N"]。
    public static func mergeSpeakers(_ refs: [SpeakerRef], threshold: Double = 0.75) -> [String: String] {
        var centers: [[Double]] = []
        var out: [String: String] = [:]
        for r in refs {
            var best = -1
            var bestScore = -1.0
            for (i, c) in centers.enumerated() {
                let s = cosine(c, r.vector)
                if s > bestScore { bestScore = s; best = i }
            }
            if best >= 0, bestScore >= threshold {
                out["\(r.chunk)|\(r.label)"] = SpeakerRules.display(best)
                // 中心随样本微调，长会里口音漂移也能跟上
                if centers[best].count == r.vector.count {
                    let n = 0.8
                    for i in 0..<centers[best].count {
                        centers[best][i] = centers[best][i] * n + r.vector[i] * (1 - n)
                    }
                }
            } else {
                centers.append(r.vector)
                out["\(r.chunk)|\(r.label)"] = SpeakerRules.display(centers.count - 1)
            }
        }
        return out
    }
}
