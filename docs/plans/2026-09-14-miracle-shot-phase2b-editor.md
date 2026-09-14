# Miracle Shot — Phase 2b: Annotation Editor

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task (implementers on Sonnet, waves per the table below).

**Goal:** The `Edit` button in the quick preview opens an editor window where the user annotates the screenshot (arrow, rectangle, ellipse, line, freehand, text, numbered steps, blur/pixelate, highlight, crop) with undo/redo, applies a background preset, and exports through the normal capture path (clipboard, file, history, preview) or by drag and drop.

**Architecture:** Everything that can be pure lives in `MiracleShotCore`: the `Annotation` model, `Document`, `UndoStack`, geometry (view/image transforms, handles, hit testing, arrowheads), `AnnotationRenderer` (one CoreGraphics/CoreImage path for the live canvas and for export), and `EditorSession`, a pure state machine that turns mouse/keyboard events into document mutations. The AppKit layer (`MiracleShotUI`) is thin: `EditorCanvasView` forwards events to the session and draws the rendered image plus selection chrome; `EditorWindowController` owns the toolbar, shortcuts and export. Export reuses `CaptureCoordinator` through a new `publish(_:derivedFrom:)` that `applyBackground` also uses.

**Coordinate convention:** annotation geometry is in **source image pixels, origin top-left, y down** (same as `SelectionGeometry`). The renderer flips the CGContext for vector drawing and converts rects for image patches. The canvas converts view points to image pixels with `EditorGeometry`.

**Tech Stack:** Swift 6, SwiftPM (Package.swift unchanged), XCTest, CoreGraphics, CoreText, CoreImage, AppKit. Fonts: `CoreTypeface` (Core bundle).

**Out of scope:** zoom, multi-select, layers panel, image fills for text, arbitrary colors (palette only), saving editor state between launches.

---

## Conventions (same as phases 1 and 2a)

- Repo `/Users/vasiliev/cleanshotvibed`; worktrees `/Users/vasiliev/miracle-shot-wt/task-N`, branches `task/N-slug`, merge `--no-ff` into `master`. Baseline: 161 tests green, tag `phase-2a-complete`.
- TDD, no emoji, no "ё", colors only via `BrandPalette`. Commit messages in English ending with a blank line and `Claude-Session: https://claude.ai/code/session_012TeusS6XfhDMHoM7fu1tzs`.
- Test helpers: `Tests/MiracleShotCoreTests/Helpers/TestImages.swift` (`solid`, `pixel`, `channel`, `assertClose`), `Tests/MiracleShotAppTests/Helpers/Fakes.swift`.
- Existing pieces to reuse: `BrandColor`/`BrandPalette`, `CoreTypeface.mono`, `BackgroundRenderer.render`, `BackgroundPreset`, `ImageCodec`, `ImageFit`, `BrandButton`, `BrandFont`, `QuickPreviewPanel.handlers[.edit]`, `CaptureCoordinator.applyBackground`.

## Waves

| Wave | Tasks | Notes |
|------|-------|-------|
| 1 | Task 1 (model, document, undo) | leaf types |
| 2 | Task 2 (geometry, handles, hit test), Task 3 (typeface families, text metrics, renderer) | disjoint files, both need Task 1 |
| 3 | Task 4 (EditorSession), Task 5 (coordinator `publish`, preview Edit hook) | Task 4 needs 2 and 3; Task 5 is UI-only |
| 4 | Task 6 (canvas view) | needs 3 and 4 |
| 5 | Task 7 (toolbar, window, shortcuts, export, drag) | needs 6 |
| 6 | Task 8 (wiring, build, manual checklist) | after everything |

---

### Task 1: Annotation model, Document, UndoStack

**Files:**
- Create: `Sources/MiracleShotCore/Editor/Annotation.swift`
- Create: `Sources/MiracleShotCore/Editor/Document.swift`
- Create: `Sources/MiracleShotCore/Editor/UndoStack.swift`
- Test: `Tests/MiracleShotCoreTests/AnnotationTests.swift`, `Tests/MiracleShotCoreTests/DocumentTests.swift`, `Tests/MiracleShotCoreTests/UndoStackTests.swift`

**Model (exact):**

