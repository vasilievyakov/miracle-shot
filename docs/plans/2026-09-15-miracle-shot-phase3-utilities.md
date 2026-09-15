# Miracle Shot — Phase 3: Utilities (Pin, OCR, Scrolling Capture)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task (implementers on Sonnet, waves per the table below).

**Goal:** The three utilities of the design: pin a screenshot as a floating always-on-top panel, recognize text (ru + en) into the clipboard, and capture a scrolling window into one long image; all reachable from the quick preview or a hotkey and flowing through the normal capture path.

**Architecture:** Pure logic in `MiracleShotCore`: `PinTransform` (opacity/scale clamping), `TextBlock`/`OCRResult`/`OCRMapping` (Vision observation -> pixel rects, line assembly), `FrameDiff` (normalized difference on a sample grid), `ImageStitcher` (overlap search with static header/footer detection). AppKit/system layer in `MiracleShotUI`: `PinPanel`/`PinController`, `OCRService` (Vision), `ScrollCaptureService` (frames via `CaptureServicing`, scroll events via `ScrollEventSending` when Accessibility is granted, manual mode otherwise), new coordinator entry points behind protocols with fakes. A new `CaptureAction.captureScrolling` with default hotkey shift+cmd+3.

**Tech Stack:** Swift 6, SwiftPM (Package.swift unchanged), XCTest, Vision, ScreenCaptureKit (existing), CoreGraphics events, AppKit.

**Out of scope:** OCR overlay with selectable text, pin editing, scrolling capture of horizontal content, capturing hidden/minimized windows.

---

## Conventions (same as before)

- Repo `/Users/vasiliev/cleanshotvibed`; worktrees `/Users/vasiliev/miracle-shot-wt/task-N`, branches `task/N-slug`, merge `--no-ff` into `master`. Baseline: 320 tests green, tag `phase-2b-complete`.
- TDD, no emoji, no "ё", colors only via `BrandPalette`, `@MainActor` UI, Swift 6 strict concurrency. Commit messages in English ending with a blank line and `Claude-Session: https://claude.ai/code/session_012TeusS6XfhDMHoM7fu1tzs`.
- Helpers: `Tests/MiracleShotCoreTests/Helpers/TestImages.swift` (`solid`, `pixel`, `channel`, `context`, `assertClose`), `Tests/MiracleShotAppTests/Helpers/Fakes.swift` (`CallLog`, `makeCapture`, `makeTestImage`, fakes).
- Coordinates: `WindowInfo.frame` and `Capture.bounds` are CG global points (origin top-left of the primary display). Image pixels: origin top-left, y down.

## Waves

| Wave | Tasks | Notes |
|------|-------|-------|
| 1 | Task 1 (PinTransform), Task 2 (OCR mapping), Task 3 (FrameDiff), Task 4 (ImageStitcher) | pure Core, disjoint files |
| 2 | Task 5 (Pin panel), Task 6 (OCR service + coordinator), Task 7 (scroll capture service + action + coordinator) | UI; 7 needs 3 and 4; 5/6/7 touch different files except `ServiceProtocols.swift`, `Fakes.swift`, `CaptureCoordinator.swift`, `AppDelegate.swift`: Task 6 and 7 both edit those, so Task 7 starts after Task 6 is merged |
| 3 | Task 8 (wiring, build, manual checklist, corpus) | after everything |

---

### Task 1: PinTransform

**Files:** Create `Sources/MiracleShotCore/Pin/PinTransform.swift`; test `Tests/MiracleShotCoreTests/PinTransformTests.swift`.

```swift
/// Opacity and scale of a pinned screenshot, clamped so it can never vanish or explode.
public struct PinTransform: Sendable, Equatable {
    public static let opacityRange: ClosedRange<CGFloat> = 0.2...1.0
    public static let scaleRange: ClosedRange<CGFloat> = 0.25...4.0
    public static let opacityStep: CGFloat = 0.1
    /// Multiplicative step for keyboard zoom.
    public static let scaleStep: CGFloat = 1.25
    /// Multiplicative step per wheel line.
    public static let wheelScaleStep: CGFloat = 1.05

    public var opacity: CGFloat   // clamped on set
    public var scale: CGFloat     // clamped on set
    public init(opacity: CGFloat = 1, scale: CGFloat = 1)

    public func opacityIncreased() -> PinTransform
    public func opacityDecreased() -> PinTransform
    public func scaledUp(by factor: CGFloat = scaleStep) -> PinTransform
    public func scaledDown(by factor: CGFloat = scaleStep) -> PinTransform
    /// Wheel delta in lines (positive = zoom in); each line multiplies by `wheelScaleStep`.
    public func wheeled(lines: CGFloat) -> PinTransform
    public static let identity = PinTransform()
    /// "100 %" / "80 %" style labels for the HUD.
    public var scaleLabel: String     // Int(scale * 100) + " %"
    public var opacityLabel: String   // Int(opacity * 100) + " %"
}
```

