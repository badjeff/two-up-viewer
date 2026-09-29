# Working in this repository

Architecture notes and the conventions that hold here. Read this before
changing anything in `Sources/two-up-viewer`.

## Building and testing

`swift build` must be clean — no errors, no warnings. There is no test target
and no linter, so the compiler is the only gate that exists.

`./build-app.sh --quick` is the build to reach for: debug, host architecture
only, cached icon, about two seconds. When the user is about to test a change by
hand, build it for them and say where it is and that it is host-arch debug — a
quick build is a normal deliverable, not something to apologise for. Two things
it will not pick up, so they need a full `./build-app.sh`: the other
architecture's slice, and a changed `Tools/make-icon.swift`. Everything else,
`Info.plist` and signing included, is refreshed. A full build is release,
universal and renders the icon, and is the right default only when the result is
about to be installed or shipped.

`.github/workflows/build.yml` runs the same two builds on a GitHub runner and
attaches the zipped bundle to the run. It is the same gate plus the assertions
the local script does not make, and the app job runs on `main`, on tags and on
demand rather than on every pull request.

## Before you commit

Do not run `git commit` until you are asked to in that same request. Editing,
building and leaving the work in the tree is the default; a green build is not an
instruction to commit. Do not amend, force-push, rebase shared history or change
git configuration unless asked. If a change is left uncommitted, say so plainly
and list what is in the tree.

Do not drive the running app's UI to verify a change without asking first.
Screenshots and window state belong to whoever is testing.

## Comments

Do not add comments to the Swift sources. No `//`, no `///`, no `/* */`. The
codebase carries none, and a new one is a change to be undone rather than added
to. Three exceptions, all mechanical rather than explanatory:

- The two-line copyright/SPDX block at the top of every source file — Swift
  files, `build-app.sh` and `Tools/make-icon.swift`. Keep it identical
  everywhere, and in step with `LICENSE`.
- The `// swift-tools-version:` line in `Package.swift`, which has to stay the
  *first* line: SwiftPM reads the file's first comment as the tools version and
  rejects a manifest that opens with anything else, so the copyright block goes
  below it, not above.
- `// MARK:` separators, which drive Xcode's jump bar.

The reasoning that a comment would have held goes here instead, into *Traps that
are not obvious from the code* below. That section is the only place that
knowledge is kept, so leaving a trap out of it loses it entirely.

## What the code does

macOS, AppKit, with SwiftUI for chrome. One volume open at a time.

- `TwoUpViewerApp.swift` — app entry, settings scene, one `VolumeWindow`, the
  `Go to Page` sheet, and the command groups. The View menu is
  `CommandGroup(replacing: .sidebar)`, so a reader shortcut has to be added
  there rather than assumed from the stock one.
- `Support/ViewerTypes.swift` — `PageLayout`, `SpreadOrder`, `ViewerBackground`,
  and the settings notification.
- `Support/AppSettings.swift` — `UserDefaults` wrapper for zoom mode and scale,
  layout, spread order, background, rotation, sidebar width and visibility, and
  the recents list. Only `spreadOrder` posts a notification, and the only writer
  is `ViewerModel`, which also subscribes to it — so the round trip is a no-op
  that exists for the second writer the Settings window used to be.
- `Support/AppRouter.swift` — resolves a folder to an openable volume and opens
  it. `open` is main-actor, so its `containsPages` listing is main-actor work;
  that is the one listing that is not off-thread.
- `Support/NaturalOrder.swift` — natural sort, so `page 2` precedes `page 10`.
- `Model/VolumeScanner.swift` — `ComicPage`, `ComicVolume`, and `enum`
  `VolumeScanner`: `scan` runs off the main actor with bounded header
  concurrency. A page is anything whose extension is in `pageExtensions` — the
  list is not filtered for directories, so a folder named `cover.jpg` is a page
  that never decodes. `containsPages` is deliberately synchronous, because
  `AppRouter.open` returns a `Bool`.
- `Model/ImagePipeline.swift` — `actor`. Decodes in `Task.detached`, so decoding
  is off the main thread. Two image caches: full-size for the canvas, small for
  thumbnails and `prefetch`, so prefetching never evicts what is on screen.
  `prefetch` is serial, nearest-page-first, and `await`ed rather than spawned —
  the caller's cancellation has to reach it, so `ViewerModel` owns the task.
