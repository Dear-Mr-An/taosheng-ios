import Foundation
import SwiftUI

/// 只给 CI 截图用的开关。
///
/// 带 `-TSShot <screen>` 启动时，App 会直接跳到指定画面并灌一小份演示数据，
/// 这样模拟器截图可以稳定复现「待办空态 / 设置滚到底 / 弹窗输入框」这些现场，
/// 不带这个参数时行为与正常启动完全一致。
enum ShotMode {
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-TSShot"), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        return v.isEmpty ? nil : v
    }

    static var active: Bool { screen != nil }

    /// 各画面落在哪个 Tab 上
    static func tab(for screen: String) -> Int? {
        switch screen {
        case "today", "event-edit", "today-live", "today-done", "event-meeting", "speaker-rename",
             "today-hero", "today-justended", "today-timeline-asc", "timeline-rail", "timeline-meeting",
             "today-timeline-parts", "event-summary", "event-raw", "event-speakers":
            return 0
        case "ask": return 1
        case "memory", "memory-filter-meeting", "memory-cards", "memory-week", "memory-timeline-rail",
             "card-sheet-top", "card-sheet-bottom", "review-meetings":
            return 2
        case "todo", "todo-pending": return 3
        case "recording-bottom", "person-add", "transcribe", "llm", "llm-interval": return 4
        default: return nil
        }
    }
}

/// 截图用的演示数据：只写内存里那几张表，不产生任何音频文件。
enum ShotDemo {
    static let eventID = "shot-event-1"
    static let meetingSessionID = "shot-session-meeting"
    static let liveSessionID = "shot-session-live"

    static var today: String { DayKey.of(Date()) }

    static func seedIfNeeded() {
        guard ShotMode.active else { return }
        let day = today
        let now = Date()

        if Store.shared.events(day: day, limit: 1).isEmpty {
            Store.shared.upsertEvent(MemoryEvent(
                id: eventID,
                day: day,
                startAt: now.addingTimeInterval(-3600),
                endAt: now.addingTimeInterval(-600),
                scene: "会议",
                title: "和周工确认交付时间",
                summary: "下周三之前把接口联调完，周五一起去客户现场。",
                points: ["接口文档今晚发过去", "周五上午十点出发"],
                people: ["我", "周工"],
                place: "会议室",
                emotion: "平静",
                intensity: 3,
                important: true,
                starred: false,
                starredAt: nil,
                entityId: "shot-entity-1",
                lineFrom: 1,
                lineTo: 2,
                createdAt: now,
                sessionId: meetingSessionID))
        }

        if Store.shared.items(day: day, status: nil, category: nil, limit: 1).isEmpty {
            Store.shared.insertItems([
                MemoryItem(id: "shot-item-1", eventId: eventID, day: day, category: "待办",
                           kind: "我要做", content: "把接口文档发给周工", status: .pending,
                           dueText: "今晚 8 点", dueAt: now.addingTimeInterval(3600),
                           who: "我", sourceText: nil, createdAt: now, updatedAt: now),
                MemoryItem(id: "shot-item-2", eventId: eventID, day: day, category: "约定",
                           kind: "我答应别人", content: "周五上午十点出发去客户现场", status: .accepted,
                           dueText: nil, dueAt: nil, who: "周工", sourceText: nil,
                           createdAt: now, updatedAt: now),
                MemoryItem(id: "shot-item-3", eventId: eventID, day: day, category: "备忘",
                           kind: nil, content: "客户换到新地址，进门找前台登记", status: .pending,
                           dueText: nil, dueAt: nil, who: nil, sourceText: nil,
                           createdAt: now, updatedAt: now)
            ])
        }
    }

