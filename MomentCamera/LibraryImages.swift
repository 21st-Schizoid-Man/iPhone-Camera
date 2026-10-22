import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum LibraryImages {
    static func image(_ data: Data, maxPixel: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ImageError.invalidImage }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let width = properties?[kCGImagePropertyPixelWidth as String] as? Int ?? 4096
        let height = properties?[kCGImagePropertyPixelHeight as String] as? Int ?? 4096
        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: maxPixel ?? max(width, height),
            kCGImageSourceShouldCacheImmediately as String: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ImageError.invalidImage }
        return image
    }

    static func jpeg(_ image: CGImage, metadata: [String: Any] = [:]) throws -> Data {
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageError.invalidImage
        }
        var properties = metadata
        properties[kCGImagePropertyOrientation as String] = 1
        properties[kCGImagePropertyPixelWidth as String] = image.width
        properties[kCGImagePropertyPixelHeight as String] = image.height
        properties[kCGImageDestinationLossyCompressionQuality as String] = 0.95
        properties.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
        if var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = image.width
            exif[kCGImagePropertyExifPixelYDimension as String] = image.height
            properties[kCGImagePropertyExifDictionary as String] = exif
        }
        if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            properties[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.invalidImage }
        return result as Data
    }

    static func thumbnail(_ data: Data) throws -> Data { try jpeg(image(data, maxPixel: 480)) }

    static func videoThumbnail(_ url: URL) -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return try? jpeg(image)
    }

    static func fileExtension(_ data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source), let value = UTType(type as String) else { return "jpg" }
        return value.preferredFilenameExtension ?? "jpg"
    }

    enum ImageError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "无法读取或生成照片，请保留原片后重试。" }
    }
}
