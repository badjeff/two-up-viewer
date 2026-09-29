// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import SwiftUI
import AppKit

struct ThumbnailCell: View {
    let page: ComicPage
    let isCurrent: Bool
    let width: CGFloat
    var captionText: String?

    @State private var image: CGImage?
    @State private var failed = false

    private var height: CGFloat {
        let ratio = page.pointSize.height / max(1, page.pointSize.width)
        return width * ratio
    }

    var body: some View {
        VStack(spacing: 3) {
            thumbnail
            caption
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))

            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: height)
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(
                    isCurrent ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: isCurrent ? 2.5 : 0.5
                )
        }
        .shadow(color: .black.opacity(isCurrent ? 0.35 : 0.15), radius: 2, y: 1)
        .task(id: LoadKey(page: page.id, bucket: bucket)) { await load() }
        .help(page.fileName)
        .accessibilityLabel("Page \(page.number)")
    }

    private static var backingScale: Double {
        Double(NSScreen.main?.backingScaleFactor ?? 2)
    }

    private var longEdge: Double { width * Self.backingScale * 1.5 }

    private var bucket: Int { ImagePipeline.bucket(for: longEdge) }

    private var caption: some View {
        Text(text)
            .font(.system(size: Self.captionSize, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity)
    }

    private var text: String { captionText ?? page.baseName }

    private static let captionSize: CGFloat = 11

    private func load() async {
        guard let box = await ImagePipeline.shared.thumbnail(at: page.url, longEdge: longEdge)
        else {
            failed = true
            return
        }
        image = box.image
    }

    private struct LoadKey: Hashable {
        let page: Int
        let bucket: Int
    }
}

struct ThumbnailSidebar: View {
    @ObservedObject var model: ViewerModel

    @State private var highlighted: Int?
    @State private var visibleRows: [Int] = []
    @State private var settleTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            VolumePicker(model: model)
            Divider()
            pageStrip
        }
        .frame(width: model.sidebarWidth)
        .background(.regularMaterial)
    }

    private var pageStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { number, row in
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(displayOrder(row), id: \.id) { page in
                                ThumbnailCell(
                                    page: page,
                                    isCurrent: highlightedPages.contains(page.id),
                                    width: thumbWidth,
                                    captionText: model.volume.caption(for: page)
                                )
                                .onTapGesture { tap(page.id) }
                            }
                        }
                        .id(number)
                        .onAppear { trackRow(number, shown: true) }
                        .onDisappear { trackRow(number, shown: false) }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }
            .onAppear { highlighted = model.currentPage }
            .onDisappear { settleTask?.cancel() }
            .onChange(of: model.currentPage) { page in
                guard !model.currentPageCameFromScroll else { return }
                settleTask?.cancel()
                highlight(page, in: proxy)
            }
            .onChange(of: model.scrollRestToken) { _ in
                settleTask?.cancel()
                settleTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.settleDelay)
                    guard !Task.isCancelled else { return }
                    highlight(model.currentPage, in: proxy)
                }
            }
        }
    }

    private static let settleDelay: UInt64 = 600_000_000

    private func highlight(_ page: Int, in proxy: ScrollViewProxy) {
        highlighted = page
        let row = page / max(1, model.layout.columns)
        if visibleRows.contains(row) { return }
        let anchor: UnitPoint
        if let first = visibleRows.first, row < first {
            anchor = .bottom
        } else if let last = visibleRows.last, row > last {
            anchor = .top
        } else {
            anchor = .center
        }
        withAnimation(.smooth(duration: 0.3)) {
            proxy.scrollTo(row, anchor: anchor)
        }
    }

    private var highlightedPages: Set<Int> {
        guard let page = highlighted else { return [] }
        return Set(model.indices(ofSpreadStartingAt: page))
    }

    private func trackRow(_ number: Int, shown: Bool) {
        if shown {
            guard !visibleRows.contains(number) else { return }
            visibleRows.append(number)
            visibleRows.sort()
        } else {
            visibleRows.removeAll { $0 == number }
        }
    }

    private var rows: [[ComicPage]] {
        let pages = model.volume.pages
        let perRow = model.layout.columns
        guard perRow > 1 else { return pages.map { [$0] } }
        return stride(from: 0, to: pages.count, by: perRow).map {
            Array(pages[$0..<min($0 + perRow, pages.count)])
        }
    }

    private func displayOrder(_ row: [ComicPage]) -> [ComicPage] {
        model.spreadOrder == .rightToLeft ? row.reversed() : row
    }

    private func tap(_ index: Int) {
        model.go(to: snapTarget(for: index))
    }

    private var thumbWidth: CGFloat {
        let available = model.sidebarWidth - 16 - (model.layout.columns > 1 ? 8 : 0)
        let perCell = available / CGFloat(model.layout.columns)
        return max(44, min(perCell, 118))
    }

    private func snapTarget(for index: Int) -> Int {
        guard model.layout == .twoUp else { return index }
        return index - (index % 2)
    }
}

struct VolumePicker: View {
    @ObservedObject var model: ViewerModel
    @State private var siblings: [URL] = []
    @State private var counts: [URL: Int] = [:]
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "books.vertical")
                        .foregroundStyle(.secondary)
                    Text(model.volume.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text("\(model.pageCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .help("Switch volume")

            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(siblings, id: \.self) { url in
                            VolumeRow(
                                url: url,
                                isCurrent: url == model.volume.url,
                                count: counts[url] ?? 0
                            ) {
                                AppRouter.shared.open(url)
                                isExpanded = false
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
                Divider()
            }
        }
        .task(id: model.volume.url) {
            let found = await VolumeScanner.siblingVolumes(of: model.volume.url)
            siblings = found
            var pageCounts: [URL: Int] = [:]
            for sibling in found {
                pageCounts[sibling] = await VolumeScanner.pageCount(of: sibling)
            }
            counts = pageCounts
        }
    }
}

private struct VolumeRow: View {
    let url: URL
    let isCurrent: Bool
    let count: Int
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .font(.caption)
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(size: 11))
                    if count > 0 {
                        Text("\(count) pages")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isCurrent ? Color.accentColor.opacity(0.16)
                          : (isHovering ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
