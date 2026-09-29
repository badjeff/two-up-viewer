#!/usr/bin/env swift

// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import AppKit
import Foundation

let sizes: [(px: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2),
    (512, 1), (512, 2),
]

let canvasSize = 1024.0

func colour(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let backgroundTop = colour(94, 92, 220)
let backgroundBottom = colour(38, 37, 110)
let pageFill = colour(252, 252, 255)

func drawIcon(into ctx: CGContext, unitSize: CGFloat) {
    let u = unitSize / 1024.0

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * u, y: y * u, width: w * u, height: h * u)
    }

    let body = rect(64, 64, 896, 896)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 200 * u, cornerHeight: 200 * u,
                       transform: nil))
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [backgroundTop.cgColor, backgroundBottom.cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: body.maxY),
                           end: CGPoint(x: 0, y: body.minY),
                           options: [])
    ctx.restoreGState()

    let pages: [(CGRect, CGFloat)] = [
        (rect(170, 268, 310, 506), 0.82),
        (rect(544, 220, 310, 554), 1.0),
    ]
    for (page, alpha) in pages {
        let path = CGPath(roundedRect: page, cornerWidth: 34 * u, cornerHeight: 34 * u,
                          transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * u),
                      blur: 26 * u,
                      color: colour(0, 0, 0, 0.3).cgColor)
        ctx.setFillColor(pageFill.withAlphaComponent(alpha).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }
}

// MARK: - Render

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

let iconSetRoot = outputDirectory.appendingPathComponent("two-up-viewer.iconset")
try? FileManager.default.removeItem(at: iconSetRoot)
try FileManager.default.createDirectory(at: iconSetRoot, withIntermediateDirectories: true)

for (px, scale) in sizes {
    let side = CGFloat(px * scale)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: side / canvasSize, y: side / canvasSize)
        drawIcon(into: ctx, unitSize: canvasSize)
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
    let name = scale == 1 ? "icon_\(px)x\(px).png" : "icon_\(px)x\(px)@2x.png"
    try data.write(to: iconSetRoot.appendingPathComponent(name))
}

print(iconSetRoot.path)
