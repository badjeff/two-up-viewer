// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

// MARK: - Continuous canvas

final class ContinuousCanvas: NSView {

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    private var pages: [ComicPage] = []
    private var rects: [CGRect] = []
    private var rowBands: [CGRect] = []
    private var needsVisibleRepaint = false
    private var columns: Int = 1
    private var rotation: Double = 0
    private var scale: CGFloat = 1
    private var gutter: CGFloat = 18

    private var images: [Int: CGImage] = [:]

    var isZooming = false

    static let tileSize = 4

    private(set) var resolvedTiles: Set<Int> = []

    private func scheduleRepaint(_ rect: NSRect) {
        setNeedsDisplay(rect)
    }

    private(set) var needsRedecode = false

    static func tile(of index: Int) -> Int { index / tileSize }
    static func tileRange(_ tile: Int) -> Range<Int> {
        let lo = tile * tileSize
        return lo..<(lo + tileSize)
    }

    @discardableResult
    func layout(pages newPages: [ComicPage], scale: CGFloat, rotation: Double,
                columns: Int, rightToLeft: Bool, gutter: CGFloat,
                viewportWidth: CGFloat = 0) -> CGSize {
        let pagesChanged = newPages.count != pages.count
            || newPages.first?.url != pages.first?.url
        let scaleChanged = abs(scale - self.scale) > 0.001
        needsRedecode = false
        if pagesChanged || scaleChanged {
            if !isZooming {
                images.removeAll()
                resolvedTiles.removeAll()
            }
            needsRedecode = pagesChanged || scaleChanged
        }

        pages = newPages
        self.scale = scale
        self.rotation = rotation
        self.gutter = gutter
        self.columns = max(1, columns)

        let perRow = self.columns
        var rects: [CGRect] = []
        var rowBands: [CGRect] = []
        rects.reserveCapacity(pages.count)
        rowBands.reserveCapacity((pages.count + perRow - 1) / perRow)

        var sizes: [CGSize] = []
        sizes.reserveCapacity(pages.count)
        for page in pages {
            let size = page.rotatedPointSize(rotation: rotation)
            sizes.append(CGSize(width: size.width * scale, height: size.height * scale))
        }

        var contentWidth: CGFloat = 1
        var rowWidths: [CGFloat] = []
        for start in stride(from: 0, to: max(pages.count, 1), by: perRow) {
            let indices = start..<min(start + perRow, pages.count)
            let w = indices.reduce(CGFloat(0)) { $0 + sizes[$1].width }
                + gutter * CGFloat(max(0, indices.count - 1))
            rowWidths.append(w)
            contentWidth = max(contentWidth, w)
        }

        let inset = ViewerModel.canvasInset
        let canvasWidth = max(contentWidth + inset * 2, max(1, viewportWidth))
        let contentInset = inset + (canvasWidth - contentWidth - inset * 2) / 2

        var byIndex = [CGRect](repeating: .zero, count: pages.count)
        var y: CGFloat = inset

        for (row, start) in stride(from: 0, to: max(pages.count, 1), by: perRow).enumerated() {
            let indices = Array(start..<min(start + perRow, pages.count))
            let rowHeight = indices.reduce(CGFloat(0)) { max($0, sizes[$1].height) }

            let visual = rightToLeft ? indices.reversed() : indices
            let slack = contentInset + (indices.count == perRow
                ? (contentWidth - rowWidths[row]) / 2
                : (rightToLeft ? contentWidth - rowWidths[row] : 0))
            var x = slack
            for index in visual {
                let size = sizes[index]
                byIndex[index] = CGRect(x: x, y: y + (rowHeight - size.height) / 2,
                                        width: size.width, height: size.height)
                x += size.width + gutter
            }

            rowBands.append(CGRect(x: 0, y: y, width: canvasWidth, height: rowHeight))
            y += rowHeight + gutter
        }
        if !rowBands.isEmpty { y -= gutter }

        self.rects = byIndex
        self.rowBands = rowBands
        let contentSize = CGSize(width: max(canvasWidth, 1), height: max(y + inset, 1))
        frame = CGRect(origin: frame.origin, size: contentSize)
        needsVisibleRepaint = true
        needsLayout = true
        return contentSize
    }

    // MARK: - Queries

    func rect(at index: Int) -> CGRect {
        guard index >= 0, index < rects.count else { return .zero }
        return rects[index]
    }

