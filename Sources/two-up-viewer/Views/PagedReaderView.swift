// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

// MARK: - Paged canvas

final class PagedCanvas: NSView {

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
    private var images: [Int: CGImage] = [:]
    private var pageSize: CGSize = .zero
    private var scale: CGFloat = 1
    private var rotation: Double = 0
    private var gutter: CGFloat = 0

    var onAdvance: (() -> Void)?
    var onRetreat: (() -> Void)?

    func configure(pages: [ComicPage], images: [Int: CGImage], pageSize: CGSize,
                   scale: CGFloat, rotation: Double, gutter: CGFloat) {
        if pages == self.pages, sameImages(images), pageSize == self.pageSize,
           scale == self.scale, rotation == self.rotation, gutter == self.gutter {
            return
        }
        self.pages = pages
        self.images = images
        self.pageSize = pageSize
        self.scale = scale
        self.rotation = rotation
        self.gutter = gutter
        needsDisplay = true
    }

    private func sameImages(_ other: [Int: CGImage]) -> Bool {
        images.count == other.count && other.allSatisfy { images[$0.key] === $0.value }
    }

    func setImages(_ images: [Int: CGImage]) {
        self.images = images
        needsDisplay = true
    }

    func contentSize() -> CGSize {
        guard !pages.isEmpty, pageSize.width > 0, pageSize.height > 0 else { return .zero }
        let step = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        return CGSize(width: step.width * CGFloat(pages.count) + gutter * CGFloat(pages.count - 1),
                      height: step.height)
    }

    private func pageRects() -> [CGRect] {
        let total = contentSize()
        guard !pages.isEmpty, total.width > 0, total.height > 0 else { return [] }
        let step = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let origin = CGPoint(x: max(ViewerModel.canvasInset, (bounds.width - total.width) / 2),
                             y: max(ViewerModel.canvasInset, (bounds.height - total.height) / 2))
        return pages.indices.map { i in
            CGRect(x: origin.x + CGFloat(i) * (step.width + gutter),
                   y: origin.y, width: step.width, height: step.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rects = pageRects()

        for (i, page) in pages.enumerated() where i < rects.count {
            let rect = rects[i]
            ctx.saveGState()
            ctx.setStrokeColor(NSColor(white: 0.5, alpha: 0.3).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
            ctx.restoreGState()

            if let image = images[page.id] {
                PageDrawing.draw(image, in: rect, rotation: rotation, ctx: ctx)
            } else {
                PageDrawing.drawPlaceholder(number: page.number, in: rect, ctx: ctx)
            }
        }
    }

    // MARK: - Navigation by click

    override func mouseDown(with event: NSEvent) {
        onAdvance?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRetreat?()
    }
}

// MARK: - Paged reader

final class PagedScrollView: NSScrollView {

    private let canvas = PagedCanvas()
    private var laidOut: [Int] = []
    private var reportedViewport: CGSize = .zero

    var rightToLeft = true

    var onScalePinned: ((CGFloat) -> Void)?
    var onViewportChanged: ((CGSize) -> Void)?
    var onNavigate: ((Int) -> Void)?

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
            self, selector: #selector(viewportChanged),
            name: NSView.boundsDidChangeNotification, object: contentView
        )
        addGestureRecognizer(
            NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Layout

    func apply(pages: [ComicPage], images: [Int: CGImage], pageSize: CGSize,
               scale: CGFloat, rotation: Double, gutter: CGFloat) {
        let ids = pages.map(\.id)
        let turned = ids != laidOut
        laidOut = ids

        canvas.configure(pages: pages, images: images, pageSize: pageSize,
                         scale: scale, rotation: rotation, gutter: gutter)
        resizeCanvas()

        if turned { scrollToTop() }
    }

    private func scrollToTop() {
        contentView.scroll(to: CGPoint(x: leadingEdgeX, y: 0))
        reflectScrolledClipView(contentView)
    }

    private var leadingEdgeX: CGFloat {
        guard rightToLeft else { return 0 }
        return max(0, canvas.frame.width - contentView.bounds.width)
    }

    func updateImages(_ images: [Int: CGImage]) {
        canvas.setImages(images)
    }

    override func layout() {
        super.layout()
        resizeCanvas()
    }

    private func resizeCanvas() {
        let viewport = contentView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else { return }

        let content = canvas.contentSize()
        let target = CGSize(width: max(content.width, viewport.width),
                            height: max(content.height, viewport.height))
        let current = canvas.frame.size
        guard target != current else { return }

        let wasPannable = current.width > viewport.width + 0.5 || current.height > viewport.height + 0.5
        let focus = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)

        canvas.frame = CGRect(origin: .zero, size: target)
        canvas.needsDisplay = true

        let nowPannable = target.width > viewport.width + 0.5
            || target.height > viewport.height + 0.5
        if nowPannable, wasPannable {
            contentView.scroll(to: CGPoint(x: focus.x - viewport.width / 2,
                                           y: focus.y - viewport.height / 2))
        } else {
            contentView.scroll(to: CGPoint(x: leadingEdgeX, y: 0))
        }
        reflectScrolledClipView(contentView)
    }

    @objc private func viewportChanged() {
        let size = contentView.bounds.size
        guard size != .zero, size != reportedViewport else { return }
        reportedViewport = size
        resizeCanvas()
        onViewportChanged?(size)
    }

    // MARK: - Pinch

    @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        let factor = 1.0 + gesture.magnification
        gesture.magnification = 0
        guard factor > 0.2, factor < 5 else { return }
        onScalePinned?(CGFloat(factor))
    }
}

// MARK: - SwiftUI bridge

struct PagedReaderView: NSViewRepresentable {

