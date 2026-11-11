import Foundation
import Combine
import SwiftUI

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var todaySegments: [Segment] = []
    @Published var days: [String] = []
    @Published var todayItems: [DigestItem] = []
    @Published var openItems: [DigestItem] = []
    @Published var todaySummary: String = ""
    @Published var stats: (segments: Int, transcribed: Int, pending: Int, seconds: Double) = (0, 0, 0, 0)

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .taoshengDataChanged, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func refresh() {
        let day = DayKey.of(Date())
        todaySegments = Store.shared.segments(day: day, limit: 800).sorted { $0.startedAt < $1.startedAt }
        days = Store.shared.dayKeys(limit: 90)
        todayItems = Store.shared.items(day: day)
        openItems = Store.shared.items(openOnly: true)
        todaySummary = Store.shared.digest(day: day)?.summary ?? ""
        stats = Store.shared.todayStats()
        TranscribeQueue.shared.refreshPending()
    }

    func toggleItem(_ item: DigestItem) {
        Store.shared.toggleItem(id: item.id)
        refresh()
    }

    // MARK: - 音频清理

    /// 保留最近 N 天的原音（转写完成的才删，未转写的留着）
    func purgeOldAudio() {
        let keep = Settings.shared.keepAudioDays
        let cutoff = Calendar.current.date(byAdding: .day, value: -keep, to: Date()) ?? Date()
        let old = Store.shared.segments(limit: 5000).filter { $0.startedAt < cutoff }
        for s in old where s.state == .transcribed {
            Store.shared.deleteSegment(id: s.id, removeFile: true)
        }
        refresh()
    }

    // MARK: - 导出

    func exportMarkdown(day: String) -> String {
        let segs = Store.shared.segments(day: day, limit: 800).sorted { $0.startedAt < $1.startedAt }
        var out = "# 涛声 · \(DayKey.display(day))\n\n"
        if let d = Store.shared.digest(day: day), !d.summary.isEmpty {
            out += "> \(d.summary)\n\n"
        }
        let items = Store.shared.items(day: day)
        if !items.isEmpty {
            out += "## 整理\n\n"
            for i in items {
                let box = i.status == .done ? "x" : " "
                out += "- [\(box)] **\(i.kind.title)** \(i.title)"
                if !i.due.isEmpty { out += "（\(i.due)）" }
                out += "\n"
            }
            out += "\n"
        }
        out += "## 原话\n\n"
        for s in segs where !s.isEmptySpeech {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            out += "**\(f.string(from: s.startedAt))** \(s.transcript)\n\n"
        }
        return out
    }
}