```swift
import CoreGraphics
import Foundation

public enum FontFamily: String, Sendable, Equatable, CaseIterable {
    case text      // Onest
    case mono      // JetBrains Mono
    case display   // Geologica
}

/// Visual attributes shared by every annotation. Sizes are in source pixels.
public struct AnnotationStyle: Sendable, Equatable {
    public var strokeColor: BrandColor
    public var fillColor: BrandColor?
    public var lineWidth: CGFloat
    public var fontFamily: FontFamily
    public var fontSize: CGFloat

    public init(strokeColor: BrandColor = BrandPalette.lime, fillColor: BrandColor? = nil, lineWidth: CGFloat = 4,
                fontFamily: FontFamily = .text, fontSize: CGFloat = 28)

    /// Defaults scaled for a capture at `scaleFactor` (a 2x screenshot gets 2x strokes).
    public static func `default`(scaleFactor: CGFloat) -> AnnotationStyle
}

public enum BlurMode: String, Sendable, Equatable { case gaussian, pixelate }

public enum AnnotationShape: Sendable, Equatable {
    case arrow(from: CGPoint, to: CGPoint)
    case line(from: CGPoint, to: CGPoint)
    case rect(CGRect)
    case ellipse(CGRect)
    case freehand([CGPoint])
    case text(origin: CGPoint, string: String)
    /// Numbered badge; `number` is kept in reading order by `Document.normalizeSteps()`.
    case step(center: CGPoint, number: Int)
    case blur(CGRect, mode: BlurMode)
    case highlight(CGRect)
}

public struct Annotation: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var shape: AnnotationShape
    public var style: AnnotationStyle

    public init(id: UUID = UUID(), shape: AnnotationShape, style: AnnotationStyle)

    /// Axis-aligned bounds of the geometry alone (text and step bounds need metrics: see `AnnotationBounds` in Task 3).
    /// For `text` this returns a zero-size rect at the origin; for `step` a square of side `style.fontSize * 2` centered.
    public var geometryBounds: CGRect
    /// Same shape shifted by `delta`.
    public func moved(by delta: CGPoint) -> Annotation
}
```

`geometryBounds`: arrow/line -> rect spanning both points (`standardized`); rect/ellipse/blur/highlight -> the rect standardized; freehand -> bounds of all points (zero rect for empty); text -> `CGRect(origin: origin, size: .zero)`; step -> square as documented.

**Document:**

```swift
public struct Document: Sendable, Equatable {
    public let source: CGImage
    public let scaleFactor: CGFloat
    public var annotations: [Annotation]
    public var background: BackgroundPreset?
    /// In source pixels; nil means the full image.
    public var cropRect: CGRect?

    public init(source: CGImage, scaleFactor: CGFloat, annotations: [Annotation] = [], background: BackgroundPreset? = nil, cropRect: CGRect? = nil)

    public var sourceSize: CGSize   // pixels
    public var effectiveCrop: CGRect   // cropRect ?? full, intersected with the image bounds and integral

    public mutating func add(_ annotation: Annotation)            // appends, then normalizeSteps()
    public mutating func update(_ annotation: Annotation)         // replaces by id; no-op if absent
    public mutating func remove(id: UUID)                          // then normalizeSteps()
    public mutating func bringToFront(id: UUID)
    public func annotation(id: UUID) -> Annotation?
    /// Renumbers `step` annotations 1...n in array order.
    public mutating func normalizeSteps()
    /// The number the next step gets.
    public var nextStepNumber: Int
}
```

`Equatable` on `Document` compares `source` by identity (`===`), the rest structurally. Two documents made from the same `CGImage` are equal when annotations/background/crop match.

**UndoStack:**

```swift
public struct UndoStack<State: Equatable & Sendable>: Sendable {
    public private(set) var undoStates: [State]
    public private(set) var redoStates: [State]
    public let limit: Int
    public init(limit: Int = 100)
    public var canUndo: Bool
    public var canRedo: Bool
    /// Records `state` as the state to return to; clears redo. Drops the oldest entry past `limit`.
    public mutating func push(_ state: State)
    /// Returns the state to restore, moving `current` onto the redo stack. nil if nothing to undo.
    public mutating func undo(current: State) -> State?
    public mutating func redo(current: State) -> State?
}
```

**Tests (write first):**
- `AnnotationTests`: `geometryBounds` for each shape (a reversed arrow standardizes; empty freehand is `.zero`; step square), `moved(by:)` shifts every point, `AnnotationStyle.default(scaleFactor: 2)` doubles lineWidth and fontSize.
- `DocumentTests`: add/update/remove/bringToFront; `normalizeSteps` after removing the middle of three steps gives 1, 2; `nextStepNumber`; `effectiveCrop` clamps a rect that spills outside and rounds to integers; equality with the same source.
- `UndoStackTests`: push/undo/redo round trip; redo cleared by push; limit drops the oldest; undo on empty returns nil.

