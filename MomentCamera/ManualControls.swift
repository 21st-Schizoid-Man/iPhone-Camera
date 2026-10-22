import AVFoundation
import SwiftUI

struct CameraCapabilities {
    var isoRange: ClosedRange<Double>
    var shutterRange: ClosedRange<Double>
    var biasRange: ClosedRange<Double>
    var initialISO: Double
    var initialShutter: Double
    var supportsExposure: Bool
    var supportsFocus: Bool
    var supportsWhiteBalance: Bool
}

struct ManualControls: View {
    @ObservedObject var model: CameraViewModel

    var body: some View {
        NavigationStack {
            Form {
                if let capabilities = model.capabilities {
                    Section("曝光") {
                        Toggle("自动曝光", isOn: $model.autoExposure)
                            .disabled(!capabilities.supportsExposure)
                        if model.autoExposure {
                            control("曝光补偿", value: $model.exposureBias,
                                    range: capabilities.biasRange, text: String(format: "%+.1f EV", model.exposureBias))
                        } else {
                            control("ISO", value: $model.iso, range: capabilities.isoRange,
                                    text: "\(Int(model.iso))")
                            control("快门", value: $model.shutterLog,
                                    range: log2(capabilities.shutterRange.lowerBound)...log2(capabilities.shutterRange.upperBound),
                                    text: shutterText)
                        }
                    }
                    Section("镜头") {
                        Toggle("自动对焦", isOn: $model.autoFocus)
                            .disabled(!capabilities.supportsFocus)
                        if !model.autoFocus {
                            control("焦点位置", value: $model.focus, range: 0...1,
                                    text: String(format: "%.0f%%", model.focus * 100))
                            Text("0 为近焦端，100 为远焦端；实际距离由镜头决定。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("自动白平衡", isOn: $model.autoWhiteBalance)
                            .disabled(!capabilities.supportsWhiteBalance)
                        if !model.autoWhiteBalance {
                            control("色温", value: $model.temperature, range: 2500...8500,
                                    text: "\(Int(model.temperature)) K")
                        }
                    }
                    Section {
                        Button("恢复自动设置") { model.resetManualControls() }
                        Text("参数范围依当前摄像头能力调整。切换镜头后恢复自动设置。胶片风格仅用于照片成片；预览和录像为正常模式。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView("相机尚未就绪", systemImage: "camera", description: Text("请先允许相机权限并在真实 iPhone 上启动相机。"))
                }
            }
            .navigationTitle("专业参数")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(model.isBusy || model.isRecording)
            .onChange(of: model.autoExposure) { _, _ in model.applyExposure() }
            .onChange(of: model.iso) { _, _ in model.applyExposure() }
            .onChange(of: model.shutterLog) { _, _ in model.applyExposure() }
            .onChange(of: model.exposureBias) { _, _ in model.applyExposure() }
            .onChange(of: model.autoFocus) { _, _ in model.applyFocus() }
            .onChange(of: model.focus) { _, _ in model.applyFocus() }
            .onChange(of: model.autoWhiteBalance) { _, _ in model.applyWhiteBalance() }
            .onChange(of: model.temperature) { _, _ in model.applyWhiteBalance() }
        }
    }

    private var shutterText: String {
        let duration = pow(2, model.shutterLog)
        return duration < 1 ? "1/\(Int((1 / duration).rounded())) s" : String(format: "%.1f s", duration)
    }

    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(text).monospacedDigit().foregroundStyle(.secondary) }
            if range.lowerBound < range.upperBound {
                Slider(value: value, in: range).accessibilityLabel(title)
            }
        }
    }
}
