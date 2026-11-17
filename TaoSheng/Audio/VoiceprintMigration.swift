import Foundation

/// 从 48 维粗特征换成 CAM++ 192 维之后，旧样本维度对不上，
/// `Voiceprint.match` 会直接跳过——认人不会崩，但人物库等于空的。
/// 模型就绪时就地从原录音重算一遍，用户不用重新指认每个人。
enum VoiceprintMigration {
    private static let lock = NSLock()
    private static var running = false

    /// 幂等：已全是 192 维时什么都不做；不同维度混着时只重算旧的那些。
    static func rebuildIfNeeded() {
        guard SpeakerModelStore.readyOnDisk else { return }
        lock.lock()
        if running {
            lock.unlock()
            return
        }
        running = true
        lock.unlock()

        DispatchQueue.global(qos: .utility).async {
            defer {
                lock.lock()
                running = false
                lock.unlock()
            }
            let samples = Store.shared.allVoiceSamples()
            var rebuilt = 0
            var dropped = 0
            for s in samples where SpeakerModelRules.needsRebuild(storedDim: s.vector.count) {
                // 用户中途点了「删除模型」：再算下去会拿不到 192 维，
                // 万一回落到 48 维写进库，就把旧样本又变成了不可比的一条。
                guard SpeakerModelStore.readyOnDisk else { break }
                guard let seg = Store.shared.segment(id: s.segmentId) else {
                    // 对应的录音记录已经不在了，这条样本没有重算的可能，直接删掉，
                    // 不然每次进设置页都会重试一遍，人物卡的样本数也是虚的。
                    Store.shared.deleteVoiceSample(id: s.id)
                    dropped += 1
                    continue
                }
                let url = Store.audioDir.appendingPathComponent(seg.fileName)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    Store.shared.deleteVoiceSample(id: s.id)
                    dropped += 1
                    continue
                }
                // 模型仍在磁盘上才重算：`Voiceprint.vector` 在模型为空时会走 48 维口径。
                guard SpeakerModelStore.readyOnDisk, let v = Voiceprint.vector(from: url) else {
                    Store.shared.deleteVoiceSample(id: s.id)
                    dropped += 1
                    continue
                }
                Store.shared.insertVoiceSample(VoiceSample(
                    id: s.id,
                    personId: s.personId,
                    segmentId: s.segmentId,
                    vector: v,
                    createdAt: s.createdAt
                ))
                rebuilt += 1
            }
            if SpeakerModelStore.readyOnDisk {
                Store.shared.clearStaleClusters(keepingDim: SpeakerModelRules.embeddingDim)
            }
            if rebuilt > 0 || dropped > 0 {
                NSLog("涛声: CAM++ 重算声纹样本 \(rebuilt) 条，删除不可重算的 \(dropped) 条")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
                }
            }
        }
    }
}
