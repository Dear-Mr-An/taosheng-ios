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

    static func vector(from url: URL) -> [Double]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let length = AVAudioFrameCount(file.length)
        guard length > 0 else { return nil }
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: length) else { return nil }
        do { try file.read(into: buf) } catch { return nil }
        guard let chData = buf.floatChannelData else { return nil }
        let n = Int(buf.frameLength)
        guard n > frameSize else { return nil }
        let sr = file.processingFormat.sampleRate
        let samples = Array(UnsafeBufferPointer(start: chData[0], count: n))
        return vector(from: samples, sampleRate: sr)
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
        return normalize(out)
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
        var best: (String, Double)? = nil
        var grouped: [String: [Double]] = [:]
        for s in samples where s.vector.count == vector.count {
            let score = cosine(vector, s.vector)
            grouped[s.personId, default: []].append(score)
        }
        for (pid, scores) in grouped {
            let avg = scores.reduce(0, +) / Double(scores.count)
            if best == nil || avg > best!.1 {
                best = (pid, avg)
            }
        }
        guard let b = best, b.1 >= threshold else { return nil }
        return (b.0, b.1)
    }
}
