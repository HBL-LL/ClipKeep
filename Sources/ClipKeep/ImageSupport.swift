import AppKit
import CryptoKit
import ImageIO

/// A copied image converted to PNG, ready to store.
struct EncodedImage: Sendable {
    let png: Data
    let width: Int
    let height: Int
    let sha256: String
}

enum ImageEncoder {
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    /// Converts PNG or TIFF clipboard data to PNG. Safe to call off the main thread.
    static func encode(_ data: Data) -> EncodedImage? {
        guard let rep = NSBitmapImageRep(data: data), rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
            return nil
        }
        let png: Data
        if data.starts(with: pngSignature) {
            png = data
        } else if let converted = rep.representation(using: .png, properties: [:]) {
            png = converted
        } else {
            return nil
        }
        return EncodedImage(png: png, width: rep.pixelsWide, height: rep.pixelsHigh, sha256: pixelHash(rep) ?? fileHash(png))
    }

    /// Hashes decoded pixels, so the same picture copied as PNG or as TIFF matches.
    private static func pixelHash(_ rep: NSBitmapImageRep) -> String? {
        guard !rep.isPlanar, let pixels = rep.bitmapData else { return nil }
        var hasher = SHA256()
        withUnsafeBytes(of: (rep.pixelsWide, rep.pixelsHigh, rep.bitsPerPixel)) { hasher.update(bufferPointer: $0) }
        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: pixels, count: rep.bytesPerRow * rep.pixelsHigh))
        return hex(hasher.finalize())
    }

    private static func fileHash(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Small previews for the list, decoded once and cached.
@MainActor
enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func thumbnail(for url: URL, maxPixels: Int = 240) -> NSImage? {
        let key = url.lastPathComponent as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
        cache.setObject(image, forKey: key)
        return image
    }

    static func forget(_ fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
    }
}
