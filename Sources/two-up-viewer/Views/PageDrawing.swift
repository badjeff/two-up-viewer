// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import AppKit

enum PageDrawing {

    static func isQuarterTurn(_ rotation: Double) -> Bool {
        abs(rotation).truncatingRemainder(dividingBy: 180) > 45
    }

    static func draw(_ image: CGImage, in rect: CGRect, rotation: Double,
                     ctx: CGContext) {
        ctx.interpolationQuality = .high

        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: 1, y: -1)
        if rotation != 0 {
            ctx.rotate(by: -rotation * .pi / 180)
        }

        let size = isQuarterTurn(rotation)
            ? CGSize(width: rect.height, height: rect.width)
            : rect.size
        ctx.draw(image, in: CGRect(x: -size.width / 2, y: -size.height / 2,
                                  width: size.width, height: size.height))
    }

    static func drawPlaceholder(number: Int, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.setStrokeColor(NSColor(white: 0.5, alpha: 0.45).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: -0.5, dy: -0.5))

        let shortest = min(rect.width, rect.height)
        guard shortest >= 34 else { return }

        let font = NSFont.systemFont(ofSize: shortest * 0.34, weight: .semibold)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: "\(number)", attributes: [
                .font: font,
                .foregroundColor: NSColor(white: 0.45, alpha: 0.5),
            ]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard bounds.width > 0, bounds.height > 0 else { return }

        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, ctx)
    }
}

