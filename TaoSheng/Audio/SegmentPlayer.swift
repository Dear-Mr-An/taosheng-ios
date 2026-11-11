import Foundation
import AVFoundation
import Combine

/// 播放某一段录音（wav）
final class SegmentPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = SegmentPlayer()

    @Published private(set) var playingID: String?
    private var player: AVAudioPlayer?

    func toggle(segment: Segment) {
        if playingID == segment.id {
            stop()
            return
        }
        stop()
        let url = Store.audioDir.appendingPathComponent(segment.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            playingID = segment.id
        } catch {
            NSLog("涛声: 播放失败 \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.playingID = nil
            self.player = nil
        }
    }
}
