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
                    app.refresh()
                    queue.start()
                    digest.start()
                    ReviewEngine.shared.start()
                    SkillEngine.shared.start()
                    BackupEngine.shared.start()
                    ReminderEngine.shared.requestAuth()
                    ReminderEngine.shared.rescheduleAll(Store.shared.reminders())
                    // 整理自动排的提醒不落库，启动时按未完成待办补排一次
                    ReminderEngine.shared.rescheduleQuick(
                        Store.shared.items(day: nil, status: .pending, category: nil, limit: 200)
                            .compactMap { it in
                                guard let due = it.dueAt else { return nil }
                                return (id: it.id, title: it.content, due: due)
                            }
                    )
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