- `Model/ViewerModel.swift` — document state: layout, spread order, rotation,
  zoom, current page, sidebar width and visibility. Decode and load state is not
  here; it belongs to whichever reader is mounted. `needsInitialFit` is why a fit
  mode is not left at 100%: the mode is applied when the first real viewport size
  arrives, not before.
- `Model/ZoomMode.swift` — zoom presets and their limits.
- `Views/DocumentView.swift` — the reader. Hosts the strip, the seam and the
  scroller, primes the current spread, and warms neighbours once what is on
  screen is up. Hiding the strip takes the seam out of the layout with it.
- `Views/ContinuousScrollerView.swift` — continuous scrolling, and the only
  place that decides which pages are decoded.
  - `ContinuousCanvas` is one `NSView` standing in for the whole document, so it
    is as tall as the volume. Repaint `visibleRect`, never `needsDisplay = true`,
    and every repaint goes through `scheduleRepaint`.
  - Pages are grouped into four-page tiles. `updateWindow` computes the window
    from the visible spread, and a page with no decoded image draws a numbered
    placeholder. The budget is in pages, since a tile is four decodes. Nothing is
    decoded while `isMoving`; the window is recomputed once the viewport has held
    still for `scrollSettleDelay`. A jump names its destination and primes it
    first, so jumps do not land blank.
  - `isZooming` is mirrored onto the canvas so a pinch does not drop the decoded
    set on every frame. No final gesture action is guaranteed, so `syncZoomState`
    re-reads the recognizer before each rebuild.
  - `ContinuousScrollView` and `ContinuousCanvas` are `NSView` subclasses, so
    they are implicitly `@MainActor`: their static members are main-actor
    isolated, and a `Task {}` created inside one inherits the main actor. An
    `await MainActor.run` here would be pure overhead.
- `Views/PagedReaderView.swift` — the one-spread-at-a-time reader, behind the
  continuous-scroll toggle. `Coordinator` owns that spread's decodes and abandons
  them on a turn.
- `Views/PageDrawing.swift` — the only place an image becomes pixels. Undoes the
  canvas's y flip, applies rotation, draws the placeholder.
- `Views/ThumbnailSidebar.swift` — the page strip, and the volume picker. Builds a
  `ThumbnailCell` per page and loads its thumbnail when it first appears. Rows are
  a `LazyVStack`, so `visibleRows` is the set of rows on screen and the strip only
  scrolls when the highlighted row is not in it — anchored `.bottom` for a row
  above the visible range, `.top` for one below, `.center` otherwise. A page
  change the reader scrolled to is ignored (`currentPageCameFromScroll`); the
  highlight catches up 600ms after `scrollRestToken` instead, so scrolling the
  canvas does not fight the strip. The pending settle task is cancelled on
  teardown, since hiding the strip disposes the view mid-scroll.
- `Views/SidebarDivider.swift` — the seam between the sidebar and the canvas,
  and the only way the sidebar's width changes.
- `Views/ArrowPageKeys.swift` — arrow-key handling, restricted to page moves. The
  monitor's closure captures the model, so `dismantleNSView` has to unregister it.
- `Views/ViewerToolbar.swift` — the toolbar and the popovers it opens. The strip's
  toggle leads the navigation group, so it lands at the far left; ⌃S lives on the
  menu command, not the button, so the shortcut fires once.

## Traps that are not obvious from the code

- **`isFlipped` plus `CGContext`.** The canvas is flipped, so anything drawn with
  Core Graphics has to undo the mirror. The context's y axis runs down the screen
  while `CGContext.draw` lays images out from the rect's bottom edge.
  `PageDrawing` is the only place that undoes it; new drawing belongs there.
- **`rowIndex(atOrBelow:)` bisects, and is only correct because the bands are in
  document order.** The bands are not sorted by any other key. Sorting or
  filtering them in place silently returns the wrong row.
- **A row's horizontal target comes from that row's own rects, never the
  document's.** `layout` centres every row on the axis of the *widest* row, so one
  page wider than the rest — a landscape cover, say — pushes the document's edge
  out and leaves every other row short of it; a target taken from
  `documentView.frame.width` lands the spread short of the leading edge by exactly
  the width the odd page added. So `scrollTargetX` reads the target row's own
  `minX`/`maxX`. And a leading-edge target is only right while the row overflows
  the viewport: a row narrower than the viewport fits whole, and pinning its
  leading edge to the viewport's is not a scroll position but an offset that slides
  the row sideways, because the row is centred inside the wider document — in
  right-to-left that reads as "every page is jammed against the right edge". Hence
  `scrollTargetX` checks the row's own width first and returns the centring offset
  when it fits. Same branch for one-up and two-up; only the number of pages sharing
  the row differs.
