// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import Combine
import AppKit
import CoreGraphics

final class ViewerModel: ObservableObject {

    let volume: ComicVolume

    @Published private(set) var currentPage: Int = 0

    @Published var zoomMode: ZoomMode {
        didSet {
            guard zoomMode != oldValue else { return }
            settings.zoomMode = zoomMode
            if case .custom(let s) = zoomMode { settings.zoomScale = s }
            applyZoomMode(force: true)
        }
    }

    @Published var continuousScrolling: Bool {
        didSet { settings.continuousScrolling = continuousScrolling }
    }

    @Published private(set) var effectiveScale: Double = 1.0

    @Published var rotation: Double {
        didSet { settings.rotation = rotation }
    }

    @Published var layout: PageLayout {
        didSet {
            guard layout != oldValue else { return }
            settings.layout = layout
            applyZoomMode(force: true)
            snapToPage()
        }
    }

    @Published var spreadOrder: SpreadOrder {
        didSet {
            guard spreadOrder != oldValue else { return }
            settings.spreadOrder = spreadOrder
        }
    }

    @Published var background: ViewerBackground {
        didSet { settings.background = background }
    }

    @Published var sidebarWidth: Double {
        didSet { settings.sidebarWidth = sidebarWidth }
    }

    @Published var sidebarVisible: Bool {
        didSet {
            guard sidebarVisible != oldValue else { return }
            settings.sidebarVisible = sidebarVisible
        }
    }

    @Published var viewportSize: CGSize = .zero {
        didSet {
            guard viewportSize != oldValue, viewportSize != .zero else { return }
            guard needsInitialFit else { return }
            needsInitialFit = false
            applyZoomMode(force: true)
        }
    }

    private var needsInitialFit = true

    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    init(volume: ComicVolume, settings: AppSettings = .shared) {
        self.volume = volume
        self.settings = settings

        self.zoomMode = settings.zoomMode
        self.continuousScrolling = settings.continuousScrolling
        self.rotation = settings.rotation
        self.layout = settings.layout
        self.spreadOrder = settings.spreadOrder
        self.background = settings.background
        self.sidebarWidth = settings.sidebarWidth
        self.sidebarVisible = settings.sidebarVisible

        self.effectiveScale = zoomMode == .custom(settings.zoomScale)
            ? settings.zoomScale
            : 1.0

        NotificationCenter.default.publisher(for: .pfSpreadOrderDidChange)
            .compactMap { $0.object as? SpreadOrder }
            .receive(on: RunLoop.main)
            .sink { [weak self] order in self?.spreadOrder = order }
            .store(in: &cancellables)
    }

    var pageCount: Int { volume.count }

    var visibleIndices: [Int] { indices(ofSpreadStartingAt: currentPage) }

    func indices(ofSpreadStartingAt index: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        let page = min(max(index, 0), pageCount - 1)
        switch layout {
        case .single:
            return [page]
        case .twoUp:
            let base = spreadAnchor(for: page)
            return [base, base + 1].filter { $0 >= 0 && $0 < pageCount }
        }
    }

    func spreadAnchor(for index: Int) -> Int {
        guard layout == .twoUp else { return index }
        let page = min(max(index, 0), max(0, pageCount - 1))
        return page - (page % 2)
    }

    var visiblePages: [ComicPage] { visibleIndices.map { volume.pages[$0] } }

    var referencePageSize: CGSize {
        let sizes = visiblePages.map { $0.rotatedPointSize(rotation: rotation) }
        guard let first = sizes.first else { return CGSize(width: 1, height: 1) }
        return sizes.reduce(first) { CGSize(width: max($0.width, $1.width),
                                            height: max($0.height, $1.height)) }
    }

    var fittingViewport: CGSize {
        let gutter: CGFloat = layout == .twoUp ? Self.spreadGutter : 0
        return CGSize(width: max(1, viewportSize.width - gutter - Self.canvasInset * 2),
                      height: max(1, viewportSize.height - Self.canvasInset * 2))
    }

    static let spreadGutter: CGFloat = 12
    static let canvasInset: CGFloat = 9

    var pageBadge: String {
        let idx = visibleIndices
        guard let lo = idx.first, let hi = idx.last else { return "—" }
        return lo == hi ? "\(lo + 1)" : "\(lo + 1)–\(hi + 1)"
    }

    var pageCounterText: String { "\(pageBadge) of \(pageCount)" }

