import AVFoundation
import SwiftUI

@MainActor
final class CameraViewModel: ObservableObject {
    enum Mode: String, CaseIterable { case photo = "照片", video = "视频" }
    let engine = CameraEngine()
    let cityLocation = CityLocationProvider()
    let library: CaptureLibrary
    @Published var mode: Mode = .photo
    @Published var style: PhotoStyle = .normal
    @Published private(set) var capabilities: CameraCapabilities?
    @Published var autoExposure = true
    @Published var autoFocus = true
    @Published var autoWhiteBalance = true
    @Published var iso: Double = 100
    @Published var shutterLog = log2(1.0 / 125)
    @Published var exposureBias: Double = 0
    @Published var focus: Double = 0.5
    @Published var temperature: Double = 5500
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var flash: AVCaptureDevice.FlashMode = .off
    @Published private(set) var notice: String?
    @Published var errorMessage: String?
    @Published private(set) var needsSettings = false
    private var isActive = false
    private var browsingAlbum = false
    private var operationPending = false
    private var activationInProgress = false
    private var noticeTask: Task<Void, Never>?
    private var capturedStyle: PhotoStyle = .normal
    private var capturedMetadata: CaptureMetadata?
    private let deviceModel = DeviceModel.current

    init(library: CaptureLibrary) {
        self.library = library
        engine.onEvent = { [weak self] event in Task { @MainActor in self?.handle(event) } }
    }

    func activate() async {
        guard !browsingAlbum else { return }
        isActive = true
        guard !isReady, !activationInProgress else { return }
        activationInProgress = true
        defer { activationInProgress = false }
        needsSettings = false
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
        else { granted = status == .authorized }
        guard granted else {
            needsSettings = true
            errorMessage = "请在系统设置中允许访问摄像头。即使不授权，你仍可浏览 App 相册。"
            return
        }
        guard isActive, !browsingAlbum else { return }
        cityLocation.refresh()
        engine.start()
    }

    func deactivate() {
        isActive = false
        isReady = false
        engine.stop()
    }

    func setBrowsingAlbum(_ value: Bool) {
        browsingAlbum = value
        if value { deactivate() }
    }

    func cycleFlash() {
        switch flash {
        case .off: flash = .auto
        case .auto: flash = .on
        default: flash = .off
        }
    }

    func switchCamera() {
        guard isReady, !isBusy, !isRecording else { return }
        isBusy = true
        engine.switchCamera()
    }

    func capture() async {
        guard isReady, !isBusy else { return }
        isBusy = true
        operationPending = true
        needsSettings = false
        if isRecording { engine.stopRecording(); return }
        if mode == .video {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            let granted: Bool
            if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .audio) }
            else { granted = status == .authorized }
            guard granted else {
                finishOperation()
                needsSettings = true
                errorMessage = "请在系统设置中允许麦克风权限，以录制有声音的视频。"
                return
            }
        }
        guard isActive, isReady, !browsingAlbum else { finishOperation(); return }
        // Snapshot at capture time. A later city refresh or photo edit cannot rewrite this.
        capturedMetadata = CaptureMetadata(capturedAt: Date(), timeZoneIdentifier: TimeZone.current.identifier,
                                           deviceModel: deviceModel, city: cityLocation.cityForCapture)
        cityLocation.refresh()
        if mode == .photo {
            capturedStyle = style
            engine.takePhoto(flash: flash)
        } else { engine.startRecording() }
    }

    private func handle(_ event: CameraEngine.Event) {
        switch event {
        case .ready(let capabilities):
            self.capabilities = capabilities
            iso = min(max(capabilities.initialISO, capabilities.isoRange.lowerBound), capabilities.isoRange.upperBound)
            shutterLog = log2(min(max(capabilities.initialShutter, capabilities.shutterRange.lowerBound), capabilities.shutterRange.upperBound))
            resetManualControls()
            isReady = isActive && !browsingAlbum
            isBusy = operationPending
        case .stopped: isReady = false
        case .recordingStarted:
            isRecording = true
            recordingStartedAt = Date()
            capturedMetadata?.capturedAt = recordingStartedAt
            finishOperation()
        case .photo(let data): Task { await savePhoto(data) }
        case .video(let url):
            isRecording = false
            recordingStartedAt = nil
            operationPending = true
            isBusy = true
            Task { await saveVideo(url) }
        case .unavailable(let message):
            isReady = false
            errorMessage = message
        case .failure(let message):
            finishOperation()
            isRecording = false
            recordingStartedAt = nil
            errorMessage = message
        }
    }

    private func savePhoto(_ data: Data) async {
        let style = capturedStyle
        let metadata = capturedMetadata ?? CaptureMetadata(capturedAt: nil, timeZoneIdentifier: TimeZone.current.identifier,
                                                           deviceModel: deviceModel, city: nil)
        var displayed = data
        var usedOriginal = false
        do { displayed = try await Task.detached(priority: .userInitiated) { try style.render(data) }.value }
        catch { usedOriginal = true }
        do {
            try await library.addPhoto(original: data, displayed: displayed, metadata: metadata)
            saved()
            if usedOriginal { errorMessage = "胶片处理失败，原片已保存到 App 相册。" }
        } catch {
            let backup = try? await Task.detached { try RecoveryStore().photo(data) }.value
            finishOperation()
            errorMessage = backup != nil ? "写入 App 相册失败，原片已暂存。再次进入相册时会尝试恢复。"
                : "照片未能保存，请检查设备剩余空间：\(error.localizedDescription)"
        }
    }

    private func saveVideo(_ url: URL) async {
        let metadata = capturedMetadata ?? CaptureMetadata(capturedAt: nil, timeZoneIdentifier: TimeZone.current.identifier,
                                                           deviceModel: deviceModel, city: nil)
        do { try await library.addVideo(url, metadata: metadata); saved(needsDevelopment: false) }
        catch {
            let backup = try? await Task.detached { try RecoveryStore().video(url) }.value
            finishOperation()
            errorMessage = backup != nil ? "写入 App 相册失败，视频已暂存。再次进入相册时会尝试恢复。"
                : "视频未能写入 App 相册，临时文件仍保留。请检查设备剩余空间。"
        }
    }

    private func finishOperation() { operationPending = false; isBusy = false }

    private func saved(needsDevelopment: Bool = true) {
        finishOperation()
        notice = needsDevelopment ? "已收入 App 相册 · 等你点亮" : "已收入 App 相册"
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func resetManualControls() {
        autoExposure = true
        autoFocus = true
        autoWhiteBalance = true
        exposureBias = 0
        applyExposure(); applyFocus(); applyWhiteBalance()
    }

    func applyExposure() {
        engine.setExposure(automatic: autoExposure, iso: iso, duration: pow(2, shutterLog), bias: exposureBias)
    }
    func applyFocus() { engine.setFocus(automatic: autoFocus, position: focus) }
    func applyWhiteBalance() { engine.setWhiteBalance(automatic: autoWhiteBalance, temperature: temperature) }
}
