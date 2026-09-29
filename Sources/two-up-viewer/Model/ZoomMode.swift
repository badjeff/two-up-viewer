// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import AppKit
import CoreGraphics

enum ZoomMode: Equatable {
    case fitPage
    case fitWidth
    case actualSize
    case custom(Double)

    func scale(forPageSize pageSize: CGSize, inViewport viewport: CGSize, slots: Int) -> Double {
        let slots = CGFloat(max(1, slots))
        guard pageSize.width > 0, pageSize.height > 0,
              viewport.width > 0, viewport.height > 0 else { return 1 }

        switch self {
        case .fitPage:
            let s = min(viewport.width / (pageSize.width * slots),
                        viewport.height / pageSize.height)
            return Double(max(0.01, s))

        case .fitWidth:
            let s = viewport.width / (pageSize.width * slots)
            return Double(max(0.01, s))

        case .actualSize:
            return 1.0

        case .custom(let s):
            return s
        }
    }
}

enum ZoomLimits {
    static let min: Double = 0.02
    static let max: Double = 16.0
    static let stepPercent: Double = 2
    static let sliderStepPercent: Double = 1

    static func clamp(_ scale: Double) -> Double {
        Swift.min(Swift.max(scale, min), max)
    }
}

