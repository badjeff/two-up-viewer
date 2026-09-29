// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

final class SidebarDividerView: NSView {

    static let grabWidth: CGFloat = 9

    var onWidthChange: ((Double) -> Void)?

    var width: CGFloat = 0

    private var dragStartX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0

    override func mouseDown(with event: NSEvent) {
        dragStartX = event.locationInWindow.x
        dragStartWidth = width
    }

    override func mouseDragged(with event: NSEvent) {
        guard let onWidthChange else { return }
        let range = AppSettings.sidebarWidthRange
        let target = dragStartWidth + event.locationInWindow.x - dragStartX
        onWidthChange(Double(min(max(target, range.lowerBound), range.upperBound)))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.midX - 0.5, y: bounds.minY, width: 1, height: bounds.height).fill()
    }
}

struct SidebarDivider: NSViewRepresentable {

    let width: Double
    let onWidthChange: (Double) -> Void

    func makeNSView(context: Context) -> SidebarDividerView {
        let view = SidebarDividerView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: SidebarDividerView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: SidebarDividerView) {
        view.width = CGFloat(width)
        view.onWidthChange = onWidthChange
    }
}