    @ObservedObject var model: ViewerModel
    let volume: ComicVolume

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PagedScrollView {
        let v = PagedScrollView(frame: .zero)
        v.onScalePinned = { factor in
            model.setZoom(to: model.effectiveScale * Double(factor))
        }
        v.onViewportChanged = { model.viewportSize = $0 }
        v.onNavigate = { direction in
            if direction > 0 { model.goForward() } else { model.goBack() }
        }
        return v
    }

    func updateNSView(_ v: PagedScrollView, context: Context) {
        let spread = model.visibleIndices
        let gutter: CGFloat = model.layout == .twoUp ? ViewerModel.spreadGutter : 0

        let drawn = model.spreadOrder == .rightToLeft ? spread.reversed() : spread

        v.rightToLeft = model.spreadOrder == .rightToLeft

        v.apply(pages: drawn.map { volume.pages[$0] },
                images: context.coordinator.images,
                pageSize: model.referencePageSize,
                scale: CGFloat(model.effectiveScale),
                rotation: model.rotation,
                gutter: gutter)

        context.coordinator.loadMissing(spread, into: v, volume: volume,
                                        targetPixels: model.decodeTargetPixels)
    }

    @MainActor
    final class Coordinator {
        fileprivate var images: [Int: CGImage] = [:]
        private var requested: Set<Int> = []
        private var inFlight: Set<Int> = []
        private var stale: Set<Int> = []
        private var heldBucket = 0
        private var load: Task<Void, Never>?

        func loadMissing(_ indices: [Int], into view: PagedScrollView,
                         volume: ComicVolume, targetPixels: Double) {
            let wanted = Set(indices)
            let bucket = ImagePipeline.bucket(for: targetPixels)
            if requested != wanted {
                requested = wanted
                load?.cancel()
                load = nil
                inFlight = []
                stale = []
                images = images.filter { wanted.contains($0.key) }
            } else if bucket != heldBucket {
                stale = wanted
            }
            heldBucket = bucket

            let missing = indices.filter {
                !inFlight.contains($0) && (images[$0] == nil || stale.contains($0))
            }
            guard !missing.isEmpty else { return }
            inFlight.formUnion(missing)
            stale.subtract(missing)

            load = Task { [weak self] in
                var loaded: [Int: CGImage] = [:]
                for index in missing {
                    if Task.isCancelled { return }
                    let box = await ImagePipeline.shared.image(
                        at: volume.pages[index].url, targetPixels: targetPixels)
                    if let image = box?.image { loaded[index] = image }
                }
                guard let self, !Task.isCancelled else { return }
                self.inFlight.subtract(missing)
                self.load = nil
                self.images.merge(loaded) { _, new in new }
                view.updateImages(self.images)
            }
        }
    }
}

