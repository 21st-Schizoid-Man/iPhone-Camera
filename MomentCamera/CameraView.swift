import AVFoundation
import SwiftUI

struct CameraView: View {
    @StateObject private var model: CameraViewModel
    @StateObject private var library: CaptureLibrary
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var showingManualControls = false
    @State private var showingAlbum = false
    @State private var showingLocation = false

    init() {
        let library = CaptureLibrary()
        _library = StateObject(wrappedValue: library)
        _model = StateObject(wrappedValue: CameraViewModel(library: library))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ZStack {
                    CameraPreview(session: model.engine.session)
                        .clipped()
                    if !model.isReady {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.aperture").font(.system(size: 44))
                            Text("准备好，留住这一刻").font(.headline)
                            Button("启动相机") { Task { await model.activate() } }
                                .buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.8))
                    }
                    VStack {
                        if let start = model.recordingStartedAt {
                            HStack(spacing: 8) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                Text(start, style: .timer).monospacedDigit()
                            }
                            .padding(12).background(.black.opacity(0.6), in: Capsule())
                        }
                        Spacer()
                        if let notice = model.notice {
                            Label(notice, systemImage: "checkmark.circle.fill")
                                .padding(12).background(.ultraThinMaterial, in: Capsule())
                                .padding(.bottom, 20)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                    .padding(.top, 16)
                }
                controls
            }
        }
        .tint(.yellow)
        .sheet(isPresented: $showingManualControls) {
            ManualControls(model: model).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingLocation) {
            CityCaptureSettings(provider: model.cityLocation).presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showingAlbum, onDismiss: {
            model.setBrowsingAlbum(false)
            Task { await model.activate() }
        }) {
            AlbumView(library: library)
        }
        .task { await library.migrateLegacy(); await model.activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.activate() } }
            else if phase == .background { model.deactivate() }
        }
        .alert("相机提示", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            if model.needsSettings {
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button("好的", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("拾光").font(.system(size: 22, weight: .semibold, design: .serif))
                Text("MOMENT CAMERA").font(.system(size: 8, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
            }
            Spacer()
            CityCaptureButton(provider: model.cityLocation) { showingLocation = true }
            Button { showingManualControls = true } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
            }
            .accessibilityLabel("专业参数")
            .disabled(!model.isReady || model.isBusy || model.isRecording)
            Button { model.cycleFlash() } label: {
                Image(systemName: model.flash == .off ? "bolt.slash.fill" : (model.flash == .auto ? "bolt.badge.a.fill" : "bolt.fill"))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("闪光灯：\(model.flash == .off ? "关闭" : (model.flash == .auto ? "自动" : "开启"))")
            .disabled(model.mode != .photo || model.isRecording || model.isBusy)
        }
        .padding(.horizontal, 22).padding(.vertical, 8)
    }

    private var controls: some View {
        VStack(spacing: 24) {
            if model.mode == .photo {
                Picker("照片风格", selection: $model.style) {
                    ForEach(PhotoStyle.allCases) { style in Text(style.rawValue).tag(style) }
                }
                .pickerStyle(.segmented)
                .disabled(model.isBusy)
            }
            HStack(spacing: 32) {
                ForEach(CameraViewModel.Mode.allCases, id: \.self) { mode in
                    Button(mode.rawValue) { model.mode = mode }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(model.mode == mode ? .yellow : .white.opacity(0.65))
                        .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                        .disabled(model.isRecording || model.isBusy)
                }
            }
            HStack {
                Button {
                    model.setBrowsingAlbum(true)
                    showingAlbum = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            if let latest = library.records.first, latest.isDeveloped {
                                LibraryThumbnail(url: library.thumbnailURL(latest))
                            } else {
                                Color(white: 0.10)
                                Image(systemName: "photo.stack").font(.title3).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.5), lineWidth: 1))
                        if !library.undeveloped.isEmpty {
                            Text("\(library.undeveloped.count)").font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                                .padding(5).background(.yellow, in: Circle()).offset(x: 6, y: -6)
                        }
                    }
                }
                .accessibilityLabel("打开 App 相册，\(library.records.count) 件作品，\(library.undeveloped.count) 张待显影")
                .disabled(model.isRecording || model.isBusy)
                Spacer()
                Button { Task { await model.capture() } } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 82, height: 82)
                        if model.isBusy {
                            ProgressView().tint(.white)
                        } else if model.isRecording {
                            RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 32, height: 32)
                        } else {
                            Circle().fill(model.mode == .photo ? .white : .red).frame(width: 66, height: 66)
                        }
                    }
                }
                .accessibilityLabel(model.isRecording ? "停止录像" : (model.mode == .photo ? "拍照" : "开始录像"))
                .disabled(!model.isReady || model.isBusy)
                Spacer()
                Button { model.switchCamera() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 24)).frame(width: 56, height: 56)
                }
                .foregroundStyle(.white)
                .accessibilityLabel("切换前后摄像头")
                .disabled(!model.isReady || model.isBusy || model.isRecording)
            }
            Text(model.mode == .photo && model.style != .normal
                 ? "胶片风格用于成片 · 取景器显示原始画面"
                 : "先收入 App 相册 · 由你决定是否导出")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 20)
    }
}