Commit: "Add the annotation model, Document and UndoStack".

---

### Task 2: Editor geometry, handles, hit testing, arrowheads

**Files:**
- Create: `Sources/MiracleShotCore/Editor/EditorGeometry.swift`
- Create: `Sources/MiracleShotCore/Editor/AnnotationHandles.swift`
- Create: `Sources/MiracleShotCore/Editor/AnnotationHitTest.swift`
- Create: `Sources/MiracleShotCore/Editor/ArrowGeometry.swift`
- Test: `Tests/MiracleShotCoreTests/EditorGeometryTests.swift`, `AnnotationHandlesTests.swift`, `AnnotationHitTestTests.swift`, `ArrowGeometryTests.swift`

**EditorGeometry** (view space is points, origin top-left, y down, like the flipped NSView the canvas uses):

```swift
public struct EditorGeometry: Sendable, Equatable {
    /// View points per image pixel.
    public let scale: CGFloat
    /// Where the image's top-left lands in the view.
    public let origin: CGPoint
    public let imageSize: CGSize

    /// Fits `imageSize` (pixels) into `viewSize` minus `padding` on every side, never larger than `maxScale`
    /// (pass `1 / scaleFactor` so a Retina capture shows at its natural on-screen size), centered.
    public static func fit(imageSize: CGSize, in viewSize: CGSize, padding: CGFloat, maxScale: CGFloat) -> EditorGeometry

    public func imagePoint(fromView p: CGPoint) -> CGPoint
    public func viewPoint(fromImage p: CGPoint) -> CGPoint
    public func imageRect(fromView r: CGRect) -> CGRect
    public func viewRect(fromImage r: CGRect) -> CGRect
    /// `points` in the view converted to image pixels (tolerances, handle radii).
    public func imageLength(fromView points: CGFloat) -> CGFloat
    /// Clamps an image point into the image bounds.
    public func clamped(_ p: CGPoint) -> CGPoint
}
```

**AnnotationHandles:**

```swift
public enum Handle: Sendable, Equatable, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left   // rect-like shapes
    case start, end                                                              // line, arrow
}

public enum AnnotationHandles {
    /// Handles the shape offers, with their image-space positions. Rect-like: 8; line/arrow: start and end;
    /// freehand, text, step, none.
    public static func handles(for annotation: Annotation) -> [(handle: Handle, point: CGPoint)]
    /// The handle within `tolerance` (image pixels) of `point`, closest first.
    public static func handle(at point: CGPoint, in annotation: Annotation, tolerance: CGFloat) -> Handle?
    /// The annotation with `handle` dragged to `point`. Rect-like shapes keep the opposite edge fixed and are
    /// standardized (dragging past the opposite edge flips, never produces a negative size). Line/arrow move that endpoint.
    public static func resized(_ annotation: Annotation, handle: Handle, to point: CGPoint) -> Annotation
}
```

**AnnotationHitTest:**

```swift
public enum AnnotationHitTest {
    /// Topmost annotation under `point`. `tolerance` in image pixels is added to half the stroke width.
    /// rect/ellipse/blur/highlight: inside the rect (ellipse: inside the ellipse) or within tolerance of the border;
    /// line/arrow/freehand: distance to any segment <= tolerance + lineWidth / 2;
    /// text: inside `textBounds` (provided by the caller through `bounds(for:)`);
    /// step: within radius `fontSize` of the center.
    public static func hit(_ point: CGPoint, in annotations: [Annotation], tolerance: CGFloat,
                           bounds: (Annotation) -> CGRect) -> Annotation?
    public static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat
}
```

The `bounds` closure exists so Core geometry stays free of font metrics; Task 3 provides `AnnotationBounds.bounds(of:)` and the session passes it.

**ArrowGeometry:**

```swift
public enum ArrowGeometry {
    /// Head length is `max(12, lineWidth * 4)`, half-angle 28 degrees. Returns the three points of the filled head
    /// (tip == `to`) and the point where the shaft should stop (inside the head) so the stroke does not poke out.
    public static func head(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> (tip: CGPoint, left: CGPoint, right: CGPoint, shaftEnd: CGPoint)
}
```

