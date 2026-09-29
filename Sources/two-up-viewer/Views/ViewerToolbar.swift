// Copyright (c) 2026 badjeff
// SPDX-License-Identifier: MIT

import SwiftUI
import AppKit

struct ViewerToolbar: ToolbarContent {

    @ObservedObject var model: ViewerModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            SidebarToggle(model: model)

            Button { model.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack)
            .help("Previous Page (\u{2190})")

            Button { model.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward)
            .help("Next Page (\u{2192})")
        }

        ToolbarItem(placement: .principal) {
            PageIndicator(model: model)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ZoomStepper(model: model)
            ContinuousScrollButton(model: model)
            LayoutMenu(model: model)
            BackgroundMenu(model: model)
        }
    }
}

private struct SidebarToggle: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        Button {
            model.sidebarVisible.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .foregroundStyle(model.sidebarVisible
                                 ? Color.accentColor : Color.secondary)
        }
        .help(model.sidebarVisible
              ? "Hide Page Strip (\u{2303}S)"
              : "Show Page Strip (\u{2303}S)")
        .accessibilityLabel(model.sidebarVisible
                            ? "Hide Page Strip"
                            : "Show Page Strip")
    }
}

private struct PageIndicator: View {
    @ObservedObject var model: ViewerModel
    @State private var popoverOpen = false

    var body: some View {
        Button { popoverOpen.toggle() } label: {
            HStack(spacing: 5) {
                Text(model.pageBadge)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \(model.pageCount)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .help("Go to Page (\u{2318}G)")
        .popover(isPresented: $popoverOpen, arrowEdge: .bottom) {
            PagePopover(model: model)
        }
        .accessibilityLabel("Go to Page \(model.pageCounterText)")
    }
}

private struct PagePopover: View {
    @ObservedObject var model: ViewerModel
    @State private var draft = ""
    @FocusState private var editing: Bool

    private var lastIndex: Double { Double(max(0, model.pageCount - 1)) }

    private var track: Double {
        guard lastIndex > 0 else { return 0 }
        return Double(model.currentPage) / lastIndex
    }

    private var trackValue: Binding<Double> {
        Binding(get: { track },
                set: { model.scrub(to: model.spreadAnchor(
                    for: Int(($0 * lastIndex).rounded()))) })
    }

    private func commit() {
        let typed = draft.trimmingCharacters(in: .whitespaces)
        if let number = Int(typed), number >= 1, number <= model.pageCount {
            model.go(to: model.spreadAnchor(for: number - 1))
        }
        sync()
    }

    private func sync() {
        draft = "\(model.currentPage + 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current: \(model.pageBadge)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                TextField("Page", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .focused($editing)
                    .onSubmit(commit)
                    .help("Type a page number and press Return")
                Text("of \(model.pageCount)")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                Spacer(minLength: 0)
            }

            Slider(value: trackValue, in: 0 ... 1)
                .help("Drag to move through the volume")
                .disabled(model.pageCount < 2)
        }
        .padding(12)
        .frame(width: 230)
        .buttonStyle(.borderless)
        .onAppear { sync() }
        .onChange(of: model.currentPage) { _ in sync() }
        .onChange(of: editing) { focused in if !focused { commit() } }
    }
}

private struct ZoomStepper: View {
    @ObservedObject var model: ViewerModel
    @State private var popoverOpen = false

    var body: some View {
        HStack(spacing: 0) {
            Button { model.zoomOut() } label: {
                Image(systemName: "minus")
            }
            .help("Zoom Out (\u{2318}-)")

            Button { popoverOpen.toggle() } label: {
                Text(model.zoomLabel)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .frame(minWidth: 52)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.borderless)
            .help("Zoom: \(model.zoomLabel)")
            .popover(isPresented: $popoverOpen, arrowEdge: .bottom) {
                ZoomPopover(model: model)
            }

            Button { model.zoomIn() } label: {
                Image(systemName: "plus")
            }
            .help("Zoom In (\u{2318}+)")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

private struct ZoomPopover: View {
    @ObservedObject var model: ViewerModel
    @State private var draft = ""
    @FocusState private var editing: Bool

    private static let low = log(ZoomLimits.min)
    private static let high = log(ZoomLimits.max)

    private var track: Double {
        (log(model.effectiveScale) - Self.low) / (Self.high - Self.low)
    }

    private static func snapToSliderStep(_ scale: Double) -> Double {
        let step = ZoomLimits.sliderStepPercent / 100
        return (scale / step).rounded() * step
    }

    private var trackValue: Binding<Double> {
        Binding(get: { track },
                set: { model.setZoom(to: Self.snapToSliderStep(
                    exp(Self.low + $0 * (Self.high - Self.low)))) })
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Actual Size") { model.actualSize() }
            Button("Zoom In") { model.zoomIn() }
            Button("Zoom Out") { model.zoomOut() }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commit() {
        let typed = draft.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let percent = Double(typed), percent > 0 {
            model.setZoom(to: percent / 100)
        }
        sync()
    }

    private func sync() {
        draft = "\(Int((model.effectiveScale * 100).rounded()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current: \(model.zoomLabel)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                TextField("Percent", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .focused($editing)
                    .onSubmit(commit)
                    .help("Type a percent and press Return")
                Text("%")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                Spacer(minLength: 0)
            }

            Slider(value: trackValue, in: 0 ... 1)
                .help("Drag to zoom")

            Divider()

            row

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Button(model.zoomMode == .fitWidth ? "Fit Width \u{2713}" : "Fit Width") {
                    model.fitWidth()
                }
                .help("Scale each page so its width matches the window")

                Button(model.zoomMode == .fitPage ? "Fit Page \u{2713}" : "Fit Page") {
                    model.fitPage()
                }
                .help("Scale each page so the whole page is visible")
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 230)
        .buttonStyle(.borderless)
        .onAppear { sync() }
        .onChange(of: model.effectiveScale) { _ in sync() }
        .onChange(of: editing) { focused in if !focused { commit() } }
    }
}

private struct ContinuousScrollButton: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        Button {
            model.continuousScrolling.toggle()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(model.continuousScrolling
                                 ? Color.accentColor : Color.secondary)
        }
        .help(model.continuousScrolling
              ? "Continuous scrolling — scroll through the volume"
              : "One page at a time — click to turn, scroll to pan a zoomed page")
        .accessibilityLabel(model.continuousScrolling
                            ? "Continuous scrolling" : "Single page navigation")
    }
}

private struct LayoutMenu: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        Menu {
            ForEach(PageLayout.allCases) { layout in
                Button {
                    model.layout = layout
                } label: {
                    Label(layout.title, systemImage: layout.symbol)
                }
            }
            if model.layout == .twoUp {
                Divider()
                ForEach(SpreadOrder.allCases) { order in
                    Button {
                        model.spreadOrder = order
                    } label: {
                        Text(order == model.spreadOrder
                             ? "\(order.title) \u{2713}" : order.title)
                    }
                }
            }
        } label: {
            Image(systemName: model.layout.symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("View Layout")
    }
}

private struct BackgroundMenu: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        Menu {
            ForEach(ViewerBackground.allCases) { bg in
                Button {
                    model.background = bg
                } label: {
                    Label(bg.title, systemImage: bg.symbol)
                }
            }
        } label: {
            Image(systemName: "circle.lefthalf.filled")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Background Color")
    }
}

