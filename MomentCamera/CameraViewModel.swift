import AVFoundation
import Photos
import SwiftUI

@MainActor
final class CameraViewModel: ObservableObject {
    enum Mode: String, CaseIterable { case photo = "照片", video = "视频" }
    let engine = CameraEngine()
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
    @Published private(set) var recoveries: [URL] = []
    private let recoveryStore = RecoveryStore()
    private var isActive = false
    private var activationInProgress = false
    private var noticeTask: Task<Void, Never>?
    private var capturedStyle: PhotoStyle = .normal

    init() {
        recoveries = recoveryStore.items()
        engine.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func activate() async {
        isActive = true
        guard !isReady, !activationInProgress else { return }
        activationInProgress = true
        defer { activationInProgress = false }
        needsSettings = false
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        if status == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        } else {
            granted = status == .authorized
        }
        guard granted else {
            needsSettings = true
            errorMessage = "请在系统设置中允许访问摄像头，才能拍照和录像。"
            return
        }
        guard isActive else { return }
        engine.start()
    }

    func deactivate() {
        isActive = false
        isReady = false
        engine.stop()
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
        needsSettings = false
        if isRecording {
            engine.stopRecording()
            return
        }
        // Obtain add-only access before capture so a denied request cannot lose a recording.
        let libraryStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard libraryStatus == .authorized || libraryStatus == .limited else {
            isBusy = false
            needsSettings = true
            errorMessage = "请在系统设置中允许添加照片，拍摄内容才能保存到相册。"
            return
        }
        guard isActive, isReady else { isBusy = false; return }
        if mode == .photo {
            capturedStyle = style
            engine.takePhoto(flash: flash)
        } else {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            let granted: Bool
            if status == .notDetermined {
                granted = await AVCaptureDevice.requestAccess(for: .audio)
            } else {
                granted = status == .authorized
            }
            guard granted else {
                isBusy = false
                needsSettings = true
                errorMessage = "请在系统设置中允许麦克风权限，以录制有声音的视频。"
                return
            }
            guard isActive, isReady else { isBusy = false; return }
            engine.startRecording()
        }
    }

    private func handle(_ event: CameraEngine.Event) {
        switch event {
        case .ready(let capabilities):
            self.capabilities = capabilities
            iso = min(max(capabilities.initialISO, capabilities.isoRange.lowerBound), capabilities.isoRange.upperBound)
            shutterLog = log2(min(max(capabilities.initialShutter, capabilities.shutterRange.lowerBound), capabilities.shutterRange.upperBound))
            resetManualControls()
            isReady = isActive
            isBusy = false
        case .stopped:
            isReady = false
        case .recordingStarted:
            isRecording = true
            recordingStartedAt = Date()
            isBusy = false
        case .photo(let data):
            Task { await savePhoto(data) }
        case .video(let url):
            isRecording = false
            recordingStartedAt = nil
            isBusy = true
            Task { await saveVideo(url) }
        case .unavailable(let message):
            isReady = false
            errorMessage = message
        case .failure(let message):
            isBusy = false
            isRecording = false
            recordingStartedAt = nil
            errorMessage = message
        }
    }

    private func savePhoto(_ data: Data) async {
        let style = capturedStyle
        var rendered = data
        var usedOriginal = false
        do {
            rendered = try await Task.detached(priority: .userInitiated) { try style.render(data) }.value
        } catch {
            usedOriginal = true
        }
        let output = rendered
        let store = recoveryStore
        let backup = try? await Task.detached(priority: .userInitiated) { try store.photo(output) }.value
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: output, options: nil)
            }
            if let backup { recoveryStore.remove(backup) }
            saved()
            if usedOriginal { errorMessage = "胶片处理失败，已将正常模式原片保存到相册。" }
        } catch {
            isBusy = false
            recoveries = recoveryStore.items()
            errorMessage = backup != nil
                ? "相册保存失败，照片已保留。请从左下角的待保存拍摄中重试或导出。"
                : "照片保存失败，且无法创建本地备份。请检查设备剩余空间：\(error.localizedDescription)"
        }
    }

    private func saveVideo(_ url: URL) async {
        let store = recoveryStore
        let backup = try? await Task.detached(priority: .userInitiated) { try store.video(url) }.value
        let source = backup ?? url
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: source)
            }
            recoveryStore.remove(source)
            saved()
        } catch {
            isBusy = false
            recoveries = recoveryStore.items()
            errorMessage = backup != nil
                ? "相册保存失败，视频已保留。请从左下角的待保存拍摄中重试或导出。"
                : "视频保存失败，仅保留了临时文件。请检查设备剩余空间：\(error.localizedDescription)"
        }
    }

    func retrySave(_ url: URL) async {
        guard !isBusy, !isRecording else { return }
        isBusy = true
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            isBusy = false
            needsSettings = true
            errorMessage = "请在设置中允许添加照片，或使用分享导出。"
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if url.pathExtension == "mov" {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }
            recoveryStore.remove(url)
            saved()
        } catch {
            isBusy = false
            errorMessage = "仍然无法保存到相册。文件已保留，可通过分享导出。"
        }
    }

    private func saved() {
        recoveries = recoveryStore.items()
        isBusy = false
        notice = "已保存到相册"
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
        applyExposure()
        applyFocus()
        applyWhiteBalance()
    }

    func applyExposure() {
        engine.setExposure(automatic: autoExposure, iso: iso, duration: pow(2, shutterLog), bias: exposureBias)
    }

    func applyFocus() { engine.setFocus(automatic: autoFocus, position: focus) }

    func applyWhiteBalance() { engine.setWhiteBalance(automatic: autoWhiteBalance, temperature: temperature) }
}
