import CoreImage
import UIKit
import Vision

/// Half of Apple's product photos are JPEGs on white: a white box in dark mode and behind glass.
/// Cuts the phones out on device, once per photo. Vision's subject lifting (Neural Engine) gives soft edges;
/// a flood fill of the white backdrop keeps white phones solid, which Vision alone drops, and clears anything left on it.
nonisolated enum Cutout {
    private static let folder = URL.cachesDirectory.appending(path: "Cutouts", directoryHint: .isDirectory)
    private static let context = CIContext()
    nonisolated(unsafe) private static let memory = NSCache<NSURL, UIImage>() // NSCache is thread-safe
    private static let maxPixels: CGFloat = 1200 // detail photo width at 3x; also keeps the flood fill fast

    /// Already-loaded result, so rows that scroll back into view don't flash the placeholder.
    static func cached(_ url: URL?) -> UIImage? {
        url.flatMap { memory.object(forKey: $0 as NSURL) }
    }

    @concurrent static func image(for url: URL) async throws -> UIImage {
        if let image = cached(url) { return image }
        let file = folder.appending(path: (url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") + ".png")
        if let image = UIImage(contentsOfFile: file.path(percentEncoded: false)) {
            memory.setObject(image, forKey: url as NSURL)
            return image
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let original = UIImage(data: data), let originalCG = original.cgImage else { throw URLError(.cannotDecodeContentData) }
        let scale = min(1, maxPixels / CGFloat(max(originalCG.width, originalCG.height)))
        let size = CGSize(width: CGFloat(originalCG.width) * scale, height: CGFloat(originalCG.height) * scale)
        let resized = original.preparingThumbnail(of: size) ?? original
        var image = resized
        if [.none, .noneSkipFirst, .noneSkipLast].contains(originalCG.alphaInfo), let source = resized.cgImage {
            // Opaque photo: cut it out and keep the result, since this is the expensive part.
            image = UIImage(cgImage: await cutOut(source))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? image.pngData()?.write(to: file)
        }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    /// The photo with its white backdrop made transparent; unchanged if it has no white border.
    static func cutOut(_ source: CGImage) async -> CGImage {
        let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        guard let backdrop = foregroundMask(source) else { return source }
        var mask = backdrop
        let handler = ImageRequestHandler(source)
        if let observation = try? await handler.perform(GenerateForegroundInstanceMaskRequest()),
           let lifted = try? observation.generateScaledMask(for: observation.allInstances, scaledToImageFrom: handler) {
            let inner = backdrop.applyingFilter("CIMorphologyMinimum", parameters: ["inputRadius": 2]).cropped(to: extent)
            let outer = backdrop.applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": 2]).cropped(to: extent)
            // Vision's soft edges, solid interiors from the flood fill, nothing out on the backdrop.
            mask = CIImage(cvPixelBuffer: lifted)
                .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: inner])
                .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: outer])
        } // else (e.g. no Neural Engine in the simulator): the flood fill alone, with harder edges.
        let output = CIImage(cgImage: source)
            .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask])
        return context.createCGImage(output, from: extent) ?? source
    }

    /// White everywhere except the backdrop: near-white pixels connected to the image border.
    private static func foregroundMask(_ image: CGImage) -> CIImage? {
        let width = image.width, height = image.height
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var mask = [UInt8](repeating: 255, count: width * height)
        var stack = Array(0..<width) + Array((height - 1) * width..<height * width)
            + Array(stride(from: 0, to: width * height, by: width)) + Array(stride(from: width - 1, to: width * height, by: width))
        while let i = stack.popLast() {
            // 235: JPEG noise keeps Apple's white a little under 255; phone outlines are far darker.
            guard mask[i] == 255, min(pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2]) >= 235 else { continue }
            mask[i] = 0
            let x = i % width
            if x > 0 { stack.append(i - 1) }
            if x < width - 1 { stack.append(i + 1) }
            if i >= width { stack.append(i - width) }
            if i < width * (height - 1) { stack.append(i + width) }
        }
        return CIImage(bitmapData: Data(mask), bytesPerRow: width, size: CGSize(width: width, height: height), format: .L8, colorSpace: nil)
    }
}