Tests: clamping at both ends on init and after steps; step values; wheel with fractional lines (`wheeled(lines: 2)` == scale * 1.05^2 within 1e-9, negative lines zoom out); labels round (`0.3333` -> "33 %").

Commit: "Add PinTransform".

---

### Task 2: OCR mapping and text assembly

**Files:** Create `Sources/MiracleShotCore/OCR/OCRResult.swift`; test `Tests/MiracleShotCoreTests/OCRMappingTests.swift`.

```swift
public struct TextBlock: Sendable, Equatable {
    public var text: String
    /// Pixel rect in the source image, origin top-left.
    public var rect: CGRect
    public var confidence: Float
    public init(text: String, rect: CGRect, confidence: Float)
}

public struct OCRResult: Sendable, Equatable {
    public var blocks: [TextBlock]
    public init(blocks: [TextBlock])
    public var isEmpty: Bool
    /// Blocks grouped into lines by vertical overlap (two blocks share a line when their rects overlap vertically
    /// by more than half of the smaller height), lines ordered top to bottom, blocks in a line left to right,
    /// blocks joined with a space, lines with "\n". Paragraph breaks (vertical gap larger than 1.5 lines) become "\n\n".
    public var text: String
    /// The first `count` non-empty lines of `text`, for notifications.
    public func preview(lines count: Int) -> String
}

public enum OCRMapping {
    /// Vision gives normalized rects with origin bottom-left; convert to pixel rects with origin top-left.
    public static func pixelRect(normalized: CGRect, imageSize: CGSize) -> CGRect
    public static func block(text: String, normalized: CGRect, confidence: Float, imageSize: CGSize) -> TextBlock
}
```

Tests: `pixelRect` flips y (`normalized (0.1, 0.8, 0.5, 0.1)` in 1000x500 -> `(100, 50, 500, 50)`); line assembly with three blocks on two lines in scrambled order; a block slightly offset vertically still joins its line; paragraph gap makes a blank line; `preview(lines: 2)` skips empty lines; `isEmpty`.

Commit: "Add OCR result mapping and line assembly".

---

### Task 3: FrameDiff

**Files:** Create `Sources/MiracleShotCore/Scroll/FrameDiff.swift`; test `Tests/MiracleShotCoreTests/FrameDiffTests.swift`.

```swift
public enum FrameDiff {
    /// Mean absolute difference over a `grid x grid` sample of pixels (RGB, ignoring alpha), normalized to 0...1.
    /// Images of different sizes return 1. Sampling makes a 5K frame comparison cost a few thousand reads.
    public static func difference(_ a: CGImage, _ b: CGImage, grid: Int = 48) -> Double
    /// Below this the content is considered still (scroll animation finished).
    public static let settledThreshold = 0.004
    /// Below this two consecutive settled frames are considered the same page (end of content).
    public static let samePageThreshold = 0.002
    /// Row-wise difference: for `rowCount` evenly spaced rows returns the per-row mean absolute difference,
    /// used by the stitcher's static-region detection.
    public static func rowDifferences(_ a: CGImage, _ b: CGImage, rowCount: Int) -> [Double]
}
```

Implementation: draw both images into 8-bit sRGB contexts once (`TestImages.context` idiom in Core: a private helper), sample with `UnsafePointer<UInt8>`.

Tests: identical frames -> 0; an image and its inverse -> close to 1; a frame with a 10 percent band changed from ink to bone -> between 0.05 and 0.15; different sizes -> 1; `rowDifferences` marks the changed band rows and leaves others at 0.

Commit: "Add FrameDiff".

---

### Task 4: ImageStitcher

