import Foundation
import AVFoundation
import Accelerate

/// 本机声纹：24 维 log-mel 均值 + 标准差 = 48 维向量，余弦相似度认人。
/// 比不上云端 CAM++，但纯本机、不出设备、够分出「我 / 熟人 / 陌生人」。
enum Voiceprint {

    static let frameSize = 512
    static let hopSize = 256
    static let melBands = 24
    static let threshold: Double = 0.82

    // MARK: - 提取

    /// 抽查窗长（秒）。整段开头可能是静音或音乐，只看前 60 秒容易把「噪声」当音色；
    /// 照原版 SpeakerPrecheck 的做法，在整段里均匀取几处，各算一次再平均。
    static let windowSeconds: Double = 4
    static let maxWindows = 8

    static func vector(from url: URL) -> [Double]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sr = file.processingFormat.sampleRate
        let total = file.length
        guard total > 0 else { return nil }
        let win = AVAudioFramePosition(max(1, sr * windowSeconds))
        let usable = min(win, total)
        // 文件太短（不足一个窗）就按整段算
        let count = total < win * 2 ? 1 : min(maxWindows, Int(total / win))
        var picked: [[Double]] = []
        for i in 0..<count {
            // 均匀铺开：最后一块贴着结尾，避免越界
            let start = count == 1 ? 0 : (total - usable) * AVAudioFramePosition(i) / AVAudioFramePosition(count - 1)
            file.framePosition = start
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(usable)) else { continue }
            do { try file.read(into: buf) } catch { continue }
            guard let chData = buf.floatChannelData else { continue }
            let n = Int(buf.frameLength)
            guard n > frameSize else { continue }
            let samples = Array(UnsafeBufferPointer(start: chData[0], count: n))
            if let v = vector(from: samples, sampleRate: sr) { picked.append(v) }
        }
        guard !picked.isEmpty else { return nil }
        guard picked.count > 1 else { return picked[0] }
        // 先各自归一化再取平均，最后再归一化一次：各窗音量不同也不影响方向
        var avg = [Double](repeating: 0, count: picked[0].count)
        for v in picked where v.count == avg.count {
            for i in 0..<avg.count { avg[i] += v[i] }
        }
        let k = Double(picked.count)
        avg = avg.map { $0 / k }
        let out = normalize(avg)
        return out.allSatisfy { $0.isFinite } ? out : nil
    }

    static func vector(from samples: [Float], sampleRate sr: Double) -> [Double]? {
        let n = samples.count
        guard n > frameSize else { return nil }

        let log2n = vDSP_Length(log2(Double(frameSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))

        let bins = frameSize / 2
        let filters = melFilterbank(bands: melBands, bins: bins, sampleRate: sr, fftSize: frameSize)

        var sum = [Double](repeating: 0, count: melBands)
        var sumSq = [Double](repeating: 0, count: melBands)
        var frames = 0

        var offset = 0
        var windowed = [Float](repeating: 0, count: frameSize)
        var real = [Float](repeating: 0, count: bins)
        var imag = [Float](repeating: 0, count: bins)
        var mags = [Float](repeating: 0, count: bins)

        while offset + frameSize <= n {
            samples.withUnsafeBufferPointer { sp in
                vDSP_vmul(sp.baseAddress! + offset, 1, window, 1, &windowed, 1, vDSP_Length(frameSize))
            }

            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    windowed.withUnsafeBufferPointer { wp in
                        wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: bins) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(bins))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(bins))
                }
            }

            for b in 0..<melBands {
                var e: Double = 0
                let w = filters[b]
                for k in 0..<bins {
                    let ww = w[k]
                    if ww > 0 {
                        let m = Double(mags[k])
                        e += m * m * ww
                    }
                }
                let v = log(max(e, 1e-8))
                sum[b] += v
                sumSq[b] += v * v
            }
            frames += 1
            offset += hopSize
        }

        guard frames > 4 else { return nil }
        let fd = Double(frames)
        var out = [Double](repeating: 0, count: melBands * 2)
        for b in 0..<melBands {
            let mean = sum[b] / fd
            let variance = max(sumSq[b] / fd - mean * mean, 0)
            out[b] = mean
            out[melBands + b] = sqrt(variance)
        }
        let normalized = normalize(out)
        // 录音里如果有异常采样导致出现 NaN/Inf，宁可不认人，也不要写进数据库
        return normalized.allSatisfy { $0.isFinite } ? normalized : nil
    }

    static func normalize(_ v: [Double]) -> [Double] {
        var mean = 0.0
        for x in v { mean += x }
        mean /= Double(max(v.count, 1))
        var varSum = 0.0
        for x in v { varSum += (x - mean) * (x - mean) }
        let sd = sqrt(varSum / Double(max(v.count, 1))) + 1e-8
        return v.map { ($0 - mean) / sd }
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let d = sqrt(na) * sqrt(nb)
        return d > 0 ? dot / d : 0
    }

    // MARK: - mel 三角滤波器

    static func melFilterbank(bands: Int, bins: Int, sampleRate: Double, fftSize: Int) -> [[Double]] {
        func hzToMel(_ hz: Double) -> Double { 2595.0 * log10(1.0 + hz / 700.0) }
        func melToHz(_ mel: Double) -> Double { 700.0 * (pow(10.0, mel / 2595.0) - 1.0) }

        let maxHz = sampleRate / 2.0
        let melMax = hzToMel(maxHz)
        let melMin = hzToMel(60.0)
        var points: [Double] = []
        for i in 0...(bands + 1) {
            let m = melMin + (melMax - melMin) * Double(i) / Double(bands + 1)
            points.append(melToHz(m))
        }
        let binHz = sampleRate / Double(fftSize)
        var out: [[Double]] = []
        for b in 0..<bands {
            var w = [Double](repeating: 0, count: bins)
            let left = points[b]
            let center = points[b + 1]
            let right = points[b + 2]
            for k in 0..<bins {
                let f = Double(k) * binHz
                if f > left && f <= center && center > left {
                    w[k] = (f - left) / (center - left)
                } else if f > center && f < right && right > center {
                    w[k] = (right - f) / (right - center)
                }
            }
            out.append(w)
        }
        return out
    }

    // MARK: - 认人

    /// 用已登记的样本找最像的人
    static func match(_ vector: [Double], samples: [VoiceSample]) -> (personId: String, score: Double)? {
        var grouped: [String: [Double]] = [:]
        for s in samples where s.vector.count == vector.count {
            grouped[s.personId, default: []].append(cosine(vector, s.vector))
        }
        let averages = grouped.map { (id: $0.key, score: $0.value.reduce(0, +) / Double($0.value.count)) }
        // 阈值 + 与第二名的差距，两条都过才算认出来（照 SpeakerIdentity.match）
        guard let hit = SpeakerRules.bestName(averages, threshold: threshold) else { return nil }
        return (hit.id, hit.score)
    }
}