- **A scroll target is only meaningful against a real viewport.** The first
  `updateNSView` on a fresh window runs before AppKit has sized the scroller, so
  `viewport` is the `max(1, …)` floor — a one-pixel scroller. Anchoring a page move
  against that lands the reader on the left end of the spread in right-to-left,
  and the animator write is dropped outright because the view is not in a window
  yet. Nothing retried it: `updateNSView` skips an index it thinks it already
  handled, so the wrong offset stood until the reader navigated. `scrollToPage`
  therefore records the request and `applyRequestedPage(animated:)` performs it,
  and `layout()` retries it as soon as the viewport is real. A move that skips the
  deferral has to anchor against a real viewport, or the leading edge is never
  established.
- **The horizontal anchor is derived state, but a width change must not re-derive
  it.** `scrollTargetX` is a function of the row rects, the viewport width and the
  direction, so `updateNSView` cannot rescue a stale origin — it only moves on a
  *new* index. `setLayout` therefore ends with `reanchorLeadingEdge()`. But it is
  keyed only on the inputs that change the *document* — scale, rotation, columns,
  direction, gutter — and deliberately **not** on the viewport width. A window
  resize or a sidebar drag changes the width, and re-anchoring there snapped the
  spread to its leading edge, throwing away the reader's position: the user
  resized the sidebar while reading the left page of a two-up spread and lost their
  place. The reader's offset is theirs; a resize leaves it alone and lets the clip
  view clamp. Two more deliberate choices: it anchors on the page at the centre of
  the viewport, which is the page a continuous reader is showing, not the last one
  requested; and it moves `x` only — re-anchoring `y` would yank the reader to the
  row top every time the window changed size.
- **The margin belongs in the canvas geometry rather than in a SwiftUI `padding`.**
  `ViewerModel.canvasInset` insets the continuous canvas on all four sides,
  `PagedCanvas.pageRects` floors its centring origin at the same value, and both
  `scrollTargetX` and `scrollTargetY` add it back onto the target so a deliberate
  move lands *with* the margin rather than flush to the edge. `fittingViewport`
  subtracts it twice, or fit-width would scale pages up until they touched the
  panel edge again.
- **The quick build is host-arch and caches the icon, which is why it is not
  shippable.** `--quick` builds one slice and `cp`s it instead of calling `lipo`,
  so it skips the other architecture's cross-compile entirely. It still signs and
  verifies, and the bundle launches and takes folder drops the same, so the
  closing line says "not for shipping" precisely so it cannot be mistaken for the
  installable one. It also copies `build/AppIcon.icns` forward, with the staleness
  test `-nt Tools/make-icon.swift` — not "does the file exist" — because that is
  the icon's only input. Rendering is a `swift` interpreter run plus `iconutil`,
  most of the wall clock on an otherwise-unchanged build, and dropping it is what
  makes the quick path two seconds instead of twenty-five. Touching
  `make-icon.swift` is enough to force a re-render, so there is no cache to clear
  by hand. A full build renders unconditionally, so CI needs no cache step —
  there is nothing there to warm.
- **Warnings are errors, in `build-app.sh` and in CI.** `-Xswiftc
  -warnings-as-errors` is on the build the script runs and on the workflow's
  gate, so a new diagnostic fails instead of scrolling past; a bare `swift build`
  still only prints them. Release can warn where debug does not, since the
  optimiser changes what the compiler reports, so a full build is what finds out.
- **The deployment target belongs to the manifest, not to the SDK.**
  `Package.swift` declares `platforms: [.macOS(.v13)]` and SwiftPM turns that into
  a `-target …-macosx13.0`, so `LC_BUILD_VERSION.minos` is `13.0` whatever Xcode
  built it — a newer toolchain does not raise the floor. `Info.plist`'s
  `LSMinimumSystemVersion` is a hand-maintained duplicate of that number, and CI
  fails when the two disagree. Nothing in the tree carries an `#available` guard,
  so an API newer than 13.0 is not a degraded feature but a dyld failure at
  launch on the oldest supported Mac. That is what makes a newer toolchain's new
  warnings worth reading rather than suppressing: each one is a line that would
  not have run on macOS 13.
