import SwiftUI
import AVFoundation

@main
struct TaoShengApp: App {
    @StateObject private var settings = Settings.shared
    @StateObject private var app = AppState.shared
    @StateObject private var capture = CaptureEngine.shared
    @StateObject private var queue = TranscribeQueue.shared
    @StateObject private var digest = DigestEngine.shared

    init() {
        // 音频会话提前配好，避免首次点录音时被系统打断
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord,
                                 mode: .default,
                                 options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers, .defaultToSpeaker])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(app)
                .environmentObject(capture)
                .environmentObject(queue)
                .environmentObject(digest)
                .preferredColorScheme(.dark)
                .onAppear {
                    app.refresh()
                    queue.start()
                    digest.start()
                    if UserDefaults.standard.bool(forKey: "captureWanted") && !capture.isRunning {
                        capture.start()
                    }
                }
        }
    }
}