    /// 「转写与原话」截图用：造 8 段今天的原话，验证卡片只列 3 段 + 「看全部 8 段」。
    static func seedSegmentsIfNeeded() {
        guard ShotMode.active else { return }
        let day = today
        // 同一台模拟器会被连续启动多次（每个画面一次），必须按固定 id 判重；
        // 用 count 判重会漏（limit 只管行数），结果每启一次就多插 8 段。
        let existing = Set(Store.shared.segments(day: day, limit: 999).map(\.id))
        if existing.contains("shot-seg-1") { return }
        let lines: [(String, String)] = [
            ("我", "早上先把接口文档过了一遍，字段名统一成下划线风格。"),
            ("周工", "下周三之前要联调完，前端这边今天就能给你一版。"),
            ("我", "好，那我明天把网关的白名单配上。"),
            ("周工", "客户那边换到新园区了，进门要找前台登记。"),
            ("我", "周五上午十点出发，路上大概四十分钟。"),
            ("周工", "记得把演示用的账号提前开好。"),
            ("我", "另外结算那块先按老流程走，不要动。"),
            ("周工", "行，我下午把改动清单发群里。")
        ]
        let base = Date().addingTimeInterval(-Double(lines.count) * 300)
        for (i, line) in lines.enumerated() {
            if existing.contains("shot-seg-\(i + 1)") { continue }
            let start = base.addingTimeInterval(Double(i) * 300)
            let seg = Segment(id: "shot-seg-\(i + 1)",
                              startedAt: start,
                              endedAt: start.addingTimeInterval(14),
                              duration: 14,
                              fileName: "",
                              byteSize: 0,
                              transcript: line.1,
                              speaker: line.0,
                              state: .transcribed,
                              day: day,
                              createdAt: start,
                              captureModeRaw: CaptureMode.meeting.rawValue,
                              starred: false)
            _ = Store.shared.insert(seg)
        }
    }
    /// 截图用：一场已经结束、3 个说话人的会议；today-live 再额外造一场正在录的会话。
    /// 只写库、不产生音频，所以模拟器上不会真的去请求识别接口。
    static func seedSessionsIfNeeded() {
        guard let screen = ShotMode.screen else { return }
        let day = today
        let now = Date()

        if Store.shared.session(id: meetingSessionID) == nil {
            let started = now.addingTimeInterval(-3600)
            let s = ListenSession(id: meetingSessionID,
                                  modeRaw: CaptureMode.meeting.rawValue,
                                  startedAt: started,
                                  endedAt: started.addingTimeInterval(1200),
                                  stateRaw: SessionState.done.rawValue,
                                  speakersJSON: "{\"说话人2\":\"周工\"}",
                                  eventId: eventID,
                                  error: nil)
            Store.shared.insertSession(s)
            let texts: [(String, Double, String)] = [
                ("说话人1", 0, "今天主要两件事：接口联调时间和周五去现场的安排。"),
                ("说话人2", 34, "我这边周三之前能把接口文档整理完，前端今天先给一版。"),
                ("说话人1", 92, "好，那我明天把网关白名单配上，顺便把演示账号开好。"),
                ("说话人3", 150, "客户那边换到新园区了，进门要找前台登记，我提前报备。"),
                ("说话人2", 214, "行，那我下午把改动清单发群里，周五上午十点出发。")
            ]
            let utts = texts.enumerated().map { i, t in
                Utterance(id: "shot-utt-\(i + 1)", sessionId: meetingSessionID,
                          speaker: t.0, start: t.1, end: t.1 + 28, text: t.2, orderIndex: i)
            }
            Store.shared.replaceUtterances(sessionId: meetingSessionID, utts)
        }

        // 同一台模拟器会按顺序拍好几张，上一张留下的「正在录」的会话会一直挂在
        // 英雄卡上（latestSession 就是它）。除了 today-live，其它画面先把它清掉，
        // 让最新会话回到那场已结束的会议。段表直接删，避免 deleteSegment 顺带把
        // 当天的整理结果一起清掉。
        if screen != "today-live", Store.shared.session(id: liveSessionID) != nil {
            _ = Store.shared.exec("DELETE FROM utterance WHERE session_id='\(liveSessionID)';")
            _ = Store.shared.exec("DELETE FROM segment WHERE session_id='\(liveSessionID)';")
            Store.shared.deleteSession(id: liveSessionID)
        }

        if screen == "today-live", Store.shared.session(id: liveSessionID) == nil {
            let started = now.addingTimeInterval(-420)
            let s = ListenSession(id: liveSessionID,
                                  modeRaw: CaptureMode.meeting.rawValue,
                                  startedAt: started,
                                  endedAt: nil,
                                  stateRaw: SessionState.recording.rawValue,
                                  speakersJSON: "{}",
                                  eventId: nil,
                                  error: nil)
            Store.shared.insertSession(s)
            let lines = ["先过一下今天的议程，三件事。",
                         "第一件是接口联调的排期，周三之前要收口。",
                         "第二件是周五去客户现场的名单。",
                         "第三件是结算流程先不动。"]
            for (i, text) in lines.enumerated() {
                let at = started.addingTimeInterval(Double(i) * 95)
                let seg = Segment(id: "shot-live-seg-\(i + 1)",
                                  startedAt: at, endedAt: at.addingTimeInterval(18),
                                  duration: 18, fileName: "", byteSize: 0,
                                  transcript: text, speaker: "",
                                  state: .transcribed, day: day, createdAt: at,
                                  captureModeRaw: CaptureMode.meeting.rawValue,
                                  starred: false,
                                  sessionId: liveSessionID)
                _ = Store.shared.insert(seg)
            }
        }
    }
    /// 时间线画面用：一天里散在 8 个不同小时上的事件，右侧时间轴才有内容
    static func seedTimelineIfNeeded() {
        guard let screen = ShotMode.screen else { return }
        let railScreens = ["timeline-rail", "today-timeline-asc", "today-timeline-parts",
                           "timeline-meeting", "memory-timeline-rail", "memory-cards",
                           "card-sheet-top", "card-sheet-bottom", "review-meetings"]
        guard railScreens.contains(screen) else { return }
        let day = today
        let existing = Set(Store.shared.events(day: day, limit: 200).map(\.id))
        if existing.contains("shot-rail-1") { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let samples: [(Int, String, String, String)] = [
            (7, "会议", "晨会 · 排今天的活", "接口联调和客户现场两件事先定时间。"),
            (8, "备忘", "把周报模板换一版", "上周的模板字段太少，加上风险和依赖。"),
            (10, "会议", "和周工过接口字段", "字段名统一成下划线，前端今天给一版。"),
            (11, "灵感", "整理页可以按人筛选", "会议多的时候按人看谁说了什么更直观。"),
            (13, "约定", "周五上午十点出发", "客户换了新园区，进门要找前台登记。"),
            (15, "会议", "结算流程对齐", "先按老流程走，这版不要动。"),
            (17, "备忘", "演示账号提前开好", "周工那边开三档权限的账号。"),
            (19, "决定", "这一版先不做导出", "导出留到下个版本，先把记录做稳。"),
            (20, "会议", "和周工收尾", "改动清单发群里，明天开始联调。"),
            (21, "灵感", "速记卡可以分享成图片", "开会的人不用装 App 也能看。")
        ]
        for (i, s) in samples.enumerated() {
            let at = cal.date(byAdding: .hour, value: s.0, to: start) ?? start
            let ev = MemoryEvent(id: "shot-rail-\(i + 1)", day: day,
                                 startAt: at, endAt: at.addingTimeInterval(600),
                                 scene: s.1, title: s.2, summary: s.3,
                                 points: [], people: ["我"], place: nil,
                                 emotion: "平静", intensity: 2, important: false,
                                 starred: false, starredAt: nil,
                                 entityId: "shot-rail-entity-\(i + 1)",
                                 lineFrom: 0, lineTo: 0, createdAt: at,
                                 sessionId: s.1 == "会议" ? meetingSessionID : nil)
            Store.shared.upsertEvent(ev)
        }
    }

    /// 记忆页卡片区：三张速记卡
    static func seedCardsIfNeeded() {
        guard let screen = ShotMode.screen else { return }
        guard ["memory-cards", "card-sheet-top", "card-sheet-bottom", "memory-timeline-rail"].contains(screen) else { return }
        let day = today
        let existing = Set(Store.shared.cards(day: day, limit: 50).map(\.id))
        if existing.contains("shot-card-1") { return }
        let now = Date()
        let cards: [(String, String, [String])] = [
            ("会议速记", "接口联调排期已定", ["结论先行：下周三之前联调完，周五去客户现场。", "要点：前端今天给一版，网关白名单明天配好。"]),
            ("项目快讯", "客户换到新园区", ["要点：进门要找前台登记，我提前报备。", "要点：名单周五上午十点前确认。"]),
            ("今日复盘", "两件事都按计划推进", ["要点：结算流程这版不动。", "要点：导出留到下个版本。"])
        ]
        for (i, c) in cards.enumerated() {
            let card = SkillCard(id: "shot-card-\(i + 1)",
                                 skillId: "shot-skill",
                                 skillName: c.0,
                                 day: day,
                                 startAt: now.addingTimeInterval(Double(-i) * 3600),
                                 endAt: nil,
                                 entityId: nil,
                                 fields: ["summary": c.1, "points": c.2.joined(separator: "\n")],
                                 quotes: [],
                                 nothingReason: nil,
                                 createdAt: now.addingTimeInterval(Double(-i) * 600))
            Store.shared.insertCard(card)
        }
    }

    static func event() -> MemoryEvent {
        Store.shared.events(day: today, limit: 20).first { $0.id == eventID }
            ?? MemoryEvent(id: eventID, day: today, startAt: Date(), endAt: nil,
                           scene: "会议", title: "和周工确认交付时间",
                           summary: "下周三之前把接口联调完。", points: [], people: ["我", "周工"],
                           place: "会议室", emotion: "平静", intensity: 3, important: false,
                           starred: false, starredAt: nil, entityId: "shot-entity-1",
                           lineFrom: 1, lineTo: 1, createdAt: Date())
    }
}

/// Form/ScrollView 默认从顶部开始；截图要把「最后一行有没有被 TabBar 挡住」拍出来，
/// 所以在截图模式下让内容先贴到底部。
struct ShotBottomAnchor: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.defaultScrollAnchor(ShotMode.active ? .bottom : .top)
        } else {
            content
        }
    }
}
