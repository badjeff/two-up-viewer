// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import SwiftUI
import AppKit

struct ArrowPageKeys: NSViewRepresentable {

    let model: ViewerModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(for: model)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.install(for: model)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        private var monitor: Any?
        private weak var installed: ViewerModel?

        deinit { removeMonitor() }

        func install(for model: ViewerModel) {
            guard monitor == nil || installed !== model else { return }
            removeMonitor()
            installed = model
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                ArrowPageKeys.route(keyCode: event.keyCode,
                                    modifiers: event.modifierFlags,
                                    model: model) ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    private static let down: UInt16 = 0x7D
    private static let up: UInt16 = 0x7E
    private static let right: UInt16 = 0x7C
    private static let left: UInt16 = 0x7B

    private static let owned: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    static func route(keyCode: UInt16,
                      modifiers: NSEvent.ModifierFlags,
                      model: ViewerModel) -> Bool {
        guard modifiers.intersection(owned).isEmpty else { return false }
        guard !isTextInputFocused else { return false }

        let forward: Bool
        switch keyCode {
        case down, right:
            guard model.canGoForward else { return false }
            forward = true
        case up, left:
            guard model.canGoBack else { return false }
            forward = false
        default:
            return false
        }

        if forward { model.goForward() } else { model.goBack() }
        return true
    }

    private static var isTextInputFocused: Bool {
        guard let app = NSApp else { return false }
        switch app.keyWindow?.firstResponder {
        case is NSTextView, is NSTextField, is NSSearchField:
            return true
        default:
            return false
        }
    }
}

