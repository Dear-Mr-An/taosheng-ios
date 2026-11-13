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
        case "today", "event-edit": return 0
        case "ask": return 1
        case "memory": return 2
        case "todo": return 3
        case "recording-bottom", "person-add": return 4
        default: return nil
        }
    }
}

/// 截图用的演示数据：只写内存里那几张表，不产生任何音频文件。
enum ShotDemo {
    static let eventID = "shot-event-1"

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
                createdAt: now))
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
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.defaultScrollAnchor(ShotMode.active ? .bottom : .top)
        } else {
            content
        }
    }
}
