import Foundation
import Network

/// 网络状态：判断当前是不是「贵的网」（蜂窝、个人热点），用来实现「只在 WiFi 下转写」。
///
/// NWPathMonitor 的回调在私有队列 q 上跑，而 `canUpload` / `label` 在 UI 线程读，
/// 所以状态用锁保护，避免数据竞争（Swift 5 不报，但真机上可能读到半个值）。
final class NetWatcher {
    static let shared = NetWatcher()

    private let monitor = NWPathMonitor()
    private let q = DispatchQueue(label: "app.taosheng.net")
    private let lock = NSLock()

    private var _expensive = false
    /// 首帧路径还没回来时按「没网」算：否则 App 刚启动那几百毫秒会被当成 WiFi，
    /// 蜂窝下也立刻开始上传录音。
    private var _online = false
    private var _isWiFi = false
    private var _resolved = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.lock.lock()
            self._online = (path.status == .satisfied)
            self._expensive = path.isExpensive
            self._isWiFi = path.usesInterfaceType(.wifi)
            self._resolved = true
            self.lock.unlock()
        }
        monitor.start(queue: q)
    }

    /// 当前链路按流量计费（蜂窝 / 热点）
    var expensive: Bool {
        lock.lock(); defer { lock.unlock() }
        return _expensive
    }

    var online: Bool {
        lock.lock(); defer { lock.unlock() }
        return _online
    }

    var isWiFi: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isWiFi
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
        lock.lock()
        let resolved = _resolved
        let online = _online
        let wifi = _isWiFi
        let expensive = _expensive
        lock.unlock()
        if !resolved { return "检查网络…" }
        if !online { return "没有网络" }
        if wifi { return "WiFi" }
        return expensive ? "移动网络" : "网络"
    }
}
