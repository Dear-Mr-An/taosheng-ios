import Foundation
import Network

/// 网络状态：判断当前是不是「贵的网」（蜂窝、个人热点），用来实现「只在 WiFi 下转写」。
final class NetWatcher {
    static let shared = NetWatcher()

    private let monitor = NWPathMonitor()
    private let q = DispatchQueue(label: "app.taosheng.net")

    /// 当前链路按流量计费（蜂窝 / 热点）
    private(set) var expensive = false
    private(set) var online = true
    private(set) var isWiFi = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.online = (path.status == .satisfied)
            self.expensive = path.isExpensive
            self.isWiFi = path.usesInterfaceType(.wifi)
        }
        monitor.start(queue: q)
    }

    /// 现在能不能上传录音
    var canUpload: Bool {
        guard online else { return false }
        if Settings.shared.wifiOnlyTranscribe {
            return !expensive
        }
        return true
    }

    var label: String {
        if !online { return "没有网络" }
        if isWiFi { return "WiFi" }
        return expensive ? "移动网络" : "网络"
    }
}