- **The two slices and the deployment target are asserted, not assumed.** The
  script verifies the signature and nothing fails when a slice is missing, which
  `--quick` produces on purpose. CI therefore checks `lipo -archs` for both
  `x86_64` and `arm64`, reads `vtool -show-build -arch` per slice for the minos,
  and requires every `otool -L` dependency to be `/usr/lib` or `/System` — a
  toolchain dylib is how a bundle ends up needing the machine that built it.
  That parse keys off otool's tab indent, never off a field count: a newer otool
  prints a `(architecture …)` header per slice of a fat binary, and that header's
  first field is the binary's own path, so a field count reads it as a dependency
  and fails a bundle that is clean. It failed that way once on the first CI run.
  Cross-compiling the foreign slice is not a new risk here: the script only ever
  compiles it, never runs it, and already does it in whichever direction the host
  is not.
- **The seam is an `NSView`, and its drag is relative to the mousedown point.** A
  SwiftUI drag target drawn as an invisible view does not reliably receive the
  mouse here, so `SidebarDividerView` claims a real 9pt column instead — and 9pt
  is all it claims: AppKit tests subviews in frame order, so an outset
  `hitTest(_:)` never widens it. Because the grab area is wider than the 1pt line
  it draws, the drag has to be measured from where the mousedown landed, not from
  the seam position, or the divider jumps by half the grab width on the first
  dragged event.
- **`setCurrentPageFromScroll` and `setPage` are not interchangeable.** The first
  records a crossing the reader scrolled to and must never move the scroller; the
  second is a deliberate move and is the only one that does. Using the second
  where the first belongs fights the reader's own scrolling.
- **A deliberate move jumps; it does not animate.** `applyRequestedPage` writes the
  clip origin with `scroll(to:)`, never `animator()`. The user asked for a sharp
  jump to the offset, and an animated page turn read as lag on a click. The
  `Navigation` enum that used to pick between animating and not is gone with it —
  `go(to:)` and `scrub(to:)` are now the same deliberate move, kept as separate
  entry points only because the toolbar's slider and the nav buttons call different
  ones. Two-up snapping still goes through `spreadAnchor(for:)`: the parity rule
  has one owner, and a deliberate move that skips it lands on a spread the reader
  never shows.
- **The canvas frame is set twice.** `ContinuousCanvas.layout` sizes itself and then
  `ContinuousScrollView.setLayout` sets `documentView.frame` from the return
  value. Both are needed — the canvas sizes itself for its own layout pass, the
  scroll view owns the frame.
- **`visibleRect` is stale until AppKit finishes.** That is why `layout()` sets
  `needsVisibleRepaint` and the repaint waits for `layout()` rather than happening
  inline.
- **Right-to-left is applied at three different layers, deliberately.** The canvas
  lays a row out from the far end; the paged reader reverses the order it hands
  pages over in; the thumbnail strip reverses for display. The model only ever
  speaks in reading order, because the decode window and the page strip both want
  that.
- **DPI is sanitised twice, in two files.** `VolumeScanner.header` and
  `ImagePipeline` each clamp an implausible DPI to 72. If you change one, change
  both, or page geometry and decode resolution will disagree.
- **The cache key is a bucket, not a size.** `ImagePipeline.bucket(for:)` rounds a
  target up to a power of two, so two requests within one octave share a cache
  entry. Anything reasoning about "what resolution am I holding" has to reason
  about the bucket too.
- **A tile is resolved by the pages that exist, not by the four-wide range.**
  `ContinuousCanvas.tileRange(_:)` is four wide, but the last tile of any volume
  whose page count is not a multiple of four is short, and the missing indices never
  get an image. So "is this tile done" has to be measured over the range filtered
  by `rects.count` — which is what `isTileResolved` does, and the only thing
  `setImage` is allowed to ask, since the two answers have to agree. When they
  disagreed, the last tile was never recorded as resolved, so `loadTiles`
  re-spawned it, each decode came straight back out of the cache, `finishPage` ran
  `updateWindow` and spawned it again, and the main actor spun at full tilt until
  the app was killed. It showed on the last page because that is where a click
  jumps: `updateWindow(target:)` primes the final tile directly.
