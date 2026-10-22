import ImageIO
import UIKit

struct DecorationLayout {
    let canvas: CGSize
    let photo: CGRect
    let watermark: CGRect
    let watermarkRotation: CGFloat

    init(photoSize: CGSize, frame: PhotoFrame, position: WatermarkPosition, hasWatermark: Bool) {
        let edge = min(photoSize.width, photoSize.height)
        let border = frame == .none ? 0 : edge * 0.065
        var top = border, bottom = border, left = border, right = border
        if frame == .instant { bottom = edge * 0.22 }
        if hasWatermark && frame != .none {
            let band = edge * 0.12
            switch position {
            case .top: top = max(top, band)
            case .bottom: bottom = max(bottom, band)
            case .left: left = max(left, band)
            case .right: right = max(right, band)
            }
        }
        canvas = CGSize(width: photoSize.width + left + right, height: photoSize.height + top + bottom)
        photo = CGRect(x: left, y: top, width: photoSize.width, height: photoSize.height)
        let inset = edge * 0.025
        let overlayThickness = edge * 0.085
        if frame == .none {
            switch position {
            case .top: watermark = CGRect(x: inset, y: inset, width: photoSize.width - 2 * inset, height: overlayThickness)
            case .bottom: watermark = CGRect(x: inset, y: photoSize.height - inset - overlayThickness,
                                            width: photoSize.width - 2 * inset, height: overlayThickness)
            case .left: watermark = CGRect(x: inset, y: inset, width: overlayThickness, height: photoSize.height - 2 * inset)
            case .right: watermark = CGRect(x: photoSize.width - inset - overlayThickness, y: inset,
                                           width: overlayThickness, height: photoSize.height - 2 * inset)
            }
        } else {
            switch position {
            case .top: watermark = CGRect(x: left, y: 0, width: photoSize.width, height: top)
            case .bottom: watermark = CGRect(x: left, y: photo.maxY, width: photoSize.width, height: bottom)
            case .left: watermark = CGRect(x: 0, y: top, width: left, height: photoSize.height)
            case .right: watermark = CGRect(x: photo.maxX, y: top, width: right, height: photoSize.height)
            }
        }
        switch position {
        case .left: watermarkRotation = -.pi / 2
        case .right: watermarkRotation = .pi / 2
        default: watermarkRotation = 0
        }
    }
}

enum PhotoDecorationRenderer {
    /// Preview and full-resolution export share this renderer, so text and placement match.
    static func render(_ data: Data, metadata: CaptureMetadata, decoration: PhotoDecoration, maxPixel: Int? = nil) throws -> Data {
        let text = decoration.watermark(for: metadata)
        if decoration.frame == .none, text.isEmpty, maxPixel == nil { return data }
        let sourceImage = try LibraryImages.image(data, maxPixel: maxPixel)
        let size = CGSize(width: sourceImage.width, height: sourceImage.height)
        let layout = DecorationLayout(photoSize: size, frame: decoration.frame, position: decoration.position, hasWatermark: !text.isEmpty)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: layout.canvas, format: format)
        let image = renderer.image { context in
            let ink: UIColor = decoration.frame == .galleryBlack ? .white : UIColor(white: 0.15, alpha: 1)
            let paper: UIColor = decoration.frame == .galleryBlack ? UIColor(white: 0.055, alpha: 1) : UIColor(white: 0.97, alpha: 1)
            paper.setFill()
            context.fill(CGRect(origin: .zero, size: layout.canvas))
            UIImage(cgImage: sourceImage).draw(in: layout.photo)
            guard !text.isEmpty else { return }
            let graphics = context.cgContext
            graphics.saveGState()
            graphics.translateBy(x: layout.watermark.midX, y: layout.watermark.midY)
            graphics.rotate(by: layout.watermarkRotation)
            let rotated = layout.watermarkRotation != 0
            let available = CGSize(width: rotated ? layout.watermark.height : layout.watermark.width,
                                   height: rotated ? layout.watermark.width : layout.watermark.height)
            let localRect = CGRect(x: -available.width / 2, y: -available.height / 2, width: available.width, height: available.height)
            let edge = min(size.width, size.height)
            if decoration.frame == .none {
                UIColor.black.withAlphaComponent(0.45).setFill()
                UIBezierPath(roundedRect: localRect, cornerRadius: edge * 0.01).fill()
            }
            let padding = edge * 0.02
            let textWidth = max(available.width - 2 * padding, 1)
            var fontSize = edge * 0.026
            var font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
            let measured = (text as NSString).size(withAttributes: [.font: font]).width
            if measured > textWidth {
                fontSize = max(edge * 0.012, fontSize * textWidth / measured)
                font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let textRect = CGRect(x: -textWidth / 2, y: -font.lineHeight / 2, width: textWidth, height: font.lineHeight * 1.2)
            (text as NSString).draw(in: textRect, withAttributes: [
                .font: font, .foregroundColor: decoration.frame == .none ? UIColor.white : ink,
                .paragraphStyle: paragraph
            ])
            graphics.restoreGState()
        }
        guard let result = image.cgImage else { throw LibraryImages.ImageError.invalidImage }
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
        return try LibraryImages.jpeg(result, metadata: properties)
    }
}
