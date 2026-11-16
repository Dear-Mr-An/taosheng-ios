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
        // 把正在用的排前面（比较器必须是严格弱序，否则 sort 结果不稳定）
        if !current.isEmpty {
            out.sort { a, b in
                if (a.id == current) != (b.id == current) { return a.id == current }
                if a.name != b.name { return a.name < b.name }
                return a.id < b.id
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

    /// 有没有外接输入（USB / 蓝牙 / 耳机 / 车载）
    func hasExternal() -> Bool {
        guard let list = AVAudioSession.sharedInstance().availableInputs else { return false }
        return list.contains { $0.portType != .builtInMic }
    }

    /// 应用偏好设备。空 UID = 明确要手机麦克风（不是「随便」）；
    /// 「自动」= 有外接用外接、没有就手机麦克风；指定设备掉线才落回手机麦克风。
    func applyPreferred() {
        let session = AVAudioSession.sharedInstance()
        let uid = Settings.shared.preferredInputUID
        let list = session.availableInputs ?? []
        let builtIn = list.first { $0.portType == .builtInMic }
        switch MicRules.choice(uid: uid, hasExternal: hasExternal()) {
        case .systemDefault:
            try? session.setPreferredInput(nil)
        case .builtIn:
            try? session.setPreferredInput(builtIn)
        case .external:
            if let ext = list.first(where: { $0.portType != .builtInMic }) {
                try? session.setPreferredInput(ext)
            } else {
                try? session.setPreferredInput(builtIn)
            }
        case .specific(let id):
            if let target = list.first(where: { $0.uid == id }) {
                try? session.setPreferredInput(target)
            } else {
                try? session.setPreferredInput(builtIn)
            }
        }
    }
}
