// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import AppKit
import UniformTypeIdentifiers

struct ComicPage: Identifiable, Hashable, Sendable {
    let id: Int
    let url: URL
    let pixelSize: CGSize
    let pointSize: CGSize

    static func == (lhs: ComicPage, rhs: ComicPage) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    var fileName: String { url.lastPathComponent }
    var baseName: String { url.deletingPathExtension().lastPathComponent }

    var number: Int { id + 1 }
}

struct ComicVolume: Sendable {
    let url: URL
    let pages: [ComicPage]

    var title: String { url.lastPathComponent }
    var count: Int { pages.count }
    var isEmpty: Bool { pages.isEmpty }

    func caption(for page: ComicPage) -> String {
        ambiguousBaseNames.contains(page.baseName) ? page.fileName : page.baseName
    }

    private var ambiguousBaseNames: Set<String> {
        var seen: Set<String> = []
        var repeated: Set<String> = []
        for page in pages where !seen.insert(page.baseName).inserted {
            repeated.insert(page.baseName)
        }
        return repeated
    }
}

enum VolumeScanner {

    static let pageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "tif", "heic", "heif", "avif",
    ]

    private static let headerConcurrency = 6

    private struct Header {
        let pixel: CGSize
        let point: CGSize
    }

    static func containsPages(_ url: URL) -> Bool {
        !(pageNames(in: url)?.isEmpty ?? true)
    }

    static func pageCount(of url: URL) async -> Int {
        await Task.detached(priority: .utility) { pageNames(in: url)?.count ?? 0 }.value
    }

    static func scan(_ url: URL) async -> ComicVolume? {
        await Task.detached(priority: .userInitiated) {
            guard let names = pageNames(in: url) else { return nil }
            let urls = names.map { url.appendingPathComponent($0) }
            let headers = await readHeaders(urls)
            let pages = urls.enumerated().map { offset, fileURL in
                let found = headers[offset]
                return ComicPage(
                    id: offset,
                    url: fileURL,
                    pixelSize: found?.pixel ?? CGSize(width: 1, height: 1),
                    pointSize: found?.point ?? CGSize(width: 1, height: 1)
                )
            }
            return ComicVolume(url: url, pages: pages)
        }.value
    }

    static func siblingVolumes(of url: URL) async -> [URL] {
        await Task.detached(priority: .utility) {
            let parent = url.deletingLastPathComponent()
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return contents
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .filter { !(pageNames(in: $0)?.isEmpty ?? true) }
                .sorted { NaturalOrder.isBefore($0.lastPathComponent, $1.lastPathComponent) }
        }.value
    }

    private static func pageNames(in url: URL) -> [String]? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue,
              let names = try? FileManager.default.contentsOfDirectory(atPath: url.path)
        else { return nil }

        let pages = names
            .filter { !$0.hasPrefix(".") }
            .filter { pageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted(by: NaturalOrder.isBefore)
        return pages.isEmpty ? nil : pages
    }

    private static func readHeaders(_ urls: [URL]) async -> [Header?] {
        await withTaskGroup(of: (Int, Header?).self) { group in
            var headers = [Header?](repeating: nil, count: urls.count)
            var cursor = 0
            while cursor < min(headerConcurrency, urls.count) {
                let index = cursor
                cursor += 1
                group.addTask { (index, header(of: urls[index])) }
            }
            while let (index, found) = await group.next() {
                headers[index] = found
                if cursor < urls.count {
                    let next = cursor
                    cursor += 1
                    group.addTask { (next, header(of: urls[next])) }
                }
            }
            return headers
        }
    }

    private static func header(of url: URL) -> Header? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let w = props[kCGImagePropertyPixelWidth] as? Double
        let h = props[kCGImagePropertyPixelHeight] as? Double
        guard let w, let h, w > 0, h > 0 else { return nil }

        let xdpi = (props[kCGImagePropertyDPIWidth] as? Double) ?? 0
        let ydpi = (props[kCGImagePropertyDPIHeight] as? Double) ?? 0
        let saneX = (xdpi >= 24 && xdpi <= 1200) ? xdpi : 72
        let saneY = (ydpi >= 24 && ydpi <= 1200) ? ydpi : 72

        return Header(
            pixel: CGSize(width: w, height: h),
            point: CGSize(width: w * 72.0 / saneX, height: h * 72.0 / saneY)
        )
    }
}

