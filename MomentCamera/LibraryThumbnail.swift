import SwiftUI

struct LibraryThumbnail: View {
    let url: URL?
    var symbol = "photo"
    @State private var data: Data?

    var body: some View {
        ZStack {
            Color(white: 0.09)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: symbol).font(.title).foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: url) {
            data = nil
            guard let url else { return }
            let result = await Task.detached(priority: .utility) {
                guard let source = try? Data(contentsOf: url) else { return Optional<Data>.none }
                return try? LibraryImages.thumbnail(source)
            }.value
            guard !Task.isCancelled else { return }
            data = result
        }
    }
}

struct FilmPerforations: View {
    var body: some View {
        HStack {
            ForEach(0..<9, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.25)).frame(width: 9, height: 13)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 8).padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}
