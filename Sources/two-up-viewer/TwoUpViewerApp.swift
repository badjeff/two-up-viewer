// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import SwiftUI
import AppKit

@main
struct TwoUpViewerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            VolumeWindow()
        }
        .defaultSize(width: 1220, height: 880)
        .commands { DocumentCommands() }

        Settings {
            SettingsScene()
        }
    }
}

struct VolumeWindow: View {
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        Group {
            if let url = router.current {
                VolumeContent(url: url).id(url)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .task { router.restoreLastVolume() }
    }
}

private struct VolumeContent: View {
    let url: URL

    @State private var volume: ComicVolume?

    var body: some View {
        Group {
            if let volume, !volume.isEmpty {
                DocumentView(volume: volume)
            } else {
                EmptyStateView(
                    systemImage: "folder.badge.questionmark",
                    title: "No pages in this folder",
                    message: """
                    \(url.lastPathComponent) does not contain any images this app \
                    can read.

                    Try a folder of JPG, PNG, WebP, HEIC or TIFF files — the kind a \
                    volume download unpacks into.
                    """
                )
            }
        }
        .task(id: url) {
            volume = await VolumeScanner.scan(url)
        }
    }
}

struct DocumentCommands: Commands {

    @FocusedValue(\.viewerModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder\u{2026}") { Task { @MainActor in AppRouter.chooseFolder() } }
                .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent") {
                let recents = AppSettings.shared.recentVolumes
                if recents.isEmpty {
                    Text("No Recent Volumes")
                } else {
                    ForEach(recents, id: \.self) { url in
                        Button(url.path) {
                            Task { @MainActor in AppRouter.shared.open(url) }
                        }
                    }
                }
                Divider()
                Button("Clear Recently Opened") {
                    Task { @MainActor in AppRouter.shared.clearRecents() }
                }
                .disabled(recents.isEmpty)
            }
        }

        CommandGroup(replacing: .sidebar) {
            Button(model?.sidebarVisible == true
                   ? "Hide Page Strip"
                   : "Show Page Strip") {
                model?.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: .control)
            .disabled(model == nil)

            Divider()

            Button("Actual Size") { model?.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(model == nil)

            Button("Zoom In") { model?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .keyboardShortcut("=", modifiers: .command)
                .disabled(model == nil)

            Button("Zoom Out") { model?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model == nil)

            Divider()

            Menu("Layout") {
                ForEach(PageLayout.allCases) { layout in
                    Button(layout.title) { model?.layout = layout }
                        .disabled(model == nil)
                }
            }

            Menu("Background") {
                ForEach(ViewerBackground.allCases) { bg in
                    Button(bg.title) { model?.background = bg }
                        .disabled(model == nil)
                }
            }
        }

        CommandGroup(replacing: .toolbar) { }

        CommandMenu("Go") {
            Button("Next Page") { model?.goForward() }
                .keyboardShortcut(.pageDown, modifiers: [])
                .disabled(model?.canGoForward != true)

            Button("Previous Page") { model?.goBack() }
                .keyboardShortcut(.pageUp, modifiers: [])
                .disabled(model?.canGoBack != true)

            Divider()

            Button("First Page") { model?.goToStart() }
                .keyboardShortcut(.home, modifiers: [])
                .disabled(model == nil)

            Button("Last Page") { model?.goToEnd() }
                .keyboardShortcut(.end, modifiers: [])
                .disabled(model == nil)

            Divider()

            Button("Next Volume") { cycleVolume(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(model == nil)

            Button("Previous Volume") { cycleVolume(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(model == nil)

            Divider()

            Button("Go to Page\u{2026}") { presentGoToPage() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(model == nil)
        }
    }

    private func cycleVolume(_ direction: Int) {
        guard let model else { return }
        Task { @MainActor in
            let siblings = await VolumeScanner.siblingVolumes(of: model.volume.url)
            guard let current = siblings.firstIndex(of: model.volume.url) else { return }
            let next = siblings[(current + direction + siblings.count) % siblings.count]
            guard next != model.volume.url else { return }
            AppRouter.shared.open(next)
        }
    }

    private func presentGoToPage() {
        guard let model, let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        Task { @MainActor in GoToPageSheet.shared.present(model: model, in: window) }
    }
}

struct ViewerModelKey: FocusedValueKey {
    typealias Value = ViewerModel
}

extension FocusedValues {
    var viewerModel: ViewerModel? {
        get { self[ViewerModelKey.self] }
        set { self[ViewerModelKey.self] = newValue }
    }
}

struct GoToPagePanel: View {
    @ObservedObject var model: ViewerModel

    private let onFinish: () -> Void

    @State private var page = 1

    init(model: ViewerModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to Page").font(.headline)

            HStack {
                TextField("", value: $page, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text("of \(model.pageCount)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel") { onFinish() }
                    .keyboardShortcut(.cancelAction)
                Button("Go") {
                    model.go(to: min(max(page - 1, 0), max(0, model.pageCount - 1)))
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(page < 1 || page > model.pageCount)
            }
        }
        .padding(18)
        .frame(width: 300)
        .onAppear { page = model.currentPage + 1 }
        .onExitCommand { onFinish() }
    }
}

@MainActor
final class GoToPageSheet {
    static let shared = GoToPageSheet()

    private var window: NSWindow?

    private var parent: NSWindow?

    func present(model: ViewerModel, in parent: NSWindow) {
        guard window == nil else { return }

        let panel = GoToPagePanel(model: model, onFinish: { [weak self] in
            self?.dismiss()
        })
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: panel))
        window = sheet
        self.parent = parent
        parent.beginSheet(sheet, completionHandler: nil)
    }

    private func dismiss() {
        guard let sheet = window, let parent else { return }
        window = nil
        self.parent = nil
        parent.endSheet(sheet)
    }
}

struct SettingsScene: View {

    var body: some View {
        Form {
            Section {
                Toggle("Reopen the last volume on launch", isOn: Binding(
                    get: { AppSettings.shared.reopenLastVolume },
                    set: { AppSettings.shared.reopenLastVolume = $0 }
                ))
                Text("""
                The last volume you opened is reopened when the app starts. \
                Turn this off to always land on the welcome screen.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 220)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

