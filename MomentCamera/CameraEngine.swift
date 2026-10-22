import AVFoundation
import Foundation

/// All capture-session mutations run on one queue, away from the UI thread.
final class CameraEngine: NSObject {
    enum Event {
        case ready(CameraCapabilities)
        case stopped
        case photo(Data)
        case recordingStarted
        case video(URL)
        case unavailable(String)
        case failure(String)
    }

    let session = AVCaptureSession()
    var onEvent: ((Event) -> Void)?
    private let queue = DispatchQueue(label: "camera.capture.session")
    private let photos = AVCapturePhotoOutput()
    private let movies = AVCaptureMovieFileOutput()
    private var cameraInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var configured = false
    private var interruptionObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?

    override init() {
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionWasInterrupted, object: session, queue: nil
        ) { [weak self] _ in
            self?.interrupt("相机暂时被其他应用或系统占用，请返回后重试。")
        }
        errorObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError, object: session, queue: nil
        ) { [weak self] _ in
            self?.interrupt("相机运行中断，请点击重试。")
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
    }

    func start() {
        queue.async { [self] in
            do {
                if !configured { try configure() }
                if !session.isRunning { session.startRunning() }
                if session.isRunning { reportReady() }
                else { emit(.failure("无法启动相机，请重试。")) }
            } catch {
                emit(.failure(error.localizedDescription))
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if movies.isRecording { movies.stopRecording() }
            if session.isRunning { session.stopRunning() }
            emit(.stopped)
        }
    }

    private func interrupt(_ message: String) {
        queue.async { [self] in
            if movies.isRecording { movies.stopRecording() }
            if session.isRunning { session.stopRunning() }
            emit(.unavailable(message))
        }
    }

    func switchCamera() {
        queue.async { [self] in
            guard !movies.isRecording, let oldInput = cameraInput else { return }
            let position: AVCaptureDevice.Position = oldInput.device.position == .back ? .front : .back
            do {
                let newInput = try makeCamera(position: position)
                session.beginConfiguration()
                session.removeInput(oldInput)
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    cameraInput = newInput
                } else {
                    session.addInput(oldInput)
                }
                session.commitConfiguration()
                reportReady()
            } catch {
                emit(.failure(error.localizedDescription))
            }
        }
    }

    func takePhoto(flash: AVCaptureDevice.FlashMode) {
        queue.async { [self] in
            guard session.isRunning else {
                emit(.failure("相机尚未就绪，请重试。"))
                return
            }
            let settings = AVCapturePhotoSettings()
            if photos.supportedFlashModes.contains(flash) { settings.flashMode = flash }
            rotate(photos.connection(with: .video))
            photos.capturePhoto(with: settings, delegate: self)
        }
    }

    func startRecording() {
        queue.async { [self] in
            guard session.isRunning, !movies.isRecording else {
                emit(.failure("相机尚未就绪，请重试。"))
                return
            }
            do {
                if audioInput == nil {
                    guard let microphone = AVCaptureDevice.default(for: .audio) else {
                        throw CameraError.message("未找到可用的麦克风。")
                    }
                    let input = try AVCaptureDeviceInput(device: microphone)
                    session.beginConfiguration()
                    let canAdd = session.canAddInput(input)
                    if canAdd { session.addInput(input); audioInput = input }
                    session.commitConfiguration()
                    guard canAdd else { throw CameraError.message("无法连接麦克风。") }
                }
                rotate(movies.connection(with: .video))
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                movies.startRecording(to: url, recordingDelegate: self)
            } catch {
                emit(.failure(error.localizedDescription))
            }
        }
    }

    func stopRecording() {
        queue.async { [self] in
            if movies.isRecording { movies.stopRecording() }
        }
    }

    func setExposure(automatic: Bool, iso: Double, duration: Double, bias: Double) {
        configureDevice { device in
            if automatic {
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                    let value = min(max(Float(bias), device.minExposureTargetBias), device.maxExposureTargetBias)
                    device.setExposureTargetBias(value, completionHandler: nil)
                }
            } else if device.isExposureModeSupported(.custom) {
                let format = device.activeFormat
                let seconds = min(max(duration, CMTimeGetSeconds(format.minExposureDuration)), CMTimeGetSeconds(format.maxExposureDuration))
                let clampedISO = min(max(Float(iso), format.minISO), format.maxISO)
                device.setExposureModeCustom(duration: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000), iso: clampedISO, completionHandler: nil)
            }
        }
    }

    func setFocus(automatic: Bool, position: Double) {
        configureDevice { device in
            if automatic, device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if !automatic, device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(lensPosition: Float(min(max(position, 0), 1)), completionHandler: nil)
            }
        }
    }

    func setWhiteBalance(automatic: Bool, temperature: Double) {
        configureDevice { device in
            if automatic, device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            } else if !automatic, device.isWhiteBalanceModeSupported(.locked) {
                let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(temperature), tint: 0)
                var gains = device.deviceWhiteBalanceGains(for: values)
                gains.redGain = min(max(gains.redGain, 1), device.maxWhiteBalanceGain)
                gains.greenGain = min(max(gains.greenGain, 1), device.maxWhiteBalanceGain)
                gains.blueGain = min(max(gains.blueGain, 1), device.maxWhiteBalanceGain)
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            }
        }
    }

    private func configureDevice(_ operation: @escaping (AVCaptureDevice) -> Void) {
        queue.async { [self] in
            guard let device = cameraInput?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                operation(device)
            } catch { emit(.failure(error.localizedDescription)) }
        }
    }

    private func reportReady() {
        guard let device = cameraInput?.device else { return }
        let format = device.activeFormat
        let minShutter = max(CMTimeGetSeconds(format.minExposureDuration), 1.0 / 10000)
        let maxShutter = max(minShutter, min(CMTimeGetSeconds(format.maxExposureDuration), 0.5))
        emit(.ready(CameraCapabilities(
            isoRange: Double(format.minISO)...Double(format.maxISO),
            shutterRange: minShutter...maxShutter,
            biasRange: Double(device.minExposureTargetBias)...Double(device.maxExposureTargetBias),
            initialISO: Double(device.iso), initialShutter: CMTimeGetSeconds(device.exposureDuration),
            supportsExposure: device.isExposureModeSupported(.custom),
            supportsFocus: device.isLockingFocusWithCustomLensPositionSupported,
            supportsWhiteBalance: device.isWhiteBalanceModeSupported(.locked)
        )))
    }

    private func configure() throws {
        let input = try makeCamera(position: .back)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard session.canAddInput(input) else { throw CameraError.message("无法连接摄像头。") }
        session.addInput(input)
        guard session.canAddOutput(photos), session.canAddOutput(movies) else {
            session.removeInput(input)
            throw CameraError.message("当前设备不支持照片和视频拍摄。")
        }
        session.addOutput(photos)
        session.addOutput(movies)
        cameraInput = input
        configured = true
    }

    private func makeCamera(position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.message("未找到可用的摄像头。请在真实 iPhone 上运行；模拟器不支持实拍。")
        }
        return try AVCaptureDeviceInput(device: device)
    }

    private func rotate(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            emit(.failure(error?.localizedDescription ?? "照片处理失败，请重试。"))
            return
        }
        emit(.photo(data))
    }
}

extension CameraEngine: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        emit(.recordingStarted)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        let recordingSucceeded = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
        if let error, !recordingSucceeded {
            try? FileManager.default.removeItem(at: url)
            emit(.failure(error.localizedDescription))
        } else {
            emit(.video(url))
        }
    }
}

private enum CameraError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
