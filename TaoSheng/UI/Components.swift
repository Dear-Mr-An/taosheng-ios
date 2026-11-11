import SwiftUI
import UIKit

// MARK: - 键盘状态
/// 全局键盘可见性。用于：键盘弹出时收起底部 TabBar、让输入栏贴住键盘。
final class KeyboardObserver: ObservableObject {
    static let shared = KeyboardObserver()

    @Published private(set) var isVisible = false
    /// 键盘高度（含安全区），键盘不可见时为 0。
    @Published private(set) var height: CGFloat = 0

    private var tokens: [NSObjectProtocol] = []

    private init() {
        let c = NotificationCenter.default
        tokens.append(c.addObserver(forName: UIResponder.keyboardWillShowNotification,
                                   object: nil, queue: .main) { [weak self] n in
            let f = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            self?.isVisible = true
            self?.height = f?.height ?? 0
        })
        tokens.append(c.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                   object: nil, queue: .main) { [weak self] _ in
            self?.isVisible = false
            self?.height = 0
        })
    }
}

// MARK: - 录音波形
struct LevelBars: View {
    var level: Double
    var count: Int = 26
    var color: Color = Theme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.09)) { _ in
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<count, id: \.self) { i in
                    let base = 3.0 + Double((i * 37) % 11)
                    let amp = max(0.08, level)
                    let h = min(26.0, base * (0.5 + amp * 9.0) * (0.6 + 0.4 * sin(Double(i))))
                    Capsule()
                        .fill(color.opacity(level > 0.02 ? 0.85 : 0.25))
                        .frame(width: 3, height: max(3, h))
                }
            }
            .frame(height: 28)
        }
    }
}

// MARK: - 说话人色点
struct SpeakerDot: View {
    let name: String
    var size: CGFloat = 6

    private var color: Color {
        if name.isEmpty { return Theme.dim2 }
        if name == "我" { return Theme.accent }
        let idx = abs(name.hashValue) % personPalette.count
        let rgb = hexToRGB(personPalette[idx])
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

// MARK: - 原话一行
struct SegmentRow: View {
    let seg: Segment
    var onPlay: () -> Void = {}
    var onStar: () -> Void = {}
    var onAssign: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var playing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 3) {
                Text(seg.timeText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.dim)
                Text(seg.durationText)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim2)
            }
            .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    SpeakerDot(name: seg.speaker)
                    Text(seg.speaker.isEmpty ? "未识别" : seg.speaker)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(seg.speaker.isEmpty ? Theme.dim2 : Theme.text2)
                    if seg.state != .transcribed {
                        Pill(text: seg.state == .failed ? "转写失败" : "待转写",
                             color: seg.state == .failed ? Theme.bad : Theme.warn)
                    }
                    Spacer()
                }
                Text(seg.isEmptySpeech ? "（这段没有识别出文字）" : seg.transcript)
                    .font(.system(size: 14))
                    .foregroundStyle(seg.isEmptySpeech ? Theme.dim2 : Theme.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            Button { onPlay() } label: { Label("播放", systemImage: "play") }
            Button { onStar() } label: { Label("标为重点", systemImage: "star") }
            Button { onAssign() } label: { Label("这是谁", systemImage: "person.crop.circle.badge.questionmark") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("删除", systemImage: "trash") }
        }
    }
}

// MARK: - 时间线事件行
struct EventRow: View {
    let item: DigestItem
    var onToggle: () -> Void = {}

    private var dotColor: Color {
        switch item.kind {
        case .event: return Theme.blue
        case .todo: return Theme.accent
        case .promise: return Theme.purple
        case .idea: return Theme.warn
        case .memory: return Theme.ok
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle().fill(dotColor).frame(width: 7, height: 7).padding(.top, 6)
                Rectangle().fill(Theme.line).frame(width: 1).frame(maxHeight: .infinity)
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.kind.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(dotColor)
                    if !item.due.isEmpty {
                        Text(item.due)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim2)
                    }
                    Spacer()
                    if item.kind == .todo || item.kind == .promise {
                        Button(action: onToggle) {
                            Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17))
                                .foregroundStyle(item.status == .done ? Theme.ok : Theme.dim2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(item.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(item.status == .done ? Theme.dim2 : Theme.text)
                    .strikethrough(item.status == .done, color: Theme.dim2)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.dim)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 12)
        }
    }
}

// MARK: - 统计小格
struct StatCell: View {
    let value: String
    let label: String
    var color: Color = Theme.text

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 设置行
struct SettingRow: View {
    let icon: String
    let title: String
    var detail: String = ""
    var tint: Color = Theme.accent
    var chevron: Bool = true

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5)).foregroundStyle(Theme.text)
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim2)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - 开关行
struct ToggleRow: View {
    let title: String
    var detail: String = ""
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5)).foregroundStyle(Theme.text)
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.accent)
        .padding(.vertical, 6)
    }
}

// MARK: - 筛选 chip
struct Chip: View {
    let text: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Theme.accent : Theme.card)
                .foregroundStyle(selected ? Color.white : Theme.text2)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(selected ? Color.clear : Theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 页面标题
struct PageTitle: View {
    let title: String
    var subtitle: String = ""
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.dim)
                }
            }
            Spacer()
            if let t = trailing { t }
        }
    }
}

// MARK: - 分享面板
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
