// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import SwiftUI
import AppKit

enum PageLayout: String, CaseIterable, Identifiable {
    case single
    case twoUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return "Single Page"
        case .twoUp: return "Two-Up"
        }
    }

    var symbol: String {
        switch self {
        case .single: return "rectangle.portrait"
        case .twoUp: return "rectangle.split.2x1"
        }
    }

    var columns: Int {
        switch self {
        case .single: return 1
        case .twoUp: return 2
        }
    }
}

extension NSNotification.Name {
    static let pfSpreadOrderDidChange = NSNotification.Name("pf.spreadOrder.didChange")
}

enum SpreadOrder: String, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftToRight: return "Left to Right"
        case .rightToLeft: return "Right to Left"
        }
    }
}

enum ViewerBackground: String, CaseIterable, Identifiable {
    case color
    case lightGray
    case darkGray
    case black
    case checkerboard
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: return "Color"
        case .lightGray: return "Light Gray"
        case .darkGray: return "Dark Gray"
        case .black: return "Black"
        case .checkerboard: return "Checkerboard"
        case .system: return "System"
        }
    }

    var symbol: String {
        switch self {
        case .color: return "circle.lefthalf.filled"
        case .lightGray: return "sun.max"
        case .darkGray: return "moon"
        case .black: return "circle.fill"
        case .checkerboard: return "square.grid.3x3"
        case .system: return "circle.dotted"
        }
    }

    func swiftUIColor(for scheme: ColorScheme) -> Color {
        switch self {
        case .color: return scheme == .dark ? Color(white: 0.16) : Color(white: 0.90)
        case .lightGray: return Color(white: 0.72)
        case .darkGray: return Color(white: 0.28)
        case .black: return Color.black
        case .checkerboard: return Color(white: scheme == .dark ? 0.14 : 0.88)
        case .system: return scheme == .dark ? Color(white: 0.10) : Color(white: 0.96)
        }
    }
}

