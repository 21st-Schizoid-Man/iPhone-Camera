import AVKit
import SwiftUI

struct AssetDetailView: View {
    @ObservedObject var library: CaptureLibrary
    let record: CaptureRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var decoration: PhotoDecoration
    @State private var preview: Data?
    @State private var previewError: String?
    @State private var player: AVPlayer?

    init(library: CaptureLibrary, record: CaptureRecord) {
        self.library = library
        self.record = record
        _decoration = State(initialValue: record.decoration)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if record.kind == .video {
                        VideoPlayer(player: player).frame(height: 320)
                    } else if let preview, let image = UIImage(data: preview) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 420)
                    } else {
                        if previewError == nil {
                            ProgressView("正在装裱…").frame(maxWidth: .infinity, minHeight: 260)
                        } else {
                            ContentUnavailableView("暂时无法显示预览", systemImage: "photo")
                        }
                    }
                    if let previewError { Text(previewError).font(.caption).foregroundStyle(.orange) }
                    Text(record.displayDate).font(.caption).foregroundStyle(.secondary)
                }
                if record.kind == .photo { decorationControls }
                Section {
                    Button {
                        Task { await library.export(record, decoration: decoration) }
                    } label: {
                        Label(record.kind == .photo ? "保存当前版本到系统相册" : "保存视频到系统相册", systemImage: "square.and.arrow.down")
                    }
                    if record.kind == .photo {
                        Button("导出拍摄原片（不含胶片效果、相框和水印）") {
                            Task { await library.export(record, decoration: decoration, original: true) }
                        }
                        .font(.caption)
                    }
                    if library.isExporting { ProgressView("正在导出，请稍候…") }
                    if let notice = library.exportNotice {
                        Label(notice, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
                    }
                    if let error = library.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        if library.needsPhotoSettings {
                            Button("前往系统设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                } footer: {
                    Text("相框和水印选择会保存在 App 内。导出生成单独的版本，拍摄原片始终保留。")
                }
                .disabled(library.isExporting)
            }
            .navigationTitle(record.kind == .photo ? "装裱这一刻" : "这一段时光")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() }.disabled(library.isExporting) } }
            .task(id: decoration) { await updatePreview() }
            .onChange(of: decoration) { _, value in library.editDecoration(value, id: record.id) }
            .onDisappear { player?.pause() }
        }
        .tint(Color(red: 0.91, green: 0.76, blue: 0.46)).preferredColorScheme(.dark)
        .interactiveDismissDisabled(library.isExporting)
    }

    private var decorationControls: some View {
        Group {
            Section("摄影相框") {
                Picker("相框样式", selection: $decoration.frame) {
                    ForEach(PhotoFrame.allCases) { frame in Text(frame.rawValue).tag(frame) }
                }
                .pickerStyle(.menu)
            }
            Section("作品水印") {
                Toggle("添加水印", isOn: $decoration.watermarkEnabled)
                if decoration.watermarkEnabled {
                    Picker("水印位置", selection: $decoration.position) {
                        ForEach(WatermarkPosition.allCases) { position in Text(position.rawValue).tag(position) }
                    }.pickerStyle(.segmented)
                    Toggle("手机型号", isOn: $decoration.showDevice)
                    Toggle("拍摄日期", isOn: $decoration.showDate)
                    Toggle("地点城市", isOn: $decoration.showCity)
                    if decoration.showCity {
                        TextField(record.metadata.city ?? "手动填写拍摄城市", text: $decoration.cityOverride)
                            .textInputAutocapitalization(.never)
                            .onChange(of: decoration.cityOverride) { _, value in
                                if value.count > 40 { decoration.cityOverride = String(value.prefix(40)) }
                            }
                        Text(record.metadata.city.map { "拍摄时记录：\($0)。留空使用该城市，也可自行修改。" }
                             ?? "这张照片未记录拍摄城市，请手动填写；不会使用你现在的位置补写过去的照片。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if decoration.watermark(for: record.metadata).isEmpty {
                        Text("请选择至少一项有内容的信息，水印才会显示。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .disabled(library.isExporting)
    }

    private func updatePreview() async {
        if record.kind == .video {
            if player == nil { player = AVPlayer(url: library.fileURL(record)) }
            return
        }
        let url = library.fileURL(record)
        let metadata = record.metadata
        let settings = decoration
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try PhotoDecorationRenderer.render(Data(contentsOf: url), metadata: metadata, decoration: settings, maxPixel: 1400)
            }.value
            guard !Task.isCancelled else { return }
            preview = data
            previewError = nil
        } catch {
            guard !Task.isCancelled else { return }
            previewError = "预览暂时不可用，原片仍然保留。"
        }
    }
}
