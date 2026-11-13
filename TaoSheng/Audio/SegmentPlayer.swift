import Foundation
import AVFoundation
import Combine

/// 播放录音（wav）。支持单段来回切，也支持「播放这件事」这种多段连播。
///
/// 采集时音频会话是 .playAndRecord，输出默认走听筒——放录音时会小得像蚊子叫。
/// 所以播放前把输出临时掰到扬声器，停掉再掰回来。
final class SegmentPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = SegmentPlayer()

    @Published private(set) var playingID: String?
    /// 连播队列（点「播放这件事」时一次塞进这一段涉及的所有原话）
    private var queue: [Segment] = []
    private var index = 0
    private var player: AVAudioPlayer?
    private var overrodeOutput = false

    func toggle(segment: Segment) {
        if playingID == segment.id {
            stop()
            return
        }
        queue = []
        index = 0
        start(segment)
    }

    /// 从头连播一组原话
    func playAll(_ segments: [Segment]) {
        guard !segments.isEmpty else { return }
        stop()
        queue = segments
        index = 0
        start(segments[0])
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
        queue = []
        index = 0
        restoreOutput()
    }

    func isPlaying(_ id: String) -> Bool { playingID == id }

    var isPlayingAny: Bool { playingID != nil }

    // MARK: - 内部

    private func start(_ segment: Segment) {
        let url = Store.audioDir.appendingPathComponent(segment.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            playNext()
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            boostOutputIfNeeded()
            p.play()
            player = p
            playingID = segment.id
        } catch {
            NSLog("涛声: 播放失败 \(error)")
            playNext()
        }
    }

    private func playNext() {
        index += 1
        guard index < queue.count else {
            stop()
            return
        }
        start(queue[index])
    }

    /// 听筒输出时临时改到扬声器
    private func boostOutputIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        guard session.category == .playAndRecord else { return }
        let isReceiver = session.currentRoute.outputs.contains { $0.portType == .builtInReceiver }
        guard isReceiver else { return }
        if (try? session.overrideOutputAudioPort(.speaker)) != nil {
            overrodeOutput = true
        }
    }

    private func restoreOutput() {
        guard overrodeOutput else { return }
        overrodeOutput = false
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            if self.queue.isEmpty {
                self.stop()
            } else {
                self.playNext()
            }
        }
    }
}
