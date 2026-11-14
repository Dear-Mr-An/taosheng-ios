import Foundation
import AVFoundation

/// 把一场会的所有段音频拼成一个文件。
///
/// 为什么要拼：豆包的说话人分离是按「一次请求内的音频」编号的，一段一段送过去，
/// 每段都会从「说话人1」重新开始，根本对不上人。整场送一次才能拿到稳定的标签。
/// 拼接时记下每段在整场里的起点，后面用它把「第几秒说了什么」换算回真实时间。
enum SessionMerger {
    struct Result {
        var url: URL
        /// 段 id → 在整场音频里的起点（秒）
        var offsets: [String: Double]
        var duration: Double
    }

    enum MergeError: LocalizedError {
        case empty
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .empty: return "这场没有可用的录音文件"
            case .exportFailed(let m): return "音频拼接失败：\(m)"
            }
        }
    }

    static func merge(segments: [Segment]) async throws -> Result {
        let usable = segments
            .filter { !$0.fileName.isEmpty }
            .filter { FileManager.default.fileExists(atPath: Store.audioDir.appendingPathComponent($0.fileName).path) }
            .sorted { $0.startedAt < $1.startedAt }
        guard !usable.isEmpty else { throw MergeError.empty }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MergeError.exportFailed("无法创建音轨")
        }

        var cursor = CMTime.zero
        var offsets: [String: Double] = [:]
        for seg in usable {
            let url = Store.audioDir.appendingPathComponent(seg.fileName)
            let asset = AVURLAsset(url: url)
            guard let src = asset.tracks(withMediaType: .audio).first else { continue }
            let range = CMTimeRange(start: .zero, duration: asset.duration)
            do {
                try track.insertTimeRange(range, of: src, at: cursor)
            } catch {
                NSLog("涛声: 拼接跳过 \(seg.fileName) — \(error.localizedDescription)")
                continue
            }
            offsets[seg.id] = cursor.seconds
            cursor = CMTimeAdd(cursor, asset.duration)
        }
        guard cursor.seconds > 0.2 else { throw MergeError.empty }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw MergeError.exportFailed("导出器不可用")
        }
        export.outputURL = out
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(start: .zero, duration: cursor)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        if export.status != .completed {
            throw MergeError.exportFailed(export.error?.localizedDescription ?? "未知原因")
        }
        return Result(url: out, offsets: offsets, duration: cursor.seconds)
    }
}
