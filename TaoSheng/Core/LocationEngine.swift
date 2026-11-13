import Foundation
import CoreLocation

/// 足迹：跟随收音服务，约每 5 分钟记一个点；停留超过 4 分钟合成一条记录。
/// 位置只写本机数据库，不上传。
final class LocationEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationEngine()

    @Published private(set) var lastPlace: String?
    @Published private(set) var pointCount: Int = 0
    @Published private(set) var authorized: Bool = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var timer: Timer?
    private var lastFix: CLLocation?
    private var stayStart: Date?
    private var stayName: String = ""
    private var geocoding = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 80
        manager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - 开关

    func syncWithSettings() {
        if Settings.shared.locationOn {
            start()
        } else {
            stop()
        }
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        timer?.invalidate()
        // scheduledTimer 已经自动进当前 RunLoop 的 default 模式；再 add 一次会重复投递
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.flushStay()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        manager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        flushStay()
    }

    // MARK: - 回调

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let st = m.authorizationStatus
        let ok = (st == .authorizedWhenInUse || st == .authorizedAlways)
        DispatchQueue.main.async { self.authorized = ok }
        if ok && Settings.shared.locationOn { m.startUpdatingLocation() }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last, loc.horizontalAccuracy >= 0 else { return }
        lastFix = loc
        pointCount += 1
        if stayStart == nil { stayStart = Date() }
        resolveName(loc)
        if let s = stayStart, Date().timeIntervalSince(s) >= 240 {
            flushStay()
        }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        // 室内定位失败很常见，忽略即可
    }

    // MARK: - 地名

    private func resolveName(_ loc: CLLocation) {
        guard !geocoding else { return }
        geocoding = true
        geocoder.reverseGeocodeLocation(loc) { [weak self] marks, _ in
            guard let self = self else { return }
            self.geocoding = false
            guard let p = marks?.first else { return }
            let name = p.name ?? p.locality ?? p.subLocality ?? p.administrativeArea ?? "未知地点"
            self.stayName = name
            DispatchQueue.main.async { self.lastPlace = name }
        }
    }

    // MARK: - 停留点入库

    private func flushStay() {
        guard let start = stayStart, let loc = lastFix else { return }
        let end = Date()
        let dur = end.timeIntervalSince(start)
        guard dur >= 120 else { return }
        let name = stayName.isEmpty
            ? String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)
            : stayName
        let visit = PlaceVisit(id: UUID().uuidString,
                               day: DayKey.of(start),
                               name: name,
                               latitude: loc.coordinate.latitude,
                               longitude: loc.coordinate.longitude,
                               arriveAt: start,
                               leaveAt: end,
                               isHome: false)
        Store.shared.upsertPlace(visit)
        stayStart = end
        stayName = ""
    }
}
