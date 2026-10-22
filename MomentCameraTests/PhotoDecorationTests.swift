import XCTest
import ImageIO
import UIKit
@testable import MomentCamera

final class PhotoDecorationTests: XCTestCase {
    private let metadata = CaptureMetadata(capturedAt: Date(timeIntervalSince1970: 0),
                                           timeZoneIdentifier: "Asia/Shanghai", deviceModel: "iPhone 15 Pro", city: "杭州")

    func testWatermarkUsesCaptureTimeZoneAndOnlySelectedFields() {
        var settings = PhotoDecoration()
        XCTAssertEqual(settings.watermark(for: metadata), "")
        settings.watermarkEnabled = true
        settings.showDevice = false
        XCTAssertEqual(settings.watermark(for: metadata), "1970.01.01 08:00")
        settings.showDate = false
        settings.showCity = true
        XCTAssertEqual(settings.watermark(for: metadata), "杭州")
        settings.cityOverride = "  上海  "
        XCTAssertEqual(settings.watermark(for: metadata), "上海")
    }

    func testUnknownCaptureDateAndCityAreNotInvented() {
        var settings = PhotoDecoration()
        settings.watermarkEnabled = true
        settings.showDevice = false
        settings.showCity = true
        let unknown = CaptureMetadata(capturedAt: nil, timeZoneIdentifier: "UTC", deviceModel: "未知设备", city: nil)
        XCTAssertEqual(settings.watermark(for: unknown), "")
    }

    func testNoDecorationReturnsOriginalBytes() throws {
        let original = try inputPhoto()
        XCTAssertEqual(try PhotoDecorationRenderer.render(original, metadata: metadata, decoration: PhotoDecoration()), original)
    }

    func testFramesExpandCanvasWithoutCroppingThePhotograph() throws {
        let input = try inputPhoto()
        for frame in PhotoFrame.allCases where frame != .none {
            var settings = PhotoDecoration()
            settings.frame = frame
            let result = try PhotoDecorationRenderer.render(input, metadata: metadata, decoration: settings)
            let image = try LibraryImages.image(result)
            XCTAssertGreaterThan(image.width, 400)
            XCTAssertGreaterThan(image.height, 300)
            let center = try color(result, x: image.width / 2, y: image.height / 2)
            XCTAssertGreaterThan(center.red, 0.8)
            XCTAssertLessThan(center.green, 0.2)
        }
    }

    func testWatermarkActuallyRendersAtEachSelectedEdge() throws {
        let input = try inputPhoto()
        for position in WatermarkPosition.allCases {
            var settings = PhotoDecoration()
            settings.frame = .galleryWhite
            settings.watermarkEnabled = true
            settings.showDevice = true
            settings.showDate = false
            settings.position = position
            let plainSettings = PhotoDecoration(frame: .galleryWhite)
            let output = try PhotoDecorationRenderer.render(input, metadata: metadata, decoration: settings)
            let image = try LibraryImages.image(output)
            let layout = DecorationLayout(photoSize: CGSize(width: 400, height: 300), frame: settings.frame,
                                          position: position, hasWatermark: true)
            XCTAssertEqual(image.width, Int(ceil(layout.canvas.width)))
            XCTAssertEqual(image.height, Int(ceil(layout.canvas.height)))
            let darkPixels = try countDarkPixels(output, in: layout.watermark)
            XCTAssertGreaterThan(darkPixels, 5, "Watermark text must be visible on \(position)")
            XCTAssertEqual(plainSettings.watermark(for: metadata), "")
        }
    }

    func testDecorationPreviewAndExportHaveTheSameAspectRatio() throws {
        let input = try inputPhoto()
        var settings = PhotoDecoration()
        settings.frame = .instant
        settings.watermarkEnabled = true
        settings.showCity = true
        settings.position = .right
        let full = try LibraryImages.image(PhotoDecorationRenderer.render(input, metadata: metadata, decoration: settings))
        let preview = try LibraryImages.image(PhotoDecorationRenderer.render(input, metadata: metadata, decoration: settings, maxPixel: 200))
        XCTAssertEqual(Double(full.width) / Double(full.height), Double(preview.width) / Double(preview.height), accuracy: 0.015)
    }

    private func inputPhoto() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 1))
    }

    private func pixels(_ data: Data) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let image = try LibraryImages.image(data)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: 0, y: CGFloat(image.height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (bytes, image.width, image.height)
    }

    private func color(_ data: Data, x: Int, y: Int) throws -> (red: Double, green: Double) {
        let image = try pixels(data)
        let offset = (y * image.width + x) * 4
        return (Double(image.bytes[offset]) / 255, Double(image.bytes[offset + 1]) / 255)
    }

    private func countDarkPixels(_ data: Data, in rect: CGRect) throws -> Int {
        let image = try pixels(data)
        var count = 0
        for y in max(0, Int(ceil(rect.minY)))..<min(image.height, Int(floor(rect.maxY))) {
            for x in max(0, Int(ceil(rect.minX)))..<min(image.width, Int(floor(rect.maxX))) {
                let offset = (y * image.width + x) * 4
                if image.bytes[offset] < 120 && image.bytes[offset + 1] < 120 && image.bytes[offset + 2] < 120 { count += 1 }
            }
        }
        return count
    }
}
