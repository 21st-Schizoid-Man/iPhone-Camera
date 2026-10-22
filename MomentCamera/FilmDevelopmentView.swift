import SwiftUI

struct FilmDevelopmentView: View {
    @ObservedObject var library: CaptureLibrary
    let records: [CaptureRecord]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lightOn = false
    @State private var illumination: Double = 0
    @State private var positive = false
    @State private var completed = false
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.8, green: 0.66, blue: 0.42).opacity(illumination * 0.32), .clear],
                           center: .center, startRadius: 0, endRadius: 500).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Text("拾光 / 暗房").font(.system(size: 13, design: .monospaced)).tracking(2)
                    Spacer()
                    Button(completed ? "进入相册" : "稍后显影") { dismiss() }
                        .disabled(lightOn && !completed && error == nil)
                }
                .padding(.horizontal, 24).padding(.top, 16)
                Spacer(minLength: 8)
                Image(systemName: lightOn ? "lightbulb.max.fill" : "lightbulb.slash")
                    .font(.system(size: 28)).foregroundStyle(lightOn ? .yellow : .gray)
                    .accessibilityHidden(true)
                Text(completed ? "这一刻，终于有了颜色。" : "有些片刻，要在光里才看得见。")
                    .font(.system(size: 21, weight: .medium, design: .serif)).multilineTextAlignment(.center)
                    .padding(.horizontal)
                TabView {
                    ForEach(records) { record in
                        VStack(spacing: 0) {
                            FilmPerforations()
                            ZStack {
                                Color.black
                                LibraryThumbnail(url: library.thumbnailURL(record) ?? library.fileURL(record))
                                    .colorInvert().colorMultiply(Color(red: 0.88, green: 0.60, blue: 0.35))
                                    .opacity(illumination)
                                LibraryThumbnail(url: library.thumbnailURL(record) ?? library.fileURL(record))
                                    .opacity(positive ? 1 : 0)
                            }
                            .aspectRatio(3 / 4, contentMode: .fit).clipped()
                            FilmPerforations()
                        }
                        .padding(.horizontal, 8).background(Color(white: 0.055))
                        .padding(.horizontal, 36).padding(.bottom, 30)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: records.count > 1 ? .always : .never))
                .frame(maxHeight: 430)
                .accessibilityLabel(completed ? "照片已经显影" : "尚未点亮的胶片")
                if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                Button {
                    if completed { dismiss() }
                    else {
                        self.error = nil; illumination = 0; positive = false
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        lightOn = true
                        attempt += 1
                    }
                } label: {
                    Label(completed ? "收好这一卷" : (error == nil ? "打开观片灯" : "重新点亮"),
                          systemImage: completed ? "checkmark" : "lightbulb.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(17)
                }
                .buttonStyle(.borderedProminent).tint(Color(red: 0.91, green: 0.76, blue: 0.46)).foregroundStyle(.black)
                .disabled(lightOn && !completed && error == nil)
                .padding(.horizontal, 32)
                Text(completed ? "已完成显影，可在相册中装裱与导出。" : "\(records.count) 张新照片 · 从暗片到底片，再到属于你的照片")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal).padding(.bottom, 16)
                Spacer(minLength: 0)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(lightOn && !completed && error == nil)
        .task(id: attempt) {
            guard attempt > 0 else { return }
            do {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.85)) { illumination = 1 }
                try await Task.sleep(for: .seconds(reduceMotion ? 0.1 : 1.0))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.1)) { positive = true }
                try await Task.sleep(for: .seconds(reduceMotion ? 0.1 : 1.2))
                try Task.checkCancellation()
                try await library.develop(records.map(\.id))
                completed = true
            } catch is CancellationError {
                // Leaving before completion does not mark unseen photos as developed.
            } catch { self.error = "显影状态暂未保存，请重试。照片原片仍在 App 内。" }
        }
    }
}
