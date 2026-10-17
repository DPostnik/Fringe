import AppKit
import QuickLookThumbnailing

/// In-memory thumbnails, kept across panel openings; NSCache drops them under memory pressure.
@MainActor final class ThumbnailCache {
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 90 }

    func cached(_ item: ScreenshotItem) -> NSImage? { cache.object(forKey: item.cacheKey as NSString) }

    func thumbnail(for item: ScreenshotItem, size: CGSize, scale: CGFloat) async -> NSImage? {
        if let image = cached(item) { return image }
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: size, scale: scale, representationTypes: .thumbnail)
        guard let cgImage = await Self.generate(request) else { return nil }
        let image = NSImage(cgImage: cgImage, size: CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
        cache.setObject(image, forKey: item.cacheKey as NSString)
        return image
    }

    private nonisolated static func generate(_ request: QLThumbnailGenerator.Request) async -> CGImage? {
        await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.cgImage)
            }
        }
    }
}
