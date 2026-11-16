import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// 设置 → 高级与诊断（Android 原版末尾那一组：整理要求、按日统计、守护记录、麦克风占用、导出）
struct RsAdvancedPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @State private var days: [(String, Int, Int)] = []
    @State private var exportURL: URL?
    @State private var exportNote: String?

    private var route: String {
        let s = AVAudioSession.sharedInstance()
        let name = s.currentRoute.inputs.first?.portName ?? "没有输入"
        let rate = s.sampleRate > 0 ? " · \(Int(s.sampleRate / 1000)) kHz" : ""
        let ch = s.inputNumberOfChannels > 0 ? " · \(s.inputNumberOfChannels) 声道" : ""
        return name + rate + ch
    }

    private var micPermission: String {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return "已允许"
        case .denied: return "已拒绝"
        default: return "还没问过"
        }
    }

    var body: some View {
        RsSubPage(title: "高级与诊断") {
            RsGroup(title: "整理要求") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("写在这里的话会拼进整理提示词，每次整理都照它执行。")
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $settings.digestRequirement)
                        .font(.system(size: 15))
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Rs.fill))
                }
                .padding(16)
            }

            RsGroup(title: "按日统计") {
                if days.isEmpty {
                    Text("还没有数据。录过音、整理过，这里就会出现每天的数字。")
                        .font(Rs.subhead)
                        .foregroundStyle(Rs.text2)
                        .padding(16)
                } else {
                    ForEach(days, id: \.0) { row in
                        HStack {
                            Text(row.0).font(Rs.body).foregroundStyle(Rs.text)
                            Spacer(minLength: 8)
                            Text("\(row.1) 段 · \(row.2) 件").font(.system(size: 13)).foregroundStyle(Rs.text3)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                    }
                }
            }

            RsGroup(title: "守护记录") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(capture.isRunning ? "正在收音" : "收音已停")
                        .font(Rs.body)
                        .foregroundStyle(Rs.text)
                    if let at = capture.startedAt {
                        Text("这次从 \(Fmt.monthDayTime.string(from: at)) 开始")
                            .font(.system(size: 13))
                            .foregroundStyle(Rs.text3)
                    }
                    Text("今天中断 \(UserDefaults.standard.integer(forKey: "rsBreaksToday")) 次")
                        .font(.system(size: 13))
                        .foregroundStyle(Rs.text3)
                    Text("中断指录音被来电、别的应用占用麦克风打断。")
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                }
                .padding(16)
            }

            RsGroup(title: "麦克风占用") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(route).font(Rs.body).foregroundStyle(Rs.text)
                    Text("权限：\(micPermission)").font(.system(size: 13)).foregroundStyle(Rs.text3)
                    Text("别的应用占着麦克风时，这里会显示它的输入名称，不是「手机麦克风」。")
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                }
                .padding(16)
            }

            RsGroup(title: "导出") {
                VStack(alignment: .leading, spacing: 8) {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Text("导出诊断记录")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Rs.accent)
                        }
                    } else {
                        RsBtn(text: "生成诊断记录") {
                            exportURL = writeReport()
                        }
                    }
                    if let exportNote {
                        Text(exportNote).font(Rs.caption).foregroundStyle(Rs.text3)
                    }
                }
                .padding(16)
            }
        }
        .task { loadStats() }
    }

    private func loadStats() {
        var out: [(String, Int, Int)] = []
        for offset in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let day = DayKey.of(date)
            let segs = Store.shared.segments(day: day, limit: 2000)
            // 按日「件数」取整理表（memory_item），不再读旧的 item 表
            let items = Store.shared.items(day: day, status: nil, category: nil, limit: 2000)
            if segs.isEmpty && items.isEmpty { continue }
            out.append((offset == 0 ? "今天" : offset == 1 ? "昨天" : Fmt.df("M月d日").string(from: date),
                        segs.count, items.count))
        }
        days = out
    }

    private func writeReport() -> URL? {
        var text = "# 涛声诊断记录\n\n"
        text += "版本：\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")"
        text += " (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"))\n"
        text += "时间：\(Fmt.monthDayTime.string(from: Date()))\n"
        text += "录音：\(capture.isRunning ? "在跑" : "停着")；输入：\(route)；权限：\(micPermission)\n"
        text += "ASR：\(settings.asrKind.title)；就绪：\(settings.asrReady ? "是" : "否")\n"
        text += "整理：\(settings.digestTiming.title)；间隔：\(settings.digestIntervalMin) 分钟\n"
        text += "待转写：\(TranscribeQueue.shared.pendingCount) 段\n\n按日：\n"
        for row in days { text += "- \(row.0)：\(row.1) 段 / \(row.2) 件\n" }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("taosheng-report.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportNote = "已生成 \(url.lastPathComponent)，点上面的链接分享出去。"
            return url
        } catch {
            exportNote = "生成失败：\(error.localizedDescription)"
            return nil
        }
    }
}