**Tests:** fit centers and respects `maxScale` and padding (a 4000x2000 image in 1000x800 with padding 24 gets scale 0.238, origin computed); round-trip view<->image; `imageLength`; handles positions for a rect and for an arrow; `handle(at:)` picks the nearest within tolerance and nil outside; `resized` keeps the opposite edge fixed and flips cleanly (drag `topLeft` past `bottomRight`); hit testing: topmost wins, ellipse excludes the corner outside the ellipse but inside its rect, segment distance formula (point beyond the segment end measures to the endpoint), step radius; arrow head geometry (tip equals `to`, left/right symmetric about the shaft, shaftEnd lies on the shaft).

Commit: "Add editor geometry, handles, hit testing and arrowheads".

---

### Task 3: Typeface families, text bounds, AnnotationRenderer

**Files:**
- Modify: `Sources/MiracleShotCore/Brand/CoreTypeface.swift` — add `public static func font(_ family: FontFamily, size: CGFloat, weight: CGFloat) -> CTFont?` (file names: `Onest-Variable.ttf`, `JetBrainsMono-Variable.ttf`, `Geologica-Variable.ttf`); `mono(size:weight:)` becomes a thin wrapper.
- Create: `Sources/MiracleShotCore/Editor/AnnotationBounds.swift` — `public enum AnnotationBounds { static func bounds(of annotation: Annotation) -> CGRect }`: geometry bounds for shapes; for `text` the CoreText line bounds (`CTLineGetBoundsWithOptions(.useOpticalBounds)`) placed at `origin` with the top-left at the origin (height = ascent + descent, multi-line strings split on `\n`, line height = ascent + descent + leading); for `step` the circle's square (radius `fontSize * 0.9`). Falls back to a rough `0.6 * fontSize` per character when the font is missing.
- Create: `Sources/MiracleShotCore/Editor/AnnotationRenderer.swift`
- Test: `Tests/MiracleShotCoreTests/AnnotationRendererTests.swift`, `AnnotationBoundsTests.swift`, extend `CoreSmokeTests` if useful.

**AnnotationRenderer (exact contract):**

```swift
public enum AnnotationRenderer {
    /// Crop -> annotations -> background. `nil` only if a context cannot be made.
    public static func render(_ document: Document) -> CGImage?
    /// Crop and annotations without the background; the canvas shows this one.
    public static func renderWithoutBackground(_ document: Document) -> CGImage?
    /// Draws one annotation into `ctx` whose current transform maps image pixels (origin top-left, y down) to the
    /// target. Used by the canvas for the in-progress shape and by `render`. `source` is needed for blur patches.
    public static func draw(_ annotation: Annotation, in ctx: CGContext, source: CGImage, sourceOffset: CGPoint)
}
```

Implementation notes:
- Context: sRGB premultipliedLast 8-bit of the crop size. Draw the crop of `source` first (`source.cropping(to: effectiveCrop)`), unflipped, in `CGRect(origin: .zero, size: crop.size)`.
- Vector drawing in a flipped context: `ctx.translateBy(x: 0, y: height); ctx.scaleBy(x: 1, y: -1)`, then translate by `-crop.origin` so annotation coordinates stay in full-image space. All shapes use `style.strokeColor` for the stroke, `fillColor` for fills (rect/ellipse only), round caps and joins, `lineWidth`.
- Arrow: stroke shaft from `from` to `shaftEnd`, fill the head triangle. Line: stroke. Rect: fill then stroke (stroke inset by half width so it stays inside the rect). Ellipse: same with `addEllipse`. Freehand: a path through the points with `addLine` (quadratic smoothing optional, not required).
- Highlight: `ctx.setBlendMode(.multiply)`, fill the rect with `strokeColor` at alpha 0.35 (no stroke).
- Text: draw with CoreText in the flipped context using `ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)` and `textPosition` at `(origin.x, origin.y + ascent)` for the first line, then line height steps; weight 600 for `.text`/`.display`, 500 for `.mono`; color `strokeColor`. Empty strings draw nothing.
- Step: filled circle radius `fontSize * 0.9` in `strokeColor`, 2 px ink outline, number centered in mono weight 700 at `fontSize` in `BrandPalette.ink` (measure the line to center it).
- Blur/pixelate: build `CIImage(cgImage: source)`, apply `CIGaussianBlur` (radius `max(6, 0.012 * min(source.width, source.height))`) or `CIPixellate` (scale `max(8, 0.02 * min(w, h))`, center at the rect origin), clamp with `CIAffineClamp` before blurring so edges do not fade to transparent, then `CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB]).createCGImage(filtered, from: ciRect)` where `ciRect` is the rect converted to CoreImage y-up coordinates (`y = source.height - rect.maxY`). Draw the patch **unflipped** at the rect converted to context coordinates (`y = height - (rect.maxY - crop.minY)`), clipped to the rect. Rects fully outside the crop are skipped.
- `render` then calls `BackgroundRenderer.render(annotated, preset: document.background, scale: document.scaleFactor)` when a background is set.

