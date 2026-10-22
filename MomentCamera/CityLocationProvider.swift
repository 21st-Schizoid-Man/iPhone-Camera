import CoreLocation
import SwiftUI

@MainActor
final class CityLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var enabled = false
    @Published private(set) var city: String?
    @Published private(set) var status = "未开启；也可在照片水印中手动填写城市。"
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var resolvedAt: Date?
    private var fetching = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var cityForCapture: String? {
        guard enabled, let resolvedAt, Date().timeIntervalSince(resolvedAt) < 300 else { return nil }
        return city
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if value { refresh(requestPermission: true) }
        else {
            manager.stopUpdatingLocation()
            geocoder.cancelGeocode()
            city = nil
            resolvedAt = nil
            fetching = false
            status = "城市记录已关闭。"
        }
    }

    func refresh(requestPermission: Bool = false, force: Bool = false) {
        guard enabled else { return }
        guard !fetching, force || cityForCapture == nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            if requestPermission { manager.requestWhenInUseAuthorization() }
        case .authorizedWhenInUse, .authorizedAlways:
            status = "正在获取拍摄城市…"
            fetching = true
            manager.requestLocation()
        case .denied, .restricted:
            city = nil
            resolvedAt = nil
            fetching = false
            status = "未获得定位权限；可以在照片水印中手动填写城市。"
        @unknown default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { refresh() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard enabled, let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 120 else { fetching = false; return }
        geocoder.reverseGeocodeLocation(location) { [weak self] places, error in
            Task { @MainActor in
                guard let self, self.enabled else { return }
                self.fetching = false
                let place = places?.first
                self.city = place?.locality ?? place?.administrativeArea
                self.resolvedAt = self.city == nil ? nil : Date()
                self.status = self.city.map { "当前城市：\($0)" } ?? "暂时无法确定城市；照片仍可正常拍摄，也可稍后手动填写。"
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fetching = false
        status = "暂时无法获取城市；可以在水印中手动填写。"
    }
}

struct CityCaptureSettings: View {
    @ObservedObject var provider: CityLocationProvider
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("本次使用期间记录拍摄城市", isOn: Binding(
                        get: { provider.enabled }, set: { provider.setEnabled($0) }
                    ))
                    Text(provider.status).font(.callout).foregroundStyle(.secondary)
                    if provider.enabled { Button("刷新城市") { provider.refresh(requestPermission: true, force: true) } }
                } footer: {
                    Text("仅在你主动开启后使用系统定位和地理编码服务。作品只记录城市名称，不保存坐标；拒绝权限不影响拍摄。此设置不会为以前的照片补写当前位置。")
                }
            }
            .navigationTitle("拍摄城市").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CityCaptureButton: View {
    @ObservedObject var provider: CityLocationProvider
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: provider.enabled ? "location.fill" : "location.slash")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("拍摄城市：\(provider.enabled ? "已开启" : "未开启")")
    }
}
