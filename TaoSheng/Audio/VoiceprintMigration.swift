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
            var unrecoverable = 0
            for s in samples where SpeakerModelRules.needsRebuild(storedDim: s.vector.count) {
                guard let seg = Store.shared.segment(id: s.segmentId) else {
                    unrecoverable += 1
                    continue
                }
                let url = Store.audioDir.appendingPathComponent(seg.fileName)
                guard let v = Voiceprint.vector(from: url) else {
                    // 原录音已删或太短：这条样本就此作废，不能拿旧维度硬留着
                    unrecoverable += 1
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
            Store.shared.clearStaleClusters(keepingDim: SpeakerModelRules.embeddingDim)
            if rebuilt > 0 || unrecoverable > 0 {
                NSLog("涛声: CAM++ 重算声纹样本 \(rebuilt) 条，跳过 \(unrecoverable) 条")
            }
            if rebuilt > 0 {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
                }
            }
        }
    }
}
