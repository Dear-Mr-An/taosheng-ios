import Foundation
import AVFoundation

/// 导入外部录音：分享进来 / 从「文件」里选 / 扫描录音笔文件夹
final class ImportEngine {
    static let shared = ImportEngine()

    private let store = Store.shared

    /// 导入一批音频文件（拷贝进沙盒，转成可转写的 wav 或直接沿用）
    func importFiles(_ urls: [URL]) async -> String {
        var ok = 0
        var failed = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let name = try copyInto(fileURL: url)
                let dest = Store.audioDir.appendingPathComponent(name)
                let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
                let dur = await ImportEngine.duration(of: dest)
                let seg = Segment(
                    id: UUID().uuidString.lowercased(),
                    startedAt: Date(),
                    endedAt: Date(),
                    duration: dur,
                    fileName: name,
                    byteSize: size,
                    transcript: "",
                    speaker: "",
                    state: .recorded,
                    day: DayKey.of(Date()),
                    createdAt: Date()
                )
                _ = store.insert(seg)
                ok += 1
            } catch {
                failed += 1
                NSLog("涛声: 导入失败 \(url.lastPathComponent) — \(error)")
            }
        }
        NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
        await MainActor.run { TranscribeQueue.shared.transcribeNow() }
        if failed == 0 { return "已导入 \(ok) 个文件，正在转写" }
        return "导入 \(ok) 个，失败 \(failed) 个"
    }

    /// 读音频时长（秒），读不到给 0
    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        if let d = try? await asset.load(.duration) {
            let s = CMTimeGetSeconds(d)
            if s.isFinite && s > 0 { return s }
        }
        return 0
    }

    private func copyInto(fileURL: URL) throws -> String {
        let ext = fileURL.pathExtension.lowercased()
        let stamp = Int(Date().timeIntervalSince1970)
        let name = "\(DayKey.of(Date()))-\(stamp)-\(Int.random(in: 100...999)).\(ext.isEmpty ? "m4a" : ext)"
        let dest = Store.audioDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: fileURL, to: dest)
        return name
    }

    /// 扫描用户指定的文件夹，把新录音导入（原文件不动、不重复导入）
    func scanFolder(_ folder: URL) async -> String {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return "读不到这个文件夹"
        }
        let exts: Set<String> = ["m4a", "mp3", "wav", "aac", "caf", "amr", "flac", "ogg"]
        let audio = items.filter { exts.contains($0.pathExtension.lowercased()) }
        guard !audio.isEmpty else { return "文件夹里没有音频文件" }
        return await importFiles(audio)
    }
}
