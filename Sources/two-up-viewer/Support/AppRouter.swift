// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import SwiftUI
import AppKit

@MainActor
final class AppRouter: ObservableObject {

    static let shared = AppRouter()

    @Published private(set) var current: URL?

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard VolumeScanner.containsPages(url) else { return false }
        current = url
        AppSettings.shared.recordRecent(url)
        return true
    }

    func restoreLastVolume() {
        guard AppSettings.shared.reopenLastVolume else { return }
        guard let url = AppSettings.shared.lastVolumeURL else { return }
        open(url)
    }

    func close() {
        current = nil
    }

    func clearRecents() {
        close()
        AppSettings.shared.clearRecentVolumes()
    }

    @MainActor
    static func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.prompt = "Open"
        panel.message = "Choose a volume folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        shared.open(url)
    }
}

