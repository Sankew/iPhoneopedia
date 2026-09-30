import CoreGraphics
import Testing
@testable import iPhoneopedia

struct CutoutTests {
    /// A white phone (white body, gray outline) on Apple's white backdrop: the backdrop goes, the phone stays solid.
    @Test func whitePhoneOnWhiteKeepsPhoneAndClearsBackdrop() async throws {
        let photo = try #require(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 800,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        photo.setFillColor(gray: 1, alpha: 1)
        photo.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        photo.setStrokeColor(gray: 0.5, alpha: 1)
        photo.setLineWidth(4)
        photo.stroke(CGRect(x: 60, y: 30, width: 80, height: 140))

        let cut = await Cutout.cutOut(try #require(photo.makeImage()))
        #expect(try alpha(of: cut, x: 5, y: 5) == 0)
        #expect(try alpha(of: cut, x: 100, y: 100) == 255)
    }

    private func alpha(of image: CGImage, x: Int, y: Int) throws -> UInt8 {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return pixel[3]
    }
}