**Files:** Create `Sources/MiracleShotCore/Scroll/ImageStitcher.swift`; test `Tests/MiracleShotCoreTests/ImageStitcherTests.swift`; fixtures folder `Tests/MiracleShotCoreTests/Fixtures/scroll/` (exists, with `.gitkeep`) gets a `README.md` describing the corpus layout: `<app>/frame-00.png ...` plus `expected.png`, and `ImageStitcherCorpusTests` that iterates every subfolder present (zero folders = zero tests, not a failure).

```swift
public struct StitchResult: Sendable {
    public let image: CGImage
    /// True when some pair had no detectable overlap and was concatenated instead.
    public let usedFallback: Bool
    /// Rows of static header and footer that were kept once.
    public let headerRows: Int
    public let footerRows: Int
}

public enum ImageStitcher {
    /// Stitches vertically scrolled frames of the same width. One frame returns itself.
    /// Steps: (1) static header/footer = leading/trailing rows identical (row difference <= `staticTolerance`)
    /// across all consecutive pairs, capped at 40 percent of the height each; (2) for each consecutive pair find
    /// the overlap `d` (rows) in `minOverlap...(dynamicHeight - 1)` such that the last `d` dynamic rows of A match
    /// the first `d` dynamic rows of B with mean absolute difference <= `matchTolerance` (row hashes narrow the
    /// candidates, full comparison confirms; prefer the largest matching `d`); (3) append B's dynamic rows after
    /// `d`; (4) reattach the header at the top and the footer at the bottom. A pair without a match is appended
    /// whole and `usedFallback` becomes true. Frames whose dynamic part fully repeats the previous one are skipped.
    public static func stitch(_ frames: [CGImage], minOverlap: Int = 8, matchTolerance: Double = 6.0 / 255,
                              staticTolerance: Double = 2.0 / 255) -> StitchResult?
}
```

Implementation notes: work on RGBA8 buffers (one draw per frame); per-row signature = sum of the row's bytes plus a 64-bit hash of every 8th pixel, to find candidate offsets in O(rows); confirm candidates with a full-row mean absolute difference on the overlap band (early exit when the running mean exceeds the tolerance). Output built in one context of the final height.

Tests (synthetic, deterministic): build a tall "page" (e.g. 300 x 1400) with a pseudo-random pattern that is not periodic (hash-based noise per pixel plus horizontal bands of text-like rectangles), a 40-row header and 30-row footer, then cut frames of height 400 with a scroll step of 300 (100 rows overlap), each frame = header + page window + footer:
- `testStitchesFramesBackIntoThePage`: result height == 40 + 1400 + 30, and every 50th row equals the page (with `assertClose` tolerance 2).
- `testKeepsHeaderAndFooterOnce`: `headerRows == 40`, `footerRows == 30`.
- `testSkipsRepeatedLastFrame` (the last frame repeated twice: same result).
- `testFallsBackToConcatenationWithoutOverlap`: two unrelated frames -> height sum, `usedFallback == true`.
- `testSingleFrameIsReturnedAsIs`.
- `testUniformFramesDoNotFalselyMatchEverywhere`: frames of a solid color with one distinct band each: overlap found only where the band lines up (the largest consistent `d`); document the expectation in the test.
- Corpus test: skipped when no folders.

Commit: "Add ImageStitcher with static header and footer detection".

---

### Task 5: Pin panel

**Files:** Create `Sources/MiracleShotUI/Pin/PinPanel.swift`, `Sources/MiracleShotUI/Pin/PinController.swift`; modify `Sources/MiracleShotUI/App/AppDelegate.swift` only to add `preview.handlers[.pin]` (one closure). No automated tests (AppKit); suite stays green.

- `PinController` (`@MainActor final class`): `func pin(_ capture: Capture)` creates a `PinPanel` centered on the capture's `bounds` (converted from CG global to AppKit coordinates via `SelectionGeometry.flipped` and the primary screen height, like the overlay does) so the pin appears exactly where the screenshot was taken; keeps strong references in an array; removes on close.
- `PinPanel: NSPanel` borderless, `.floating`, `hasShadow = true`, `isMovableByWindowBackground = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isOpaque = false`, content = `NSImageView` with `NSImage(cgImage:size:)` at natural points size times `transform.scale`; `alphaValue = transform.opacity`; `becomesKeyOnlyIfNeeded = false` so it takes key on click for keyboard control.
- Keys (`keyDown`): Esc closes; `+`/`=` scale up, `-` scale down, `]` opacity up, `[` opacity down, `0` reset; wheel: `scrollWheel` with `deltaY` lines -> `transform.wheeled`, with Option held -> opacity by sign; double-click (`mouseDown` with `clickCount == 2`) closes. Resizing keeps the panel's center fixed.
- HUD: a small ink2 rounded label in mono (`BrandFont.mono(size: 12, weight: 600)`, bone text) at the panel's bottom center showing `scaleLabel` or `opacityLabel` for 600 ms after each change (a `DispatchWorkItem` cancelled on the next change).
- `preview.handlers[.pin] = { [weak self] capture, _ in self?.pins.pin(capture) }` in `AppDelegate`.