    var zoomLabel: String { "\(Int((effectiveScale * 100).rounded()))%" }

    private func applyZoomMode(force: Bool) {
        guard force || !effectiveScale.isFinite else { return }

        switch zoomMode {
        case .fitPage, .fitWidth:
            if force || viewportSize != .zero {
                effectiveScale = ZoomLimits.clamp(
                    zoomMode.scale(forPageSize: referencePageSize,
                                   inViewport: fittingViewport,
                                   slots: layout.columns)
                )
            }
        case .actualSize:
            effectiveScale = 1.0
        case .custom(let s):
            effectiveScale = ZoomLimits.clamp(s)
        }
        clampScaleToLimits()
    }

    private func clampScaleToLimits() {
        effectiveScale = ZoomLimits.clamp(effectiveScale)
    }

    var decodeTargetPixels: Double {
        let page = referencePageSize
        let longest = max(page.width, page.height) * effectiveScale
        return longest * 2.0
    }

    func setZoom(to scale: Double) {
        let s = ZoomLimits.clamp(scale)
        effectiveScale = s
        zoomMode = .custom(s)
    }

    func stepZoom(_ direction: Double) {
        setZoom(to: effectiveScale + direction * ZoomLimits.stepPercent / 100)
    }

    func zoomIn() { stepZoom(1) }
    func zoomOut() { stepZoom(-1) }

    func actualSize() { setZoom(to: 1.0) }

    func fitPage() { zoomMode = .fitPage }
    func fitWidth() { zoomMode = .fitWidth }

    var pageStep: Int { layout == .twoUp ? 2 : 1 }

    var canGoForward: Bool {
        layout == .twoUp
            ? currentPage + 2 < pageCount
            : currentPage + 1 < pageCount
    }

    var canGoBack: Bool { currentPage > 0 }

    func goForward() {
        guard canGoForward else { return }
        setPage(currentPage + pageStep)
    }

    func goBack() {
        guard canGoBack else { return }
        setPage(max(0, currentPage - pageStep))
    }

    func go(to index: Int) {
        setPage(index)
    }

    func scrub(to index: Int) {
        setPage(index)
    }

    func goToStart() { go(to: 0) }
    func goToEnd() { go(to: max(0, pageCount - pageStep)) }

    @Published private(set) var currentPageCameFromScroll = false

    @Published private(set) var scrollRestToken = 0

    func reportScrollRest() {
        scrollRestToken &+= 1
    }

    func setCurrentPageFromScroll(_ index: Int) {
        let clamped = min(max(index, 0), max(0, pageCount - 1))
        guard clamped != currentPage else { return }
        currentPage = clamped
        currentPageCameFromScroll = true
        warmNeighbours()
    }

    private func setPage(_ index: Int) {
        let clamped = min(max(index, 0), max(0, pageCount - 1))
        guard clamped != currentPage else { return }
        currentPage = clamped
        currentPageCameFromScroll = false
        warmNeighbours()
    }

    private func snapToPage() {
        if layout == .twoUp {
            let snapped = currentPage - (currentPage % 2)
            if snapped != currentPage { setPage(snapped) }
        }
        warmNeighbours()
    }

    func warmNeighbours() {
        prefetchTask?.cancel()
        let volume = self.volume
        let page = currentPage
        let slots = layout.columns
        prefetchTask = Task {
            await ImagePipeline.shared.prefetch(volume: volume, around: page, slots: slots)
        }
    }

    private var prefetchTask: Task<Void, Never>?

    func primeVisiblePages() async {
        let pages = visiblePages
        guard !pages.isEmpty else { return }
        let target = decodeTargetPixels

        await withTaskGroup(of: Void.self) { group in
            for page in pages {
                group.addTask {
                    guard !Task.isCancelled else { return }
                    _ = await ImagePipeline.shared.image(at: page.url, targetPixels: target)
                }
            }
        }
    }
}

extension ComicPage {
    func rotatedPointSize(rotation: Double) -> CGSize {
        let wrapped = rotation.truncatingRemainder(dividingBy: 360)
        let normalised = wrapped < 0 ? wrapped + 360 : wrapped
        let quarter = Int((normalised / 90).rounded()) % 4
        let swapped = (quarter % 2 != 0)
        return swapped
            ? CGSize(width: pointSize.height, height: pointSize.width)
            : pointSize
    }
}