**Tests (pixel checks with tolerance, small images):**
- `testRectFillAndStroke`: 100x100 ink source, rect (20,20,40,40) fill lime stroke coral width 4 -> pixel (40,40) lime, (21,40) coral, (10,10) ink.
- `testCropMovesAnnotationsWithTheImage`: crop (50,50,50,50) and a rect at (60,60,20,20): output is 50x50 and pixel (20,20) is the fill color, (5,5) is the source color.
- `testArrowHeadFillsAtTheTip`: arrow (10,50)->(90,50) lime width 4 on ink: pixel (85,50) lime, (78,54) and (82,47) lime (inside the head; the head is 16 px long with half-angle 28 degrees, so its base spans y 42.5...57.5 at x 75.9), (50,58) ink.
- `testEllipseLeavesCornersUntouched`: ellipse (10,10,80,80) fill lime: (50,50) lime, (12,12) ink.
- `testHighlightMultiplies`: bone source, highlight lime rect: inside pixel darker than bone in the blue channel and greener; outside bone.
- `testBlurLowersVariance`: source with a sharp checkerboard (8 px squares) in a region; after `.blur(rect, .gaussian)` the variance of the region drops by at least 4x; pixels outside the rect unchanged.
- `testPixelateMakesFlatBlocks`: after `.blur(rect, .pixelate)` a block's pixels are equal to each other (within 2).
- `testTextDrawsUpright`: 200x100 ink source, text "IL" lime fontSize 40 at (20,10): lime pixels exist inside `AnnotationBounds.bounds(of:)`; there are lime pixels in the top third of the bounds AND the bottom third (a stroke of "I" spans the height), and no lime pixels above the bounds (proves the text is not drawn upside down below the origin). Skip with `XCTSkip` if `CoreTypeface.font` returns nil.
- `testStepBadge`: step at (50,50) number 3 fontSize 20 -> pixel (50,50) is not the badge color (the digit is ink), pixel (50 + 12, 50) is lime; pixel (50,50 + 25) ink (outside the circle).
- `testRenderAppliesBackground`: document with `BackgroundPreset` solid bone, paddingPercent 0 -> same size; paddingPercent 20 on 100x100 -> 148x148 with the 24-floor (reference 100 * 20 percent = 20 < 24 floor -> 24 px each side).
- `AnnotationBoundsTests`: text bounds grow with the string and with fontSize; two lines are taller than one; step bounds square.

Commit: "Add AnnotationRenderer with text, blur and background composition".

---

### Task 4: EditorSession (pure interaction state machine)

**Files:**
- Create: `Sources/MiracleShotCore/Editor/EditorSession.swift`
- Test: `Tests/MiracleShotCoreTests/EditorSessionTests.swift`

**Contract:**