    private func rowIndex(atOrBelow y: CGFloat) -> Int {
        var lo = 0, hi = rowBands.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if rowBands[mid].maxY <= y { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    func index(atTopOf rect: CGRect) -> Int {
        guard !rowBands.isEmpty else { return 0 }
        return min(rowIndex(atOrBelow: rect.minY) * columns, max(0, rects.count - 1))
    }

    func index(atCenterOf rect: CGRect) -> Int {
        guard !rowBands.isEmpty else { return 0 }
        return min(rowIndex(atOrBelow: rect.midY) * columns, max(0, rects.count - 1))
    }

    func scrollTargetY(for index: Int, viewportHeight: CGFloat) -> CGFloat {
        let row = index / max(1, columns)
        guard row >= 0, row < rowBands.count else { return 0 }
        let band = rowBands[row]
        guard band.height >= viewportHeight else {
            return max(0, band.midY - viewportHeight / 2)
        }
        return max(0, band.minY - ViewerModel.canvasInset)
    }

    func scrollTargetX(for index: Int, viewportWidth: CGFloat, rightToLeft: Bool) -> CGFloat {
        let perRow = max(1, columns)
        let row = min(max(index, 0) / perRow, max(0, rowBands.count - 1))
        let lo = row * perRow
        let hi = min(lo + perRow, rects.count)
        guard hi > lo else { return 0 }

        var left = CGFloat.greatestFiniteMagnitude
        var right = -CGFloat.greatestFiniteMagnitude
        for i in lo..<hi {
            left = min(left, rects[i].minX)
            right = max(right, rects[i].maxX)
        }

        let maxOrigin = max(0, frame.width - viewportWidth)
        let inset = ViewerModel.canvasInset
        guard right - left < viewportWidth else {
            let leading = rightToLeft ? right - viewportWidth + inset : left - inset
            return min(max(0, leading), maxOrigin)
        }
        return min(max(0, (frame.width - viewportWidth) / 2), maxOrigin)
    }

    func indices(intersecting rect: CGRect) -> Range<Int> {
        guard !rowBands.isEmpty, !rects.isEmpty else { return 0..<0 }
        let first = index(atTopOf: rect) / max(1, columns)
        var last = first
        while last < rowBands.count - 1, rowBands[last + 1].minY <= rect.maxY {
            last += 1
        }
        let lo = first * columns
        let hi = min((last + 1) * columns, rects.count)
        return lo..<max(lo, hi)
    }

    // MARK: - Decoded image bookkeeping

    func isTileResolved(_ tile: Int) -> Bool {
        let existing = Self.tileRange(tile).filter { $0 < rects.count }
        return !existing.isEmpty && existing.allSatisfy { images[$0] != nil }
    }

    func setImage(_ image: CGImage, for index: Int) {
        guard index < rects.count else { return }
        images[index] = image
        let tile = Self.tile(of: index)
        if !resolvedTiles.contains(tile), isTileResolved(tile) {
            resolvedTiles.insert(tile)
        }
        scheduleRepaint(rects[index].insetBy(dx: -40, dy: -40))
    }

    func pages(inRow row: Int) -> [Int] {
        let perRow = max(1, columns)
        let lo = max(0, row) * perRow
        let hi = min(lo + perRow, rects.count)
        return hi > lo ? Array(lo..<hi) : []
    }

    func evictTiles(_ tiles: Set<Int>) {
        var touched: [CGRect] = []
        for tile in tiles {
            resolvedTiles.remove(tile)
            for index in Self.tileRange(tile) where images[index] != nil {
                if index < rects.count { touched.append(rects[index]) }
                images.removeValue(forKey: index)
            }
        }
        for rect in touched {
            scheduleRepaint(rect.insetBy(dx: -40, dy: -40))
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard !rects.isEmpty else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        for index in indices(intersecting: dirtyRect) {
            guard index < rects.count, index < pages.count else { continue }
            let rect = rects[index]

            if let image = images[index] {
                ctx.saveGState()
                ctx.setStrokeColor(NSColor(white: 0.5, alpha: 0.3).cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
                ctx.restoreGState()

                PageDrawing.draw(image, in: rect, rotation: rotation, ctx: ctx)
            } else {
                PageDrawing.drawPlaceholder(number: pages[index].number,
                                           in: rect, ctx: ctx)
            }
        }
    }

    override func layout() {
        super.layout()
        guard needsVisibleRepaint else { return }
        needsVisibleRepaint = false
        scheduleRepaint(visibleRect)
    }

    // MARK: - Navigation by click

    override func mouseDown(with event: NSEvent) {
        onAdvance?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRetreat?()
    }

    var onAdvance: (() -> Void)?
    var onRetreat: (() -> Void)?
}

    // MARK: - Continuous scroll view

final class ContinuousScrollView: NSScrollView {

    private lazy var canvas = ContinuousCanvas()

    private var volume: ComicVolume?
    private var lastIndexReported = -1
    private var isProgrammaticScroll = false
    private var programmaticScrollToken = 0

    private var isScrolling = false
    private var lastScrollAt: CFTimeInterval = 0
    private var scrollSettle: Task<Void, Never>?
    private var lastReportedOrigin: CGPoint?
    private var isZooming = false
    private weak var magnifyGesture: NSMagnificationGestureRecognizer?

    private var isMoving: Bool { isScrolling || isProgrammaticScroll }
    private var canvasColumns = 1

    private static let scrollSettleDelay: CFTimeInterval = 0.28

    var onIndexChange: ((Int) -> Void)?
    var onNavigate: ((Int) -> Void)?
    var onScrollRest: (() -> Void)?

    var onScalePinned: ((CGFloat) -> Void)?
    var onViewportChanged: ((CGSize) -> Void)?

    var currentVolumeURL: URL? { volume?.url }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        allowsMagnification = false
        hasVerticalScroller = true
        hasHorizontalScroller = true
        scrollerStyle = .overlay
        drawsBackground = false
        contentView.drawsBackground = false
        documentView = canvas

        canvas.onAdvance = { [weak self] in self?.onNavigate?(1) }
        canvas.onRetreat = { [weak self] in self?.onNavigate?(-1) }

        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsChanged),
            name: NSView.boundsDidChangeNotification, object: contentView
        )
        let magnify = NSMagnificationGestureRecognizer(target: self,
                                                      action: #selector(handleMagnify(_:)))
        addGestureRecognizer(magnify)
        magnifyGesture = magnify
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private var viewport: CGSize {
        let bounds = contentView.bounds.size
        return CGSize(width: max(1, bounds.width), height: max(1, bounds.height))
    }

    // MARK: - Content

    func setVolume(_ volume: ComicVolume) {
        self.volume = volume
        lastIndexReported = -1
        cancelAllTasks()
    }

    private func cancelAllTasks() {
        for group in tasks.values { group.forEach { $0.cancel() } }
        tasks.removeAll()
        wantedTiles.removeAll()
    }

    @discardableResult
    func setLayout(scale: CGFloat, rotation: Double, columns: Int,
                   rightToLeft: Bool, gutter: CGFloat = 18) -> CGSize {
        lastLayoutRequest = (scale, rotation, columns, rightToLeft, gutter)
        canvasColumns = max(1, columns)
        lastCentredForWidth = viewport.width
        let size = canvas.layout(pages: volume?.pages ?? [],
                                 scale: scale, rotation: rotation, columns: columns,
                                 rightToLeft: rightToLeft, gutter: gutter,
                                 viewportWidth: viewport.width)
        if canvas.needsRedecode {
            cancelAllTasks()
        }
        if let doc = documentView, doc.frame.size != size {
            doc.frame = CGRect(origin: doc.frame.origin, size: size)
        }
        if !isZooming { updateWindow() }
        return size
    }

    private var lastLayoutRequest: (scale: CGFloat, rotation: Double, columns: Int,
                                    rightToLeft: Bool, gutter: CGFloat)?
    private var lastCentredForWidth: CGFloat = 0
    private var requestedPage: Int?
    private var requestPending = false
    private var anchoredFor: (scale: CGFloat, rotation: Double, columns: Int,
                              rightToLeft: Bool, gutter: CGFloat)?

    private var anchorPage: Int? {
        lastIndexReported >= 0 ? lastIndexReported : requestedPage
    }

    private func reanchorLeadingEdge() {
        guard let r = lastLayoutRequest, viewport.width > 1,
              let page = anchorPage, page >= 0 else { return }
        let inputs = (r.scale, r.rotation, r.columns, r.rightToLeft, r.gutter)
        if let previous = anchoredFor, previous == inputs { return }
        anchoredFor = inputs

        let x = canvas.scrollTargetX(for: page, viewportWidth: viewport.width,
                                     rightToLeft: r.rightToLeft)
        guard abs(contentView.bounds.origin.x - x) > 0.5 else { return }
        contentView.scroll(to: CGPoint(x: x, y: contentView.bounds.origin.y))
    }

    override func layout() {
        super.layout()
        onViewportChanged?(viewport)
        if abs(lastCentredForWidth - viewport.width) > 0.5, let r = lastLayoutRequest {
            lastCentredForWidth = viewport.width
            _ = setLayout(scale: r.scale, rotation: r.rotation, columns: r.columns,
                          rightToLeft: r.rightToLeft, gutter: r.gutter)
        }
        applyRequestedPage()
    }

    // MARK: - Scrolling

    @objc private func boundsChanged() {
        let visible = contentView.bounds
        if visible.origin != lastReportedOrigin {
            lastReportedOrigin = visible.origin
            noteScrollActivity()
        }
        updateWindow()

        if !isProgrammaticScroll { reportIndex(canvas.index(atCenterOf: visible)) }
    }

    private func reportIndex(_ index: Int) {
        guard index != lastIndexReported else { return }
        lastIndexReported = index
        onIndexChange?(index)
    }

    func scrollToPage(_ index: Int) {
        requestedPage = index
        requestPending = true
        applyRequestedPage()
    }

    private func applyRequestedPage() {
        guard requestPending, let index = requestedPage else { return }
        guard viewport.width > 1, viewport.height > 1 else { return }
        requestPending = false

        let y = canvas.scrollTargetY(for: index, viewportHeight: viewport.height)
        guard y.isFinite else { return }

        let x = canvas.scrollTargetX(for: index, viewportWidth: viewport.width,
                                     rightToLeft: lastLayoutRequest?.rightToLeft == true)
        if abs(contentView.bounds.origin.y - y) < 0.5,
           abs(contentView.bounds.origin.x - x) < 0.5 {
            reportIndex(index)
            return
        }

        programmaticScrollToken &+= 1
        isProgrammaticScroll = true

        updateWindow(target: index)

        reportIndex(index)

        contentView.scroll(to: CGPoint(x: x, y: max(0, y)))
        isProgrammaticScroll = false
        noteScrollActivity()
    }

    override func scrollWheel(with event: NSEvent) {
        if isProgrammaticScroll {
            programmaticScrollToken &+= 1
            isProgrammaticScroll = false
        }
        super.scrollWheel(with: event)
    }

    // MARK: - Pinch

    @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        let delta = gesture.magnification
        gesture.magnification = 0

        isZooming = gesture.state == .began || gesture.state == .changed
        canvas.isZooming = isZooming

        let factor = 1.0 + delta
        if factor > 0.2, factor < 5 {
            onScalePinned?(CGFloat(factor))
        }

        guard !isZooming, let r = lastLayoutRequest else { return }
        _ = setLayout(scale: r.scale, rotation: r.rotation, columns: r.columns,
                      rightToLeft: r.rightToLeft, gutter: r.gutter)
        updateWindow()
    }

    private func syncZoomState() {
        guard let gesture = magnifyGesture else { return }
        let active = gesture.state == .began || gesture.state == .changed
        guard active != isZooming else { return }
        isZooming = active
        canvas.isZooming = active
        guard !active, let r = lastLayoutRequest else { return }
        _ = setLayout(scale: r.scale, rotation: r.rotation, columns: r.columns,
                      rightToLeft: r.rightToLeft, gutter: r.gutter)
    }

    // MARK: - Image loading

    private var tasks: [Int: [Task<Void, Never>]] = [:]

    private var wantedTiles: Set<Int> = []

    private var liveTaskCount: Int { tasks.values.reduce(0) { $0 + $1.count } }

    private static let maxConcurrentPages = 8

    private func loadTiles(_ wanted: [Int], full: Set<Int>, pages: [ComicPage]) {
        wantedTiles = Set(wanted)
        settle()

        for tile in wanted {
            guard liveTaskCount < Self.maxConcurrentPages else { return }
            guard !canvas.resolvedTiles.contains(tile) else { continue }
            guard tasks[tile] == nil else { continue }

            let indices = ContinuousCanvas.tileRange(tile).filter { $0 < pages.count }
            tasks[tile] = indices.map { index -> Task<Void, Never> in
                let url = pages[index].url
                let visible = full.contains(index)
                let pixels = visible ? Self.targetPixels : Self.marginPixels
                return Task(priority: visible ? .userInitiated : .utility) { [weak self] in
                    let box = await ImagePipeline.shared.image(at: url, targetPixels: pixels)
                    guard !Task.isCancelled, let box else { return }
                    self?.finishPage(index, box.image)
                }
            }
        }
    }

    private func finishPage(_ index: Int, _ image: CGImage) {
        canvas.setImage(image, for: index)
        settle()
        if !isZooming { updateWindow() }
    }

    private func settle() {
        for (tile, group) in tasks {
            if !wantedTiles.contains(tile) {
                group.forEach { $0.cancel() }
                tasks[tile] = nil
            } else if canvas.isTileResolved(tile) {
                tasks[tile] = nil
            } else if group.allSatisfy({ $0.isCancelled }) {
                tasks[tile] = nil
            }
        }
    }

    private func updateWindow(target: Int? = nil) {
        syncZoomState()
        guard target != nil || !isMoving else { return }
        guard let pages = volume?.pages, !pages.isEmpty else { return }
        let onScreen: [Int]
        if let target {
            onScreen = canvas.pages(inRow: target / canvasColumns)
        } else {
            onScreen = Array(canvas.indices(intersecting: contentView.bounds))
        }
        guard !onScreen.isEmpty else { return }

        let low = max(0, onScreen[0] - Self.offscreenBufferPages)
        let high = min(pages.count - 1, onScreen[onScreen.count - 1] + Self.offscreenBufferPages)
        let first = ContinuousCanvas.tile(of: low)
        let last = ContinuousCanvas.tile(of: high)

        loadTiles(Array(first...last), full: Set(onScreen), pages: pages)

        var evict: Set<Int> = []
        for t in canvas.resolvedTiles where t < first - 1 || t > last + 1 {
            evict.insert(t)
        }
        canvas.evictTiles(evict)
    }

    private static let offscreenBufferPages = 1

    private static var marginPixels: Double { max(360, targetPixels / 4) }

    private func noteScrollActivity() {
        lastScrollAt = CACurrentMediaTime()
        guard !isScrolling else { return }
        isScrolling = true
        scrollSettle?.cancel()
        scrollSettle = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard !Task.isCancelled, let self else { return }
                guard CACurrentMediaTime() - self.lastScrollAt >= Self.scrollSettleDelay,
                      !self.isProgrammaticScroll
                else { continue }
                self.isScrolling = false
                self.updateWindow()
                self.onScrollRest?()
                return
            }
        }
    }

