import Foundation

enum CaptureKind: String, Codable, Sendable { case photo, video }

enum PhotoFrame: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "无相框"
    case galleryWhite = "留白画廊"
    case galleryBlack = "黑色画廊"
    case instant = "即时成像"
    var id: Self { self }
}

enum WatermarkPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case top = "上方", bottom = "下方", left = "左侧", right = "右侧"
    var id: Self { self }
}

struct PhotoDecoration: Codable, Hashable, Sendable {
    var frame: PhotoFrame = .none
    var watermarkEnabled = false
    var position: WatermarkPosition = .bottom
    var showDevice = true
    var showDate = true
    var showCity = false
    var cityOverride = ""

    func watermark(for metadata: CaptureMetadata) -> String {
        guard watermarkEnabled else { return "" }
        var parts: [String] = []
        if showDevice { parts.append(metadata.deviceModel) }
        if showDate, let date = metadata.capturedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: metadata.timeZoneIdentifier) ?? .current
            formatter.dateFormat = "yyyy.MM.dd HH:mm"
            parts.append(formatter.string(from: date))
        }
        if showCity {
            let entered = cityOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            let city = entered.isEmpty ? (metadata.city ?? "") : entered
            if !city.isEmpty { parts.append(String(city.prefix(40))) }
        }
        return parts.joined(separator: "  ·  ")
    }
}

struct CaptureMetadata: Codable, Equatable, Sendable {
    var capturedAt: Date?
    var timeZoneIdentifier: String
    var deviceModel: String
    var city: String?
}

struct CaptureRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: CaptureKind
    let importedAt: Date
    let metadata: CaptureMetadata
    let originalFilename: String
    let displayFilename: String
    let thumbnailFilename: String?
    var isDeveloped: Bool
    var decoration: PhotoDecoration
    var lastExportedAt: Date?
    var legacyFilename: String?

    var sortDate: Date { metadata.capturedAt ?? importedAt }
    var displayDate: String {
        guard let date = metadata.capturedAt else { return "拍摄时间未记录" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: metadata.timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
