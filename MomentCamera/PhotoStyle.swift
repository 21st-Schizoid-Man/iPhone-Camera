import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

enum PhotoStyle: String, CaseIterable, Identifiable {
    case normal = "正常"
    case warmNegative = "暖调负片"
    case coolSlide = "冷调反转片"
    case monochrome = "黑白胶片"

    var id: Self { self }

    /// Applied to the captured full-resolution image, never a screenshot of the preview.
    func render(_ data: Data) throws -> Data {
        guard self != .normal else { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let original = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw RenderError.invalidImage
        }
        var image = original
        switch self {
        case .normal: break
        case .warmNegative:
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.82, kCIInputContrastKey: 0.92
            ])
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 7200, y: 8)
            ])
            image = image.applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0.045),
                "inputPoint1": CIVector(x: 0.25, y: 0.23),
                "inputPoint2": CIVector(x: 0.5, y: 0.52),
                "inputPoint3": CIVector(x: 0.75, y: 0.79),
                "inputPoint4": CIVector(x: 1, y: 0.97)
            ])
        case .coolSlide:
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.12, kCIInputContrastKey: 1.12
            ])
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 5900, y: -5)
            ])
        case .monochrome:
            image = image.applyingFilter("CIPhotoEffectNoir")
        }
        image = image.applyingFilter("CIVignette", parameters: [
            kCIInputIntensityKey: 0.28, kCIInputRadiusKey: 1.8
        ])
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let output = context.createCGImage(image, from: original.extent) else {
            throw RenderError.invalidImage
        }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RenderError.invalidImage
        }
        var metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        metadata[kCGImagePropertyOrientation as String] = 1
        metadata[kCGImagePropertyPixelWidth as String] = output.width
        metadata[kCGImagePropertyPixelHeight as String] = output.height
        metadata[kCGImageDestinationLossyCompressionQuality as String] = 0.95
        if var tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            metadata[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        CGImageDestinationAddImage(destination, output, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.invalidImage }
        return result as Data
    }

    private enum RenderError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "无法处理胶片风格照片，原片将保留。" }
    }
}
