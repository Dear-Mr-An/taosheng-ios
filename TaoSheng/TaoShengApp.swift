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
    @AppStorage("appearance") private var appearance = "system"

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord,
                                 mode: .default,
                                 options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers, .defaultToSpeaker])
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