```swift
public enum Tool: String, Sendable, Equatable, CaseIterable {
    case select, arrow, line, rect, ellipse, freehand, text, step, blur, highlight, crop
}

public enum EditorEvent: Sendable, Equatable {
    case mouseDown(CGPoint, shift: Bool)          // image pixels
    case mouseDragged(CGPoint)
    case mouseUp(CGPoint)
    case selectTool(Tool)
    case setStyle(AnnotationStyle)                 // applies to the selection (if any) and becomes the current style
    case setBlurMode(BlurMode)
    case textCommitted(id: UUID, string: String)   // empty string removes the annotation
    case textCancelled(id: UUID)
    case deleteSelection
    case escape                                    // cancels an in-progress drag or crop, else clears selection
    case undo, redo
    case setBackground(BackgroundPreset?)
    case cropConfirm, cropCancel
}

/// What the UI must do after an event; the session never touches AppKit.
public enum EditorEffect: Sendable, Equatable {
    case beginTextEditing(id: UUID)   // show the text field at the annotation's origin
    case endTextEditing
}

public enum Transient: Sendable, Equatable {
    case drawing(Annotation)
    case moving(id: UUID, last: CGPoint)
    case resizing(id: UUID, handle: Handle)
    case cropping(anchor: CGPoint, rect: CGRect)
}

public struct EditorSession: Sendable, Equatable {
    public private(set) var document: Document
    public private(set) var undo: UndoStack<Document>
    public var tool: Tool
    public var style: AnnotationStyle
    public var blurMode: BlurMode
    public private(set) var selectedID: UUID?
    public private(set) var transient: Transient?
    /// The crop rect being edited while `tool == .crop` (starts as the current crop or the full image).
    public private(set) var pendingCrop: CGRect?
    /// Hit tolerance and handle radius in image pixels; the canvas updates them when the zoom changes.
    public var hitTolerance: CGFloat
    public var handleTolerance: CGFloat
    /// Text metrics come from Core too (`AnnotationBounds.bounds(of:)`), injected so tests can use a fixed box.
    public var bounds: @Sendable (Annotation) -> CGRect

    public init(document: Document, style: AnnotationStyle, bounds: @escaping @Sendable (Annotation) -> CGRect = AnnotationBounds.bounds(of:))

    @discardableResult
    public mutating func handle(_ event: EditorEvent) -> EditorEffect?
    public var canUndo: Bool
    public var canRedo: Bool
    public var selected: Annotation?
    /// The document plus the in-progress annotation, for the canvas to draw.
    public var displayAnnotations: [Annotation]
}
```

**Behaviour table (each row is a test):**
- Shape tools (arrow, line, rect, ellipse, blur, highlight): mouseDown starts `.drawing` with a degenerate shape at the point; drags update the far point/rect (rects standardized); mouseUp commits if the shape is larger than 3 px in both dimensions for rects / longer than 3 px for lines, else discards; commit = `undo.push(documentBefore)`, `document.add`, select the new annotation, keep the tool.
- Freehand: points appended on drag; commit if at least 2 points.
- Text: mouseDown creates `.text(origin, "")`, pushes undo, adds it, selects it and returns `.beginTextEditing(id)`; `textCommitted` with a non-empty string updates it; empty string or `textCancelled` removes it and pops the undo entry (`undo.undo` back to the previous document without leaving a redo entry: implement as restoring the pushed state and clearing redo). Returns `.endTextEditing`.
- Step: mouseDown adds `.step(center, nextStepNumber)` immediately (push undo), selects it; no drag.
- Select tool: mouseDown on a handle of the selection -> `.resizing`; on an annotation (hit test, topmost) -> select it and start `.moving`; on empty -> clear selection. Drag applies `resized`/`moved(by:)` to the document live (the undo snapshot is pushed once, at mouseDown, only if a drag actually happens: push lazily on the first drag). mouseUp ends the transient. With `shift` on mouseDown while resizing a rect: keep the aspect ratio (optional; if implemented, test it, otherwise document that shift is ignored).
- Crop tool: selecting the tool sets `pendingCrop` to the current crop or the full image; mouseDown starts `.cropping(anchor: p, rect: zero)`; drag sets `rect` to the standardized rect from anchor to point, clamped to the image; mouseUp keeps `pendingCrop = rect` if larger than 8x8 px; `cropConfirm` pushes undo, sets `document.cropRect` (nil if it equals the full image) and switches to `.select`; `cropCancel` or `escape` discards `pendingCrop` and switches to `.select`.
- `deleteSelection`: pushes undo, removes, clears selection; no-op without selection.
- `setStyle`: becomes `style`; if a selection exists, pushes undo and updates its style.
- `setBackground`: pushes undo and sets `document.background`.
- `undo`/`redo`: swap documents through the stack, clear selection and transient.
- `escape`: cancels a `.drawing`/`.cropping` transient without committing; otherwise clears selection.
- `selectTool`: clears selection when leaving `.select`? No: keep the selection, but a shape tool's mouseDown always starts drawing (never moves). Switching to `.crop` initializes `pendingCrop`; switching away without confirm discards it.

**Tests:** one per row above plus: undo after drawing restores the previous document and clears selection; redo re-adds; text commit/cancel undo bookkeeping; move pushes exactly one undo entry for a multi-drag; step numbering after deleting step 1 of 2 renumbers the remaining to 1; `displayAnnotations` includes the in-progress shape.

Commit: "Add EditorSession: tools, selection, drag, crop, undo".

---

### Task 5: `CaptureCoordinator.publish`, preview Edit hook

**Files:**
- Modify: `Sources/MiracleShotUI/Coordinator/CaptureCoordinator.swift`
- Modify: `Tests/MiracleShotAppTests/CaptureCoordinatorTests.swift`