    static var targetPixels: Double {
        let backing = Double(NSScreen.main?.backingScaleFactor ?? 2)
        return 1200 * backing
    }
}

// MARK: - Representable

struct ContinuousScrollerView: NSViewRepresentable {

    @ObservedObject var model: ViewerModel
    let volume: ComicVolume

    func makeNSView(context: Context) -> ContinuousScrollView {
        let v = ContinuousScrollView(frame: .zero)
        v.setVolume(volume)
        v.onScalePinned = { factor in
            model.setZoom(to: model.effectiveScale * Double(factor))
        }
        v.onViewportChanged = { model.viewportSize = $0 }
        v.onNavigate = { direction in
            if direction > 0 { model.goForward() } else { model.goBack() }
        }
        v.onScrollRest = {
            model.reportScrollRest()
        }
        v.onIndexChange = { index in
            context.coordinator.lastReportedIndex = index
            model.setCurrentPageFromScroll(index)
        }
        return v
    }

    func updateNSView(_ v: ContinuousScrollView, context: Context) {
        if v.currentVolumeURL != volume.url { v.setVolume(volume) }
        v.setLayout(scale: CGFloat(model.effectiveScale), rotation: model.rotation,
                    columns: model.layout.columns,
                    rightToLeft: model.spreadOrder == .rightToLeft)

        let cameFromScroll = context.coordinator.lastReportedIndex == model.currentPage
        if !cameFromScroll, context.coordinator.lastRequestedIndex != model.currentPage {
            context.coordinator.lastRequestedIndex = model.currentPage
            v.scrollToPage(model.currentPage)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastReportedIndex: Int?
        var lastRequestedIndex: Int?
    }
}

