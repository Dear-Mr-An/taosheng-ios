import SwiftUI

// MARK: - 一段录音的行
struct SegmentRow: View {
    let segment: Segment
    @ObservedObject private var player = SegmentPlayer.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(segment.timeText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(segment.durationText)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }
            .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                if segment.state == .transcribed {
                    if segment.isEmptySpeech {
                        Text("（这一段没识别出人声）")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim.opacity(0.7))
                    } else {
                        Text(segment.transcript)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.text)
                            .lineSpacing(3)
                    }
                } else if segment.state == .failed {
                    Text("转写失败，稍后自动重试")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.bad.opacity(0.9))
                } else {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                        Text("等待转写 · \(Int(segment.duration))秒")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                player.toggle(segment: segment)
            } label: {
                Image(systemName: player.playingID == segment.id ? "stop.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.accentSoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 整理条目行
struct ItemRow: View {
    let item: DigestItem
    var onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(item.status == .done ? Theme.ok : Theme.dim)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: item.kind == .todo ? .medium : .regular))
                    .foregroundStyle(item.status == .done ? Theme.dim : Theme.text)
                    .strikethrough(item.status == .done, color: Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.detail.isEmpty && item.kind != .event {
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                if !item.due.isEmpty {
                    Text(item.due)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.warn)
                }
                if item.kind == .event && !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }
}

// MARK: - 波形
struct LevelBars: View {
    let level: Double
    let active: Bool
    private let count = 26

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !active)) { _ in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    let seed = Double((i * 37) % 11) / 11.0
                    let base = active ? max(0.06, level * (0.45 + seed * 0.9)) : 0.05
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(active ? Theme.accent.opacity(0.85) : Theme.dim.opacity(0.35))
                        .frame(width: 3, height: max(3, base * 46))
                }
            }
            .frame(height: 46)
        }
    }
}