```swift
    /// Pushes an image derived from `source` (a background applied, an edit finished) through the normal finish
    /// path: clipboard, file, history, preview. Refused only while a capture is in flight.
    public func publish(_ image: CGImage, derivedFrom source: Capture) {
        guard state.canStartCapture else { return }
        let size = CGSize(width: CGFloat(image.width) / source.scaleFactor, height: CGFloat(image.height) / source.scaleFactor)
        let shot = Capture(image: image, sourceAppName: source.sourceAppName, sourceWindowTitle: source.sourceWindowTitle,
                           bounds: CGRect(origin: source.bounds.origin, size: size), scaleFactor: source.scaleFactor)
        finish(shot)
    }
```

`applyBackground` becomes: render, then `publish(image, derivedFrom: source)` (its tests keep passing unchanged). New tests: `testPublishRunsTheFinishPath` (copy, save, preview; history +1; lastCapture size), `testPublishIsRefusedWhileSelecting`.

Commit: "Generalize applyBackground into CaptureCoordinator.publish".

---

### Task 6: EditorCanvasView

**Files:**
- Create: `Sources/MiracleShotUI/Editor/EditorCanvasView.swift`
- Create: `Sources/MiracleShotUI/Editor/EditorTextField.swift` (a borderless `NSTextField` subclass: Onest, lime text, ink2 background, returns on Enter, cancels on Esc, grows with content)
- Test: none automated beyond the suite staying green (the view is AppKit); keep every decision in `EditorGeometry`/`EditorSession`.

