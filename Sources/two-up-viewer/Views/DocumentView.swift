// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Checkerboard: View {
    var cell: CGFloat = 10

    var body: some View {
        Canvas { ctx, size in
            let light = Color(nsColor: .textBackgroundColor).opacity(0.06)
            let dark = Color(nsColor: .textColor).opacity(0.06)
            let rows = Int(ceil(size.height / cell))
            let cols = Int(ceil(size.width / (cell * 2)))

            var path = Path()
            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * cell * 2 + (row % 2 == 0 ? 0 : cell)
                    path.addRect(CGRect(x: x, y: CGFloat(row) * cell,
                                        width: cell, height: cell))
                }
            }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            ctx.fill(path, with: .color(dark), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }
}

struct DocumentView: View {

    @StateObject private var model: ViewerModel
    @State private var isLoading = false

    @Environment(\.colorScheme) private var colorScheme

    init(volume: ComicVolume, settings: AppSettings = .shared) {
        _model = StateObject(wrappedValue: ViewerModel(volume: volume, settings: settings))
    }

    var body: some View {
        content
    }

    private var content: some View {
        HStack(spacing: 0) {
            if model.sidebarVisible {
                ThumbnailSidebar(model: model)
                    .frame(width: model.sidebarWidth)
                SidebarDivider(width: model.sidebarWidth) { model.sidebarWidth = $0 }
                    .frame(width: SidebarDividerView.grabWidth)
            }
            canvasArea
        }
        .background(backgroundColor)
        .background(ArrowPageKeys(model: model))
        .toolbar { ViewerToolbar(model: model) }
        .toolbarBackground(.regularMaterial, for: .windowToolbar)
        .navigationTitle(model.volume.title)
        .navigationSubtitle(model.pageCounterText)
        .focusedSceneValue(\.viewerModel, model)
        .frame(minWidth: 720, minHeight: 520)
        .task(id: LoadKey(layout: model.layout, rotation: model.rotation)) {
            await primeCurrentSpread()
        }
    }

    @ViewBuilder
    private var canvasArea: some View {
        ZStack {
            if model.background == .checkerboard {
                Checkerboard()
            }

            Group {
                if model.volume.isEmpty {
                    EmptyStateView(
                        systemImage: "doc.questionmark",
                        title: "No pages found",
                        message: "\(model.volume.url.lastPathComponent) contains no readable images."
                    )
                } else if model.continuousScrolling {
                    ContinuousScrollerView(model: model, volume: model.volume)
                } else {
                    PagedReaderView(model: model, volume: model.volume)
                }
            }

            if isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var backgroundColor: Color {
        model.background.swiftUIColor(for: colorScheme)
    }

    private struct LoadKey: Hashable {
        let layout: PageLayout
        let rotation: Double
    }

    private func primeCurrentSpread() async {
        isLoading = true
        await model.primeVisiblePages()

        guard !Task.isCancelled else { return }

        isLoading = false

        model.warmNeighbours()
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WelcomeView: View {
    @State private var isDropTarget = false
    @State private var rejection: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            dropZone
            Spacer(minLength: 0)
        }
        .frame(minWidth: 760, minHeight: 480)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { loadFirstFolder(from: $0) }
    }

    private var dropZone: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)

            VStack(spacing: 6) {
                Text("Drop a volume folder here")
                    .font(.system(size: 19, weight: .medium))

                Text("A folder of page images — JPG, PNG, WebP, HEIC or TIFF.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Choose Folder\u{2026}") { Task { @MainActor in AppRouter.chooseFolder() } }
                .keyboardShortcut("o", modifiers: .command)

            if let rejection {
                Text(rejection)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .padding(44)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDropTarget
                      ? Color.accentColor.opacity(0.10)
                      : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isDropTarget ? Color.accentColor : Color.primary.opacity(0.18),
                    style: StrokeStyle(lineWidth: isDropTarget ? 2.5 : 1.5, dash: [10, 7])
                )
        )
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
    }

    private func loadFirstFolder(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue
            else {
                reject(url)
                return
            }
            DispatchQueue.main.async {
                rejection = AppRouter.shared.open(url) ? nil : noPages(in: url)
            }
        }
        return true
    }

    private func reject(_ url: URL) {
        DispatchQueue.main.async { rejection = noPages(in: url) }
    }

    private func noPages(in url: URL) -> String {
        "\(url.lastPathComponent) has no images this app can read. Drop the folder that holds the pages."
    }
}

