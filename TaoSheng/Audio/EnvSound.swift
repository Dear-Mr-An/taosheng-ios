import Foundation
import AVFoundation

/// 轻量环境音判断：只对已经录下的人声片段做一次，全部在本地。
/// 不是神经网络分类器，用的是能量 / 过零率 / 高频占比这几个廉价特征，
/// 所以结果只有粗粒度几类，够用来给原话补一句"当时是什么声音"。
enum EnvSound {
    static func analyze(url: URL) -> String? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let frames = AVAudioFrameCount(min(file.length, 16000 * 10))
        guard frames > 1600 else { return nil }
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { return nil }
        do {
            try file.read(into: buf)
        } catch {
            return nil
        }
        guard let ch = buf.floatChannelData?[0] else { return nil }
        let n = Int(buf.frameLength)
        guard n > 1600 else { return nil }

        var sum: Double = 0
        var zc = 0
        var prev: Float = ch[0]
        for i in 0..<n {
            let v = ch[i]
            sum += Double(v * v)
            if (v >= 0) != (prev >= 0) { zc += 1 }
            prev = v
        }
        let rms = (sum / Double(n)).squareRoot()
        let zcr = Double(zc) / Double(n)

        // 一阶差分当作高频能量的粗略估计
        var diff: Double = 0
        for i in 1..<n {
            let d = Double(ch[i] - ch[i - 1])
            diff += d * d
        }
        let hf = (diff / Double(max(n - 1, 1))).squareRoot()
        let hfRatio = hf / max(rms, 1e-9)

        if rms < 0.004 { return "安静" }
        if hfRatio > 0.9 && zcr > 0.15 { return "键盘" }
        if rms > 0.10 && hfRatio < 0.30 { return "音乐" }
        if hfRatio > 0.60 && zcr > 0.10 { return "环境噪音" }
        if zcr > 0.02 && zcr < 0.10 { return "人声" }
        if hfRatio > 0.42 { return "家电" }
        return "环境音"
    }
}