Commit: "Add the pin panel".

---

### Task 6: OCR service and coordinator

**Files:** Modify `Sources/MiracleShotUI/Services/ServiceProtocols.swift` (`OCRServicing`, `ClipboardServicing.copyText`), `Sources/MiracleShotUI/Services/ClipboardService.swift`, `Sources/MiracleShotUI/Coordinator/CaptureCoordinator.swift`, `Tests/MiracleShotAppTests/Helpers/Fakes.swift`, `Tests/MiracleShotAppTests/CaptureCoordinatorTests.swift`, `Sources/MiracleShotUI/App/AppDelegate.swift`; create `Sources/MiracleShotUI/Services/OCRService.swift`.

```swift
@MainActor public protocol OCRServicing: AnyObject {
    func recognize(_ image: CGImage) async throws -> OCRResult
}
// ClipboardServicing gains:
    func copyText(_ text: String)
```

- `OCRService`: `VNRecognizeTextRequest` with `recognitionLevel = .accurate`, `recognitionLanguages = ["ru-RU", "en-US"]`, `usesLanguageCorrection = true`; `VNImageRequestHandler(cgImage:)`; run on a background task (`Task.detached`) and hop back; map observations through `OCRMapping.block(text: candidate.string, normalized: observation.boundingBox, confidence: candidate.confidence, imageSize:)` using `topCandidates(1)`.
- Coordinator: `init` gains `ocr: OCRServicing` (update `AppDelegate` and the tests' `setUp`), plus:

```swift
    /// Recognizes text in `capture`; the result goes to the clipboard as plain text with a notification showing
    /// the first lines. No text: a notification and the clipboard is left alone.
    public func recognizeText(in capture: Capture) async
```

  Errors from the service: notification "Text recognition failed" with the error description. Success: `clipboard.copyText(result.text)`, notification title "Text copied", body `result.preview(lines: 3)`.
- `preview.handlers[.ocr] = { capture, _ in Task { await coordinator.recognizeText(in: capture) } }`.
- Tests: `FakeOCR` (`result`, `error`, log entry "ocr"); `testRecognizeTextCopiesAndNotifies`, `testRecognizeTextWithoutTextNotifiesAndLeavesClipboard`, `testRecognizeTextFailureNotifiesError`; `FakeClipboard` records `copiedText`.

Commit: "Add OCR through Vision to the preview".

---

### Task 7: Scrolling capture

**Files:** Modify `Sources/MiracleShotCore/Settings/CaptureAction.swift` (add `captureScrolling`, title "Capture Scrolling Window", `captureMode` `.window`), `Settings.swift` (default hotkey shift+cmd+3; when loading, fill in missing actions from the defaults if their spec is not used by another action), `Sources/MiracleShotUI/Services/ServiceProtocols.swift` (`ScrollCapturing`), `CaptureCoordinator.swift`, `AppDelegate.swift`, `Fakes.swift`, `CaptureCoordinatorTests.swift`, `Tests/MiracleShotCoreTests/SettingsTests.swift`; create `Sources/MiracleShotUI/Services/ScrollCaptureService.swift`, `Sources/MiracleShotUI/Scroll/ScrollHUDPanel.swift`.

```swift
@MainActor public protocol ScrollCapturing: AnyObject {
    /// Scrolls `window` and returns the stitched capture. Throws `CaptureError.cancelled` when the user stops it.
    func captureScrolling(window: WindowInfo) async throws -> Capture
}
// CaptureError gains `.cancelled` ("Cancelled.") and `.noFrames` ("The window produced no frames.").
```

- Coordinator `perform(.captureScrolling)`: same guards; `transition(.hotkey(.window))`; overlay in window mode; on a `.window(info)` result -> `transition(.selectionMade)`, `let shot = try await scroll.captureScrolling(window: info)`, then the normal success/failure transitions and `finish`. An `.area` result (user dragged instead of clicking a window) -> cancel with a notification "Click a window to capture scrolling content". `.cancelled` -> `.captureFailed` transition without an error toast.
- `ScrollCaptureService(capture: CaptureServicing)`:
  1. Frame 0 = `capture.capture(.window(info))`.
  2. Auto mode if `AXIsProcessTrusted()`: warp the cursor to the window center (`CGWarpMouseCursorPosition`), then loop: post a scroll event `CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-step), wheel2: 0, wheel3: 0)` with `location` = window center, `step = window height in points * 0.75` (as pixels for the event: points), post to `.cghidEventTap`; wait for settle: poll every 80 ms capturing the window until `FrameDiff.difference(prev, cur) < settledThreshold` or 400 ms; append when `FrameDiff.difference(lastKept, cur) >= samePageThreshold`, else stop (page end). Limits: 50 frames or 30 s. Show `ScrollHUDPanel` "Scrolling... N frames. Esc to stop" during the loop; Esc (the HUD is key) -> stop and stitch what exists (at least frame 0).
  3. Manual mode otherwise: HUD "Scroll the window with the mouse or trackpad, then press Return. Esc cancels."; poll every 150 ms; append each frame that differs from the last kept by more than `samePageThreshold` and is settled (two consecutive polls within `settledThreshold`); Return -> stitch; Esc -> throw `.cancelled`. Also used when auto mode stops early because the user pressed Esc after at least two frames? No: Esc always stops-and-stitches in auto mode, cancels in manual mode.
  4. `ImageStitcher.stitch(frames)`; `usedFallback` -> the coordinator posts a non-error notification "Some parts could not be aligned and were appended". Result `Capture(image:, sourceAppName: info.ownerName, sourceWindowTitle: info.title, bounds: info.frame with the stitched height in points, scaleFactor: frame0.scaleFactor)`.
  5. Debug frame dump: when the environment variable `MIRACLE_SHOT_SCROLL_DUMP` is set to a directory path, write every kept frame as `frame-NN.png` and the result as `stitched.png` there (this is how the phase-3 corpus is collected).
- `ScrollHUDPanel`: small floating ink2 panel at the top center of the window's screen, mono text, key-capturing (`canBecomeKey = true`), `onReturn`/`onEscape` closures.
- Tests: `FakeScrollCapture` (`result`, `error`, log "scroll(<id>)"); `testCaptureScrollingUsesTheWindowResult`, `testCaptureScrollingWithAreaResultCancels`, `testCaptureScrollingCancelledReturnsToIdleQuietly` (no error notification), `testCaptureScrollingFailureNotifies`; `SettingsTests`: default hotkey for `captureScrolling`, loading an old settings file without it fills shift+cmd+3, but not when shift+cmd+3 is already taken by another action.
- `AppDelegate`: menu item appears automatically (`CaptureAction.allCases`); pass `ScrollCaptureService(capture: captureService)` into the coordinator.

Commit: "Add scrolling capture with auto and manual modes".

---

### Task 8: Wiring, build, manual checklist, corpus

- Build with `scripts/build-app.sh`, relaunch. The app now needs Accessibility for auto scrolling: on the first scrolling capture without it, post a notification "Allow Miracle Shot in System Settings > Privacy & Security > Accessibility for automatic scrolling; manual mode is active" and call `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` once.
- Manual checklist: pin (position, drag, keys, wheel, HUD, Esc, double-click, multiple pins), OCR on a Russian/English screenshot (Cmd+V gives text; empty screenshot gives "No text found"), scrolling capture in Safari, Terminal, Finder, VS Code (auto after granting Accessibility; manual before), the `{seq}` and history entries.
- Corpus: run scrolling captures with `MIRACLE_SHOT_SCROLL_DUMP=/path` set (launch the app from Terminal with the variable), copy the frames of 4-5 windows into `Tests/MiracleShotCoreTests/Fixtures/scroll/<app>/` with a reviewed `expected.png`; the corpus test must pass; tune `matchTolerance`/`minOverlap` if needed. Phase closes when the corpus passes.

Then `git tag phase-3-complete`.
