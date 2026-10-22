import SwiftUI

struct DevelopmentBatch: Identifiable {
    let id = UUID()
    let records: [CaptureRecord]
}

struct AlbumView: View {
    @ObservedObject var library: CaptureLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var batch: DevelopmentBatch?
    @State private var selected: CaptureRecord?
    @State private var prepared = false
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    if library.isLoading && library.records.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(60)
                    } else if library.records.isEmpty {
                        ContentUnavailableView("你的第一卷，还在等待", systemImage: "camera.aperture",
                                               description: Text("拍摄后会自动收入这里。显影、装裱，再决定是否保存到系统相册。"))
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(library.records) { record in
                                Button {
                                    if record.kind == .photo && !record.isDeveloped {
                                        batch = DevelopmentBatch(records: [record])
                                    } else { selected = record; library.exportNotice = nil }
                                } label: { albumCard(record) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(record.kind == .video ? "视频" : "照片")，\(record.displayDate)，\(record.isDeveloped ? "查看作品" : "等待显影")")
                            }
                        }
                    }
                    Text("作品保存在 App 内，只有你选择导出时才会写入系统相册。删除 App 会清除这些本地作品，请先导出想保留的照片。")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color(red: 0.045, green: 0.05, blue: 0.055))
            .navigationTitle("光的仓库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("返回拍摄") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if !library.undeveloped.isEmpty {
                        Button("点亮新胶片") { batch = DevelopmentBatch(records: library.undeveloped) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = library.errorMessage {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("关闭") { library.errorMessage = nil }
                    }
                    .padding().background(.ultraThinMaterial)
                }
            }
            .task {
                guard !prepared else { return }
                prepared = true
                await library.migrateLegacy()
                // Let the album's own presentation finish before presenting the darkroom.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                if !library.undeveloped.isEmpty { batch = DevelopmentBatch(records: library.undeveloped) }
            }
            .fullScreenCover(item: $batch) { batch in
                FilmDevelopmentView(library: library, records: batch.records)
            }
            .fullScreenCover(item: $selected) { record in
                AssetDetailView(library: library, record: record)
            }
        }
        .tint(Color(red: 0.91, green: 0.76, blue: 0.46))
        .preferredColorScheme(.dark)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A LITTLE ROOM FOR LIGHT").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(3).foregroundStyle(.secondary)
            Text("让片刻，慢慢显影。")
                .font(.system(size: 27, weight: .medium, design: .serif))
            HStack {
                Text("\(library.records.count) 件作品")
                if !library.undeveloped.isEmpty { Text("·  \(library.undeveloped.count) 张待显影").foregroundStyle(.orange) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func albumCard(_ record: CaptureRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FilmPerforations()
            ZStack {
                if record.isDeveloped {
                    LibraryThumbnail(url: library.thumbnailURL(record) ?? (record.kind == .photo ? library.fileURL(record) : nil),
                                     symbol: record.kind == .video ? "video" : "photo")
                } else {
                    Color.black
                    VStack(spacing: 12) {
                        Image(systemName: "lightbulb.slash").font(.title2)
                        Text("等待一束光").font(.caption)
                    }
                    .foregroundStyle(Color(red: 0.55, green: 0.42, blue: 0.29))
                }
                if record.kind == .video {
                    Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            FilmPerforations()
            Text(record.displayDate).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 9).padding(.bottom, 10)
        }
        .background(Color(white: 0.075), in: RoundedRectangle(cornerRadius: 8))
    }
}
