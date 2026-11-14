import SwiftUI
import AVFoundation

@main
struct TaoShengApp: App {
    @StateObject private var settings = Settings.shared
    @StateObject private var app = AppState.shared
    @StateObject private var capture = CaptureEngine.shared
    @StateObject private var queue = TranscribeQueue.shared
    @StateObject private var digest = DigestEngine.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "auto"

    init() {
        // 和 CaptureEngine 保持一致：不要 .defaultToSpeaker / .allowBluetoothA2DP，
        // 否则微信语音、来电会被强制外放。
        // 提前起网络监听：否则首帧路径回来之前，都会以为自己在 WiFi 上
        _ = NetWatcher.shared
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord,
                                 mode: .default,
                                 options: [.allowBluetooth, .mixWithOthers])
    }

    /// 外观设置真正生效：日间 / 夜间 / 跟随系统
    private var scheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(app)
                .environmentObject(capture)
                .environmentObject(queue)
                .environmentObject(digest)
                .preferredColorScheme(scheme)
                .onAppear {
                    ShotDemo.seedIfNeeded()
                    ShotDemo.seedSegmentsIfNeeded()
                    ShotDemo.seedSessionsIfNeeded()
                    app.refresh()
                    // 截图模式只在模拟器里跑，不去弹通知/定位这些系统弹窗，免得住画面
                    guard !ShotMode.active else {
                        // 截图要能显示「正在聆听」或「已整理」，所以只换一下当前会话，不去真的收尾
                        ListenFlow.shared.reloadCurrent()
                        return
                    }
                    // 上次被杀/闪退时正在录的那一场，用已有录音补收尾：分人、整理、推送
                    ListenFlow.shared.resumeAfterLaunch()
                    queue.start()
                    digest.start()
                    ReviewEngine.shared.start()
                    SkillEngine.shared.start()
                    BackupEngine.shared.start()
                    ReminderEngine.shared.requestAuth()
                    ReminderEngine.shared.rescheduleAll(Store.shared.reminders())
                    // 整理自动排的提醒不落库，启动时按未完成待办补排一次。
                    // accepted 也要排：用户点了「加入待办」但没勾完的，同样该提醒。
                    var quicks: [(id: String, title: String, due: Date)] = []
                    for st in [MemItemStatus.pending, .accepted] {
                        for it in Store.shared.items(day: nil, status: st, category: nil, limit: 200) {
                            guard let due = it.dueAt, due > Date() else { continue }
                            quicks.append((id: it.id, title: it.content, due: due))
                        }
                    }
                    ReminderEngine.shared.rescheduleQuick(quicks)
                    MicRouter.shared.applyPreferred()
                    LocationEngine.shared.syncWithSettings()
                    if UserDefaults.standard.bool(forKey: "captureWanted") && !capture.isRunning {
                        capture.start()
                    }
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    app.refresh()
                    if UserDefaults.standard.bool(forKey: "captureWanted") && !capture.isRunning {
                        capture.start()
                    }
                }
        }
    }
}
