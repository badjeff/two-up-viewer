// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import AppKit
import ImageIO
import UniformTypeIdentifiers

final class CGImageBox: NSObject, @unchecked Sendable {
    let image: CGImage
    let decodedPixelSize: CGSize
    let dpi: CGSize

    init(image: CGImage, decodedPixelSize: CGSize, dpi: CGSize) {
        self.image = image
        self.decodedPixelSize = decodedPixelSize
        self.dpi = dpi
    }
}

final class ImageCache: @unchecked Sendable {
    private let cache = NSCache<NSString, CGImageBox>()

    init(countLimit: Int, totalCostLimit: Int) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func object(forKey key: String) -> CGImageBox? {
        cache.object(forKey: key as NSString)
    }

    func setObject(_ box: CGImageBox, forKey key: String, cost: Int) {
        cache.setObject(box, forKey: key as NSString, cost: cost)
    }
}

actor ImagePipeline {

    static let shared = ImagePipeline()

    private let cache = ImageCache(countLimit: 48, totalCostLimit: 320 * 1024 * 1024)
    private let thumbCache = ImageCache(countLimit: 900, totalCostLimit: 180 * 1024 * 1024)

    func image(at url: URL, targetPixels: Double?, thumbnail: Bool = false) async -> CGImageBox? {
        let bucket = Self.bucket(for: targetPixels)
        let key = "\(url.path)#\(bucket)"
        let store = thumbnail ? thumbCache : cache

        if let hit = store.object(forKey: key) { return hit }

        guard !Task.isCancelled else { return nil }

        let decoded: CGImageBox? = await Task.detached(priority: .userInitiated) { [weak self] in
            self?.decode(url: url, maxPixelSize: bucket, cache: store, key: key)
        }.value

        return decoded
    }

    private nonisolated func decode(
        url: URL,
        maxPixelSize: Int,
        cache: ImageCache,
        key: String
    ) -> CGImageBox? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false,
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let props = (CGImageSourceCopyProperties(source, sourceOptions as CFDictionary)
                        as? [CFString: Any]) ?? [:]
        let nativeMax = max(
            (props[kCGImagePropertyPixelWidth] as? Int) ?? 0,
            (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        )

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
        ]

        let requested = min(maxPixelSize, nativeMax > 0 ? nativeMax : maxPixelSize)
        options[kCGImageSourceThumbnailMaxPixelSize] = max(1, requested)

        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            guard let raw = CGImageSourceCreateImageAtIndex(source, 0, sourceOptions as CFDictionary)
            else { return nil }
            let dpi = Self.dpi(from: props, pixels: CGSize(width: raw.width, height: raw.height))
            let box = CGImageBox(image: raw,
                                 decodedPixelSize: CGSize(width: raw.width, height: raw.height),
                                 dpi: dpi)
            cache.setObject(box, forKey: key, cost: Self.cost(of: raw))
            return box
        }

        let dpi = Self.dpi(from: props, pixels: CGSize(width: cg.width, height: cg.height))
        let box = CGImageBox(image: cg,
                             decodedPixelSize: CGSize(width: cg.width, height: cg.height),
                             dpi: dpi)
        cache.setObject(box, forKey: key, cost: Self.cost(of: cg))
        return box
    }

    private nonisolated static func cost(of cg: CGImage) -> Int {
        cg.bytesPerRow * cg.height
    }

    private nonisolated static func dpi(from props: [CFString: Any], pixels: CGSize) -> CGSize {
        let x = (props[kCGImagePropertyDPIWidth] as? Double) ?? 0
        let y = (props[kCGImagePropertyDPIHeight] as? Double) ?? 0
        let saneX = (x >= 24 && x <= 1200) ? x : 72
        let saneY = (y >= 24 && y <= 1200) ? y : 72
        return CGSize(width: saneX, height: saneY)
    }

    static func bucket(for targetPixels: Double?) -> Int {
        guard let targetPixels, targetPixels > 0 else { return 1 << 22 }
        var b = 128.0
        while b < targetPixels { b *= 2 }
        return Int(min(b, Double(1 << 22)))
    }

    private static let preloadRadius = 10

    nonisolated static func preloadIndices(around index: Int, slots: Int,
                                          pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        let firstVisible = min(max(index, 0), pageCount - 1)
        let lastVisible = min(max(index + max(0, slots - 1), firstVisible), pageCount - 1)

        var wanted: [Int] = []
        for distance in 1...preloadRadius {
            if lastVisible + distance <= pageCount - 1 { wanted.append(lastVisible + distance) }
            if firstVisible - distance >= 0 { wanted.append(firstVisible - distance) }
        }
        return wanted
    }

    func prefetch(volume: ComicVolume, around index: Int, slots: Int) async {
        guard !volume.pages.isEmpty else { return }
        let wanted = Self.preloadIndices(around: index,
                                         slots: slots,
                                         pageCount: volume.pages.count)
        guard !wanted.isEmpty else { return }

        for i in wanted {
            if Task.isCancelled { return }
            _ = await image(at: volume.pages[i].url,
                            targetPixels: Self.prefetchPixels,
                            thumbnail: true)
        }
    }

    private static let prefetchPixels = 512.0

    nonisolated func thumbnail(at url: URL, longEdge: Double) async -> CGImageBox? {
        await image(at: url, targetPixels: longEdge, thumbnail: true)
    }
}