**Behaviour:**
- `final class EditorCanvasView: NSView` with `isFlipped = true` (so view coordinates are top-left, matching `EditorGeometry`), ink background (`BrandPalette.ink`), owns `var session: EditorSession` and `var onChange: (() -> Void)?` (toolbar refreshes undo/redo state), `var geometry: EditorGeometry` recomputed in `layout()` with padding 24 and `maxScale = 1 / document.scaleFactor`; sets `session.hitTolerance = geometry.imageLength(fromView: 6)` and `handleTolerance = imageLength(fromView: 8)`.
- Rendering: a cached `CGImage` from `AnnotationRenderer.renderWithoutBackground(session.document)` refreshed whenever the document changes (compare a document "version" counter incremented by every session event that mutates; simplest: re-render after every handled event, it is one call). `draw(_:)`: fill ink, draw the cached image in `geometry.viewRect(fromImage: crop)` (the canvas shows the cropped result, so when a crop is active the view shows only the crop; while the crop tool is active show the full image dimmed with the pending crop rect bright and a lime 1 pt outline with size label in mono, like the selection overlay). Then draw the in-progress annotation (`session.transient == .drawing`) by calling `AnnotationRenderer.draw` in a context transformed with the geometry (concatenate `translate(origin) scale(scale)` and subtract the crop origin). Selection: lime 1 pt dashed bounds around `session.selected` (bounds via `AnnotationBounds`) plus 8 pt square handles (ink2 fill, lime border) at `AnnotationHandles.handles(for:)`.
- Mouse: `mouseDown/Dragged/Up` convert with `geometry.imagePoint(fromView:)`, clamp, forward to the session; on `.beginTextEditing(id)` place an `EditorTextField` at `geometry.viewPoint(fromImage: origin)` sized to the font (`BrandFont.text(size: fontSize * scale, weight: 600)`), make it first responder; on commit send `.textCommitted`, on cancel `.textCancelled`; remove the field on `.endTextEditing`. Double-click on an existing text annotation re-opens editing (`session` gets an event `.editText(id)` — add it to Task 4's enum now if missing: returns `.beginTextEditing(id)` and pushes undo on commit only if the string changed).
- Cursor: crosshair for drawing tools, arrow for select, `.openHand` while moving.
- Keyboard (`keyDown`): Delete/Backspace -> `.deleteSelection`; Esc -> `.escape`; single-letter tool shortcuts are handled by the window (Task 7), not here.
- After every event: re-render cache if the document changed, `needsDisplay = true`, `onChange?()`.

Commit: "Add the editor canvas view".

---

### Task 7: Toolbar, window, shortcuts, export, drag and drop

**Files:**
- Create: `Sources/MiracleShotUI/Editor/EditorToolbar.swift`
- Create: `Sources/MiracleShotUI/Editor/EditorWindowController.swift`
- Modify: `Sources/MiracleShotUI/Support/BrandButton.swift` — add `init(symbol: String, accessibilityLabel: String, target:action:)` for icon buttons (SF Symbols via `NSImage(systemSymbolName:accessibilityDescription:)`, template image tinted bone, lime when `isSelectedTool`), and a `var isHighlighted` style for the active tool (lime border).
- Test: `Tests/MiracleShotAppTests/EditorShortcutsTests.swift` for the pure key -> event table.

**Toolbar (ink2 bar, 44 pt, left to right):**
- Undo, Redo (arrow.uturn.backward / forward), separator.
- Tools with SF Symbols: select `cursorarrow`, arrow `arrow.up.right`, line `line.diagonal`, rect `rectangle`, ellipse `circle`, freehand `pencil`, text `textformat`, step `1.circle`, blur `drop.halffull`, highlight `highlighter`, crop `crop`. Active tool: lime.
- Colors: swatches (14 pt circles) lime, coral, bone, boneDim, ink; the current one has a bone ring.
- Line width: three dots S/M/L (2, 4, 8 px times scaleFactor); font size follows (20, 28, 40 px times scaleFactor). Blur mode toggle (gaussian/pixelate) shown only when the blur tool is active.
- Right side: `Background` popup (presets, `None` first), `Copy`, `Done`, and a drag handle (thumbnail 44x28 of the current render; dragging it starts an `NSDraggingSession` with a PNG written to a temp file, `.fileURL` and `.png` types). Crop tool shows `Apply` / `Cancel` in place of Copy/Done while active.
- `EditorShortcuts.event(forKey: String, modifiers: NSEvent.ModifierFlags) -> EditorEvent?` pure table: v/a/l/r/o/p/t/n/b/h/c select tools, cmd+z undo, shift+cmd+z redo, delete/backspace deleteSelection, esc escape, return with crop active -> cropConfirm. Tested.

**Window:** `EditorWindowController.open(capture: Capture, presets: [BackgroundPreset], onDone: @escaping (CGImage) -> Void)`: creates (or reuses) an `NSWindow` titled "Miracle Shot Editor" (`.titled, .closable, .resizable, .miniaturizable`), ink background, min 720x520, initial size = image natural size + toolbar + 48 padding, capped at 85 percent of the screen; content = vertical stack toolbar + canvas; `NSApp.activate`. Cmd+C -> copy (`ClipboardService`-like: PNG + TIFF of `AnnotationRenderer.render`), Cmd+W / close button -> if the document has annotations, crop or background, `NSAlert` "Discard changes?" (Discard / Cancel); `Done` -> `onDone(AnnotationRenderer.render(document))` then close without asking. `performKeyEquivalent` routes Cmd shortcuts, `keyDown` routes letters through `EditorShortcuts` when the text field is not editing.

Commit: "Add the editor window, toolbar, shortcuts and export".

---

### Task 8: Wiring, build, manual checklist

**Files:**
- Modify: `Sources/MiracleShotUI/App/AppDelegate.swift`: create `EditorWindowController` (needs `ClipboardService` for Copy); `preview.handlers[.edit] = { [weak self] capture, _ in self?.editor.open(capture: capture, presets: presets, onDone: { image in self?.coordinator.publish(image, derivedFrom: capture) }) }`; History submenu items get an `Edit` alternative? Not in this phase.
- Modify: `docs/plans/2026-09-14-miracle-shot-design.md` §3.1/§3.2 to match (`EditorSession`, `publish`).

**Manual checklist (controller with the user):**
1. Shift+Cmd+1 -> area -> preview shows `Edit`, `Background`, `Reveal`. Click `Edit`: window opens with the shot at natural size, toolbar in brand style.
2. Arrow, rect, ellipse, line, pencil: draw, select, move, resize by handles, change color and width of the selection.
3. Text: click, type, Enter; Esc cancels; double-click edits again.
4. Steps: three clicks give 1, 2, 3; deleting 2 renumbers to 1, 2.
5. Blur and pixelate on a text area; highlight on a line of text.
6. Crop: drag, Apply; annotations stay attached to the image; Undo restores.
7. Cmd+Z / Shift+Cmd+Z through ten operations.
8. Background popup: Lab Brand on the annotated image.
9. Done: preview appears with the result, file saved, Cmd+V pastes it; Copy copies without saving; drag handle drops a PNG into Finder.
10. Cmd+W with changes asks; without changes closes.

Then `git tag phase-2b-complete`.
