import Foundation
import AVFoundation

/// 录音输入设备：手机麦克风 / 领夹麦 / 蓝牙耳机，插上自动切换、拔掉自动切回
final class MicRouter {
    static let shared = MicRouter()

    struct Input: Identifiable, Hashable {
        var id: String
        var name: String
        var kind: String
    }

    private init() {}

    func inputs() -> [Input] {
        let session = AVAudioSession.sharedInstance()
        var out: [Input] = []
        let current = session.currentRoute.inputs.first?.uid ?? ""
        if let list = session.availableInputs {
            for p in list {
                var kind = "有线 / 内置"
                switch p.portType {
                case .builtInMic: kind = "内置"
                case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP: kind = "蓝牙"
                case .headsetMic: kind = "耳机"
                case .usbAudio: kind = "USB · Type-C"
                case .carAudio: kind = "车载"
                default: kind = "外接"
                }
                out.append(Input(id: p.uid, name: p.portName, kind: kind))
            }
        }
        if out.isEmpty {
            out.append(Input(id: "builtin", name: "手机麦克风", kind: "内置"))
        }
        // 把正在用的排前面
        if !current.isEmpty {
            out.sort { a, b in
                if a.id == current { return true }
                if b.id == current { return false }
                return a.name < b.name
            }
        }
        return out
    }

    func currentName() -> String {
        let session = AVAudioSession.sharedInstance()
        return session.currentRoute.inputs.first?.portName ?? "手机麦克风"
    }

    func currentUID() -> String {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid ?? ""
    }

    /// 应用偏好设备；偏好设备不在线时自动落回系统默认
    func applyPreferred() {
        let session = AVAudioSession.sharedInstance()
        let uid = Settings.shared.preferredInputUID
        guard !uid.isEmpty, uid != "builtin" else {
            try? session.setPreferredInput(nil)
            return
        }
        guard let list = session.availableInputs,
              let target = list.first(where: { $0.uid == uid }) else {
            try? session.setPreferredInput(nil)
            return
        }
        try? session.setPreferredInput(target)
    }
}
