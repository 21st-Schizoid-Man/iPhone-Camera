import SwiftUI

struct RecoveryView: View {
    @ObservedObject var model: CameraViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("以下内容尚未写入系统相册，已保留在应用中。你可以重新保存或通过分享导出。")
                        .font(.callout).foregroundStyle(.secondary)
                    if let error = model.errorMessage {
                        Text(error).font(.callout).foregroundStyle(.orange)
                    }
                }
                ForEach(model.recoveries, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 12) {
                        Label(url.pathExtension == "mov" ? "待保存的视频" : "待保存的照片",
                              systemImage: url.pathExtension == "mov" ? "video" : "photo")
                        HStack(spacing: 24) {
                            Button("存入相册") { Task { await model.retrySave(url) } }
                                .buttonStyle(.bordered)
                                .disabled(model.isBusy)
                            ShareLink(item: url) { Label("分享导出", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("待保存拍摄")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if model.recoveries.isEmpty {
                    ContentUnavailableView("没有待保存内容", systemImage: "checkmark.circle")
                }
            }
        }
    }
}
