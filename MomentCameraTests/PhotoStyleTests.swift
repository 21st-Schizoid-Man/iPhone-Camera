import XCTest
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import MomentCamera

final class PhotoStyleTests: XCTestCase {
    func testNormalModePreservesOriginalBytes() throws {
        let data = try makeJPEG(orientation: 1)
        XCTAssertEqual(try PhotoStyle.normal.render(data), data)
    }

    func testEveryFilmStyleProducesADecodableDistinctImage() throws {
        let data = try makeJPEG(orientation: 1)
        let baseline = try pixels(data)
        var results: Set<Data> = []
        for style in PhotoStyle.allCases where style != .normal {
            let rendered = try style.render(data)
            let image = try XCTUnwrap(UIImage(data: rendered))
            XCTAssertEqual(image.size.width, 80)
            XCTAssertEqual(image.size.height, 40)
            XCTAssertNotEqual(try pixels(rendered), baseline, "\(style) must affect the actual image")
            results.insert(try pixels(rendered))
        }
        XCTAssertEqual(results.count, 3, "Each film style should have a distinct rendering")
    }

    func testFilmProcessingNormalizesPortraitOrientationWithoutLosingExposureMetadata() throws {
        let input = try makeJPEG(orientation: 6)
        let output = try PhotoStyle.warmNegative.render(input)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 40)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 80)
        XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 1)
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(exif[kCGImagePropertyExifExposureTime as String] as? Double), 1.0 / 125, accuracy: 0.0001)
    }

    func testFilmProcessingRejectsCorruptCaptureData() {
        for style in PhotoStyle.allCases where style != .normal {
            XCTAssertThrowsError(try style.render(Data("not an image".utf8)))
        }
    }

    private func makeJPEG(orientation: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format)
        let image = renderer.image { context in
            UIColor(red: 0.7, green: 0.3, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            UIColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 40, y: 0, width: 40, height: 40))
        }
        let result = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [
            kCGImagePropertyOrientation as String: orientation,
            kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifExposureTime as String: 1.0 / 125]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return result as Data
    }

    private func pixels(_ data: Data) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var buffer = Data(count: image.width * image.height * 4)
        try buffer.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return buffer
    }
}
