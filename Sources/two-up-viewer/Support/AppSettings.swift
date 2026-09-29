// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import Foundation
import AppKit

final class AppSettings {

    static let shared = AppSettings()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        register()
    }

    private enum Key {
        static let zoomMode = "pf.zoomMode"
        static let zoomScale = "pf.zoomScale"
        static let continuousScrolling = "pf.continuousScrolling"
        static let rotation = "pf.rotation"
        static let layout = "pf.layout"
        static let spreadOrder = "pf.spreadOrder"
        static let sidebarWidth = "pf.sidebarWidth"
        static let sidebarVisible = "pf.sidebarVisible"
        static let background = "pf.background"
        static let reopenLastVolume = "pf.reopenLastVolume"
        static let recentVolumes = "pf.recentVolumes"
    }

    private func register() {
        defaults.register(defaults: [
            Key.zoomMode: "fitWidth",
            Key.zoomScale: 1.0,
            Key.continuousScrolling: true,
            Key.rotation: 0.0,
            Key.layout: PageLayout.twoUp.rawValue,
            Key.spreadOrder: SpreadOrder.rightToLeft.rawValue,
            Key.sidebarWidth: 168.0,
            Key.sidebarVisible: true,
            Key.background: ViewerBackground.color.rawValue,
            Key.reopenLastVolume: true,
        ])
    }

    var zoomMode: ZoomMode {
        get {
            switch defaults.string(forKey: Key.zoomMode) ?? "fitWidth" {
            case "fitPage": return .fitPage
            case "actualSize": return .actualSize
            case "custom": return .custom(zoomScale)
            default: return .fitWidth
            }
        }
        set {
            defaults.set(newValue.storedName, forKey: Key.zoomMode)
            if case .custom(let s) = newValue { defaults.set(s, forKey: Key.zoomScale) }
        }
    }

    var zoomScale: Double {
        get {
            let s = defaults.double(forKey: Key.zoomScale)
            return s > 0 ? s : 1.0
        }
        set { defaults.set(ZoomLimits.clamp(newValue), forKey: Key.zoomScale) }
    }

    var rotation: Double {
        get { defaults.double(forKey: Key.rotation) }
        set { defaults.set(newValue, forKey: Key.rotation) }
    }

    var continuousScrolling: Bool {
        get { defaults.bool(forKey: Key.continuousScrolling) }
        set { defaults.set(newValue, forKey: Key.continuousScrolling) }
    }

    var layout: PageLayout {
        get { PageLayout(rawValue: defaults.string(forKey: Key.layout) ?? "") ?? .twoUp }
        set { defaults.set(newValue.rawValue, forKey: Key.layout) }
    }

    var spreadOrder: SpreadOrder {
        get { SpreadOrder(rawValue: defaults.string(forKey: Key.spreadOrder) ?? "") ?? .rightToLeft }
        set {
            defaults.set(newValue.rawValue, forKey: Key.spreadOrder)
            NotificationCenter.default.post(name: .pfSpreadOrderDidChange, object: newValue)
        }
    }

    var background: ViewerBackground {
        get { ViewerBackground(rawValue: defaults.string(forKey: Key.background) ?? "") ?? .color }
        set { defaults.set(newValue.rawValue, forKey: Key.background) }
    }

    static let sidebarWidthRange: ClosedRange<Double> = 120...520

    var sidebarWidth: Double {
        get {
            let w = defaults.double(forKey: Key.sidebarWidth)
            return w > 0 ? w : 168
        }
        set {
            defaults.set(min(max(newValue, Self.sidebarWidthRange.lowerBound),
                                Self.sidebarWidthRange.upperBound),
                         forKey: Key.sidebarWidth)
        }
    }

    var sidebarVisible: Bool {
        get { defaults.bool(forKey: Key.sidebarVisible) }
        set { defaults.set(newValue, forKey: Key.sidebarVisible) }
    }

    var reopenLastVolume: Bool {
        get { defaults.bool(forKey: Key.reopenLastVolume) }
        set { defaults.set(newValue, forKey: Key.reopenLastVolume) }
    }

    var recentVolumes: [URL] {
        defaults.stringArray(forKey: Key.recentVolumes)?.map(URL.init(fileURLWithPath:)) ?? []
    }

    var lastVolumeURL: URL? { recentVolumes.first }

    func recordRecent(_ url: URL) {
        var kept = recentVolumes.filter { $0 != url && FileManager.default.fileExists(atPath: $0.path) }
        kept.insert(url, at: 0)
        writeRecents(Array(kept.prefix(Self.recentVolumesLimit)))
    }

    func clearRecentVolumes() {
        writeRecents([])
    }

    private func writeRecents(_ urls: [URL]) {
        defaults.set(urls.map(\.path), forKey: Key.recentVolumes)
    }

    private static let recentVolumesLimit = 10

}

private extension ZoomMode {
    var storedName: String {
        switch self {
        case .fitPage: return "fitPage"
        case .fitWidth: return "fitWidth"
        case .actualSize: return "actualSize"
        case .custom: return "custom"
        }
    }
}

