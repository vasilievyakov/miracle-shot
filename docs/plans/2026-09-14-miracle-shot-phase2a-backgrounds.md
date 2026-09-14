# Miracle Shot — Phase 2a: Backgrounds, Icon, Brand Fonts

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task (implementers on Sonnet, waves per the table below).

**Goal:** A "Background" button in the quick preview that re-renders the screenshot on one of four Agentic Lab gradient presets (Lab Dark, Lime, Bone, Coral) and pushes the result through the normal copy/save/preview path; plus the app icon and brand fonts that the design marks as the first tasks of phase 2.

**Architecture:** Presets are `Codable` JSON in `Sources/MiracleShotCore/Resources/presets` (user overrides in `~/Library/Application Support/Miracle Shot/presets`). `BackgroundRenderer` (Core, CoreGraphics only) composes the source image over the fill with padding, corner radius and shadow; it is the single render path that the annotation editor will reuse later. The preview panel shows an `NSMenu` of presets; the coordinator renders and calls the existing `finish` path, so clipboard, disk, history and the preview all behave exactly as after a capture. The icon is generated at build time by a Swift script; fonts are variable TTFs in the UI resource bundle registered with CoreText at first use.

**Tech Stack:** Swift 6, SwiftPM, XCTest, CoreGraphics, CoreText, AppKit. Package.swift is frozen: resource directories `Resources/presets` and `Resources/fonts` are already declared.

**Scope explicitly out:** image fills for presets, user-editable presets UI, applying a background automatically (the user chose button-only), the annotation editor (phase 2b, separate plan).

---

## Conventions (same as phase 1)

- Repo: `/Users/vasiliev/cleanshotvibed`. Worktrees: `/Users/vasiliev/miracle-shot-wt/task-N` on branch `task/N-slug` from `master`; merge with `git merge --no-ff`.
- Tests: `swift test` (whole suite, must stay green: 115 tests before this plan). Single file: `swift test --filter BackgroundPresetTests`.
- TDD: write the failing test, run it, see it fail for the right reason, implement, run, commit.
- No emoji anywhere. No "ё". Colors only via `BrandPalette` tokens in Swift; preset JSON may contain hex strings but every value must be a palette token (a test enforces it).
- Commit messages in English; each commit ends with a blank line and `Claude-Session: https://claude.ai/code/session_012TeusS6XfhDMHoM7fu1tzs`.
- Existing helpers to reuse: `Tests/MiracleShotCoreTests/Helpers/TestImages.swift` (`solid`, `pixel`, `assertClose`, `context`), `Tests/MiracleShotAppTests/Helpers/Fakes.swift` (`CallLog`, `makeCapture`, all fakes), `CoreResources.bundle`, `UIResources.bundle`, `ImageCodec`.

## Waves

| Wave | Tasks | Notes |
|------|-------|-------|
| 1 | Task 1 (preset model + JSON + library), Task 3 (icon), Task 4 (fonts) | disjoint files |
| 2 | Task 2 (renderer) | needs `BackgroundPreset` from Task 1 |
| 3 | Task 5 (preview menu), Task 6 (coordinator) | both need Task 2; disjoint files |
| 4 | Task 7 (wiring, build, manual check) | after everything is merged |

---

### Task 1: BackgroundPreset model, built-in presets, library

**Files:**
- Modify: `Sources/MiracleShotCore/Brand/BrandPalette.swift` (add `Codable` to `BrandColor`, add `BrandPalette.all`)
- Create: `Sources/MiracleShotCore/Background/BackgroundPreset.swift`
- Create: `Sources/MiracleShotCore/Background/BackgroundPresetLibrary.swift`
- Create: `Sources/MiracleShotCore/Resources/presets/01-lab-dark.json`, `02-lime.json`, `03-bone.json`, `04-coral.json`
- Test: `Tests/MiracleShotCoreTests/BackgroundPresetTests.swift`

**Step 1: Write the failing tests**

```swift
import Foundation
import XCTest
@testable import MiracleShotCore

final class BackgroundPresetTests: XCTestCase {
    private func sample() -> BackgroundPreset {
        BackgroundPreset(
            id: "sample", name: "Sample",
            fill: .linearGradient(stops: [GradientStop(color: BrandPalette.lime, location: 0),
                                          GradientStop(color: BrandPalette.limeDim, location: 1)], angle: 135),
            padding: 64, cornerRadius: 12,
            shadow: BackgroundShadow(blur: 40, offsetY: 16, opacity: 0.5))
    }

    func testBrandColorEncodesAsHexString() throws {
        let data = try JSONEncoder().encode(BrandPalette.lime)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"#d4ff3f\"")
        XCTAssertEqual(try JSONDecoder().decode(BrandColor.self, from: data), BrandPalette.lime)
    }

    func testBrandColorRejectsInvalidHex() {
        XCTAssertThrowsError(try JSONDecoder().decode(BrandColor.self, from: Data("\"#zz\"".utf8)))
    }

    func testPresetRoundTripsThroughJSON() throws {
        let preset = sample()
        let data = try JSONEncoder().encode(preset)
        XCTAssertEqual(try JSONDecoder().decode(BackgroundPreset.self, from: data), preset)
    }

    func testSolidFillDecodesFromReadableJSON() throws {
        let json = """
        {"id":"x","name":"X","fill":{"solid":{"color":"#0b0b0c"}},"padding":10,"cornerRadius":0}
        """
        let preset = try JSONDecoder().decode(BackgroundPreset.self, from: Data(json.utf8))
        XCTAssertEqual(preset.fill, .solid(color: BrandPalette.ink))
        XCTAssertNil(preset.shadow)
    }

    func testBuiltInPresetsLoadInOrder() {
        let presets = BackgroundPresetLibrary.builtIn()
        XCTAssertEqual(presets.map(\.id), ["lab-dark", "lime", "bone", "coral"])
        XCTAssertEqual(presets.map(\.name), ["Lab Dark", "Lime", "Bone", "Coral"])
        for preset in presets {
            XCTAssertGreaterThan(preset.padding, 0, preset.id)
            XCTAssertNotNil(preset.shadow, preset.id)
        }
    }

    func testBuiltInPresetsUseOnlyPaletteColors() {
        for preset in BackgroundPresetLibrary.builtIn() {
            for color in preset.fill.colors {
                XCTAssertTrue(BrandPalette.all.contains(color), "\(preset.id) uses \(color.hex), not a palette token")
            }
        }
    }

    func testLoadAppendsUserPresetsAndSkipsBrokenFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ms-presets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try JSONEncoder().encode(sample()).write(to: dir.appendingPathComponent("sample.json"))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("broken.json"))

        let presets = BackgroundPresetLibrary.load(userDirectory: dir)
        XCTAssertEqual(presets.count, BackgroundPresetLibrary.builtIn().count + 1)
        XCTAssertEqual(presets.last?.id, "sample")
    }

    func testLoadWithMissingUserDirectoryReturnsBuiltIns() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("ms-missing-\(UUID().uuidString)")
        XCTAssertEqual(BackgroundPresetLibrary.load(userDirectory: missing), BackgroundPresetLibrary.builtIn())
    }
}
```

**Step 2: Run to verify failure**

Run: `swift test --filter BackgroundPresetTests`
Expected: compile errors (`BackgroundPreset`, `GradientStop`, `BackgroundShadow`, `BackgroundPresetLibrary`, `BrandPalette.all` unknown).

**Step 3: Implement**

`Sources/MiracleShotCore/Brand/BrandPalette.swift` — add after `BrandColor`:

```swift
/// Encoded as a "#rrggbb" string so preset JSON stays readable.
extension BrandColor: Codable {
    public init(from decoder: Decoder) throws {
        let hex = try decoder.singleValueContainer().decode(String.self)
        guard let color = BrandColor(hex: hex) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "Not a #rrggbb color: \(hex)")
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
```

and inside `BrandPalette`:

```swift
    /// Every token, for tests that enforce "palette only".
    public static let all: [BrandColor] = [ink, ink2, ink3, bone, boneDim, boneFaint, lime, limeDim, coral, line]
```

`Sources/MiracleShotCore/Background/BackgroundPreset.swift`:

```swift
import Foundation

/// One color stop of a gradient; `location` is 0...1 along the gradient line.
public struct GradientStop: Codable, Sendable, Equatable {
    public var color: BrandColor
    public var location: Double

    public init(color: BrandColor, location: Double) {
        self.color = color
        self.location = location
    }
}

/// Drop shadow under the screenshot. All values in points; `offsetY` positive moves the shadow down on screen.
public struct BackgroundShadow: Codable, Sendable, Equatable {
    public var blur: Double
    public var offsetY: Double
    /// Black at this opacity, 0...1.
    public var opacity: Double

    public init(blur: Double, offsetY: Double, opacity: Double) {
        self.blur = blur
        self.offsetY = offsetY
        self.opacity = opacity
    }
}

/// A backdrop the screenshot is placed on. JSON files in `Resources/presets` (built-in) and the user's
/// Application Support `presets` folder. Synthesized `Codable`: the fill reads as
/// `{"solid":{"color":"#..."}}` or `{"linearGradient":{"stops":[...],"angle":135}}`.
public struct BackgroundPreset: Codable, Sendable, Equatable, Identifiable {
    public enum Fill: Codable, Sendable, Equatable {
        case solid(color: BrandColor)
        /// `angle` in degrees, CSS convention: 0 runs bottom to top, 90 left to right, 180 top to bottom.
        case linearGradient(stops: [GradientStop], angle: Double)

        public var colors: [BrandColor] {
            switch self {
            case .solid(let color): return [color]
            case .linearGradient(let stops, _): return stops.map(\.color)
            }
        }
    }

    public var id: String
    public var name: String
    public var fill: Fill
    /// Space around the screenshot, in points.
    public var padding: Double
    /// Radius applied to the screenshot's corners, in points.
    public var cornerRadius: Double
    public var shadow: BackgroundShadow?

    public init(id: String, name: String, fill: Fill, padding: Double, cornerRadius: Double, shadow: BackgroundShadow?) {
        self.id = id
        self.name = name
        self.fill = fill
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }
}
```

`Sources/MiracleShotCore/Background/BackgroundPresetLibrary.swift`:

```swift
import Foundation
import os

public enum BackgroundPresetLibrary {
    private static let log = Logger(subsystem: "agency.blackbloom.miracleshot", category: "presets")

    /// Built-in presets from the Core resource bundle, in file-name order (`01-…`, `02-…`).
    public static func builtIn() -> [BackgroundPreset] {
        guard let dir = CoreResources.bundle.url(forResource: "presets", withExtension: nil) else {
            log.error("Built-in presets folder is missing from the resource bundle")
            return []
        }
        return presets(in: dir)
    }

    /// Built-in presets followed by the user's own `*.json` files. A missing folder is normal; a file that does not
    /// decode is skipped and logged so one typo cannot hide the built-ins.
    public static func load(userDirectory: URL) -> [BackgroundPreset] {
        builtIn() + presets(in: userDirectory)
    }

    private static func presets(in directory: URL) -> [BackgroundPreset] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                do {
                    return try decoder.decode(BackgroundPreset.self, from: Data(contentsOf: url))
                } catch {
                    log.error("Skipping preset \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
    }
}
```

Preset files (values are palette tokens: ink `#0b0b0c`, ink2 `#141416`, ink3 `#1c1c1f`, bone `#f3f0e8`, boneDim `#b8b4a8`, lime `#d4ff3f`, limeDim `#9bbf2a`, coral `#ff5a36`):

`01-lab-dark.json`
```json
{
  "id": "lab-dark",
  "name": "Lab Dark",
  "fill": { "linearGradient": { "angle": 160, "stops": [
    { "color": "#1c1c1f", "location": 0 },
    { "color": "#0b0b0c", "location": 1 }
  ] } },
  "padding": 64,
  "cornerRadius": 12,
  "shadow": { "blur": 40, "offsetY": 16, "opacity": 0.6 }
}
```

`02-lime.json`
```json
{
  "id": "lime",
  "name": "Lime",
  "fill": { "linearGradient": { "angle": 135, "stops": [
    { "color": "#d4ff3f", "location": 0 },
    { "color": "#9bbf2a", "location": 1 }
  ] } },
  "padding": 64,
  "cornerRadius": 12,
  "shadow": { "blur": 40, "offsetY": 16, "opacity": 0.35 }
}
```

`03-bone.json`
```json
{
  "id": "bone",
  "name": "Bone",
  "fill": { "linearGradient": { "angle": 135, "stops": [
    { "color": "#f3f0e8", "location": 0 },
    { "color": "#b8b4a8", "location": 1 }
  ] } },
  "padding": 64,
  "cornerRadius": 12,
  "shadow": { "blur": 40, "offsetY": 16, "opacity": 0.25 }
}
```

`04-coral.json`
```json
{
  "id": "coral",
  "name": "Coral",
  "fill": { "linearGradient": { "angle": 135, "stops": [
    { "color": "#ff5a36", "location": 0 },
    { "color": "#ff5a36", "location": 0.45 },
    { "color": "#141416", "location": 1 }
  ] } },
  "padding": 64,
  "cornerRadius": 12,
  "shadow": { "blur": 40, "offsetY": 16, "opacity": 0.5 }
}
```

**Step 4: Run tests**

Run: `swift test`
Expected: all green, 115 + 8 new.

**Step 5: Commit**

```bash
git add Sources/MiracleShotCore/Brand/BrandPalette.swift Sources/MiracleShotCore/Background Sources/MiracleShotCore/Resources/presets Tests/MiracleShotCoreTests/BackgroundPresetTests.swift
git commit -m "Add background presets: model, built-in JSON, library"
```

---

### Task 2: BackgroundRenderer

**Files:**
- Create: `Sources/MiracleShotCore/Background/BackgroundRenderer.swift`
- Test: `Tests/MiracleShotCoreTests/BackgroundRendererTests.swift`

**Step 1: Write the failing tests**

```swift
import CoreGraphics
import XCTest
@testable import MiracleShotCore

final class BackgroundRendererTests: XCTestCase {
    private let red = TestImages.RGBA(r: 255, g: 0, b: 0, a: 255)
    private let lime = TestImages.RGBA(r: 0xd4, g: 0xff, b: 0x3f, a: 255)
    private let bone = TestImages.RGBA(r: 0xf3, g: 0xf0, b: 0xe8, a: 255)

    private func preset(fill: BackgroundPreset.Fill, padding: Double = 10, radius: Double = 0,
                        shadow: BackgroundShadow? = nil) -> BackgroundPreset {
        BackgroundPreset(id: "t", name: "T", fill: fill, padding: padding, cornerRadius: radius, shadow: shadow)
    }

    private func source(_ w: Int = 20, _ h: Int = 10) -> CGImage {
        TestImages.solid(width: w, height: h, r: 1, g: 0, b: 0)
    }

    func testSolidFillPadsAndKeepsSource() throws {
        let out = try XCTUnwrap(BackgroundRenderer.render(source(), preset: preset(fill: .solid(color: BrandPalette.lime)), scale: 1))
        XCTAssertEqual(out.width, 40)
        XCTAssertEqual(out.height, 30)
        TestImages.assertClose(TestImages.pixel(out, x: 2, y: 2), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 20, y: 15), red)
        TestImages.assertClose(TestImages.pixel(out, x: 10, y: 10), red)   // top-left of the image area, no rounding
        TestImages.assertClose(TestImages.pixel(out, x: 29, y: 19), red)   // bottom-right of the image area
    }

    func testCornerRadiusClipsSourceCorners() throws {
        let out = try XCTUnwrap(BackgroundRenderer.render(source(), preset: preset(fill: .solid(color: BrandPalette.lime), radius: 6), scale: 1))
        TestImages.assertClose(TestImages.pixel(out, x: 10, y: 10), lime)  // corner is cut away
        TestImages.assertClose(TestImages.pixel(out, x: 20, y: 15), red)   // center intact
        TestImages.assertClose(TestImages.pixel(out, x: 20, y: 10), red)   // top edge midpoint intact
    }

    func testScaleMultipliesPointValues() throws {
        let out = try XCTUnwrap(BackgroundRenderer.render(source(), preset: preset(fill: .solid(color: BrandPalette.ink)), scale: 2))
        XCTAssertEqual(out.width, 20 + 40)
        XCTAssertEqual(out.height, 10 + 40)
        TestImages.assertClose(TestImages.pixel(out, x: 20, y: 20), red)
    }

    func testGradientRunsLeftToRightAt90Degrees() throws {
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.ink, location: 0),
                                                                GradientStop(color: BrandPalette.bone, location: 1)], angle: 90)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: preset(fill: fill, padding: 20), scale: 1))
        XCTAssertEqual(out.width, 42)
        let left = TestImages.pixel(out, x: 1, y: 2).r
        let middle = TestImages.pixel(out, x: 21, y: 2).r
        let right = TestImages.pixel(out, x: 40, y: 2).r
        XCTAssertLessThan(left, middle)
        XCTAssertLessThan(middle, right)
        // Same column, different row: unchanged (gradient is horizontal).
        XCTAssertEqual(Int(TestImages.pixel(out, x: 1, y: 39).r), Int(left), accuracy: 2)
    }

    func testGradientRunsBottomToTopAtZeroDegrees() throws {
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.ink, location: 0),
                                                                GradientStop(color: BrandPalette.bone, location: 1)], angle: 0)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: preset(fill: fill, padding: 20), scale: 1))
        let bottom = TestImages.pixel(out, x: 2, y: 40).r   // y counts from the top
        let top = TestImages.pixel(out, x: 2, y: 1).r
        XCTAssertLessThan(bottom, top)
    }

    func testShadowDarkensBelowTheImage() throws {
        let shadow = BackgroundShadow(blur: 4, offsetY: 6, opacity: 1)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(10, 10), preset: preset(fill: .solid(color: BrandPalette.bone), padding: 20, shadow: shadow), scale: 1))
        let below = TestImages.pixel(out, x: 25, y: 32)   // 2 px under the image's bottom edge (image spans y 20..<30)
        let above = TestImages.pixel(out, x: 25, y: 12)   // 8 px above the top edge, outside the shadow
        XCTAssertLessThan(below.r, bone.r - 20)
        TestImages.assertClose(above, bone, tolerance: 3)
        TestImages.assertClose(TestImages.pixel(out, x: 2, y: 2), bone, tolerance: 3)
    }

    func testSwatchHasRequestedSizeAndFill() throws {
        let out = try XCTUnwrap(BackgroundRenderer.swatch(preset(fill: .solid(color: BrandPalette.lime)), size: 16))
        XCTAssertEqual(out.width, 16)
        XCTAssertEqual(out.height, 16)
        TestImages.assertClose(TestImages.pixel(out, x: 8, y: 8), lime)
        XCTAssertEqual(TestImages.pixel(out, x: 0, y: 0).a, 0)   // rounded corner is transparent
    }
}
```

**Step 2: Run to verify failure**

Run: `swift test --filter BackgroundRendererTests`
Expected: compile error, `BackgroundRenderer` unknown.

**Step 3: Implement**

`Sources/MiracleShotCore/Background/BackgroundRenderer.swift`:

```swift
import CoreGraphics
import Foundation

/// Composes a screenshot over a `BackgroundPreset`. Pure CoreGraphics so the same path serves the preview, the
/// clipboard and the future editor. Output is sRGB, premultiplied RGBA8.
public enum BackgroundRenderer {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// `scale` converts the preset's point values to pixels: pass the capture's `scaleFactor` so a 2x screenshot
    /// gets 2x padding and keeps its own pixel density.
    public static func render(_ source: CGImage, preset: BackgroundPreset, scale: CGFloat) -> CGImage? {
        let padding = CGFloat(preset.padding) * scale
        let width = Int((CGFloat(source.width) + padding * 2).rounded())
        let height = Int((CGFloat(source.height) + padding * 2).rounded())
        guard let ctx = makeContext(width: width, height: height) else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        draw(preset.fill, in: canvas, ctx: ctx)

        let imageRect = CGRect(x: padding, y: padding, width: CGFloat(source.width), height: CGFloat(source.height))
        let radius = min(CGFloat(preset.cornerRadius) * scale, imageRect.width / 2, imageRect.height / 2)
        let path = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        if let shadow = preset.shadow {
            // CG is y-up: a positive on-screen offset is a negative y here.
            ctx.setShadow(offset: CGSize(width: 0, height: -CGFloat(shadow.offsetY) * scale),
                          blur: CGFloat(shadow.blur) * scale,
                          color: CGColor(colorSpace: sRGB, components: [0, 0, 0, CGFloat(shadow.opacity)]))
        }
        // The transparency layer lets the shadow follow the clipped image's own alpha (rounded corners, transparent
        // window corners) instead of an opaque rectangle drawn underneath it.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(source, in: imageRect)
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// A rounded tile of the fill alone, for menus and pickers.
    public static func swatch(_ preset: BackgroundPreset, size: Int) -> CGImage? {
        guard let ctx = makeContext(width: size, height: size) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let radius = CGFloat(size) * 0.25
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        draw(preset.fill, in: rect, ctx: ctx)
        return ctx.makeImage()
    }

    // MARK: - Private

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func draw(_ fill: BackgroundPreset.Fill, in rect: CGRect, ctx: CGContext) {
        switch fill {
        case .solid(let color):
            ctx.setFillColor(color.cgColor())
            ctx.fill(rect)
        case .linearGradient(let stops, let angle):
            let colors = stops.map { $0.color.cgColor() } as CFArray
            let locations = stops.map { CGFloat($0.location) }
            guard let gradient = CGGradient(colorsSpace: sRGB, colors: colors, locations: locations) else {
                if let first = stops.first { draw(.solid(color: first.color), in: rect, ctx: ctx) }
                return
            }
            // CSS convention: 0 deg points up, 90 deg points right. In CG's y-up space that is (sin, cos).
            let radians = CGFloat(angle) * .pi / 180
            let direction = CGPoint(x: sin(radians), y: cos(radians))
            // Half the length of the gradient line that exactly covers the rect corner to corner.
            let half = (abs(rect.width * direction.x) + abs(rect.height * direction.y)) / 2
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let start = CGPoint(x: center.x - direction.x * half, y: center.y - direction.y * half)
            let end = CGPoint(x: center.x + direction.x * half, y: center.y + direction.y * half)
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }
}
```

**Step 4: Run tests**

Run: `swift test`
Expected: green. If `testShadowDarkensBelowTheImage` fails with `below` equal to bone, the shadow was not applied to the transparency layer: make sure `setShadow` happens before `beginTransparencyLayer` and nothing resets the state in between. If `testGradientRunsBottomToTopAtZeroDegrees` fails, the y direction is flipped: `TestImages.pixel` counts `y` from the top while CG draws y-up.

**Step 5: Commit**

```bash
git add Sources/MiracleShotCore/Background/BackgroundRenderer.swift Tests/MiracleShotCoreTests/BackgroundRendererTests.swift
git commit -m "Add BackgroundRenderer with padding, corner radius, gradient and shadow"
```

---

### Task 3: App icon generated at build time

**Files:**
- Create: `scripts/make-icon.swift`
- Modify: `scripts/build-app.sh` (generate iconset, `iconutil`, `CFBundleIconFile`)
- Modify: `.gitignore` (ensure `build/` is ignored; it already is if phase 1 added it, check)

**Design of the icon (1024 grid, scale everything by `size / 1024`):**
- Transparent canvas. Rounded square inset 100 on every side (so 824 wide), corner radius 185, filled `#0b0b0c` (ink), 6 px border `#2a2a2d` (line).
- Four viewfinder brackets in `#d4ff3f` (lime): stroke width 56, round caps, each bracket is an L of two 170-long legs at the corners of a 560x560 square centered on the canvas.
- Center dot: circle radius 54 filled `#f3f0e8` (bone).
- Hex values mirror `BrandPalette`; the script cannot import the package, so keep the comment `// Mirrors BrandPalette in MiracleShotCore` above them.

**Step 1: Write the script**

`scripts/make-icon.swift` (run with `swift scripts/make-icon.swift <iconset-dir>`):

```swift
// Draws the Miracle Shot icon into an .iconset folder. Usage: swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit
import Foundation

// Mirrors BrandPalette in MiracleShotCore.
let ink = NSColor(srgbRed: 0x0b / 255, green: 0x0b / 255, blue: 0x0c / 255, alpha: 1)
let line = NSColor(srgbRed: 0x2a / 255, green: 0x2a / 255, blue: 0x2d / 255, alpha: 1)
let lime = NSColor(srgbRed: 0xd4 / 255, green: 0xff / 255, blue: 0x3f / 255, alpha: 1)
let bone = NSColor(srgbRed: 0xf3 / 255, green: 0xf0 / 255, blue: 0xe8 / 255, alpha: 1)

func draw(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let plate = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                             xRadius: 185 * s, yRadius: 185 * s)
    ink.setFill(); plate.fill()
    line.setStroke(); plate.lineWidth = 6 * s; plate.stroke()

    let box = NSRect(x: 232 * s, y: 232 * s, width: 560 * s, height: 560 * s)
    let leg = 170 * s
    let brackets = NSBezierPath()
    brackets.lineWidth = 56 * s
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    for (corner, dx, dy) in [(NSPoint(x: box.minX, y: box.minY), 1.0, 1.0), (NSPoint(x: box.maxX, y: box.minY), -1.0, 1.0),
                             (NSPoint(x: box.minX, y: box.maxY), 1.0, -1.0), (NSPoint(x: box.maxX, y: box.maxY), -1.0, -1.0)] {
        brackets.move(to: NSPoint(x: corner.x, y: corner.y + leg * dy))
        brackets.line(to: corner)
        brackets.line(to: NSPoint(x: corner.x + leg * dx, y: corner.y))
    }
    lime.setStroke(); brackets.stroke()

    let dot = NSBezierPath(ovalIn: NSRect(x: 512 * s - 54 * s, y: 512 * s - 54 * s, width: 108 * s, height: 108 * s))
    bone.setFill(); dot.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try draw(size: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(size: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Wrote \(out.path)")
```

**Step 2: Run it once by hand**

Run: `swift scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns && ls -la build/AppIcon.icns`
Expected: an `.icns` of a few hundred KB. Open `build/AppIcon.iconset/icon_512x512@2x.png` with `open` and check by eye: dark plate, lime brackets, bone dot, transparent outside the plate.

**Step 3: Wire into build-app.sh**

In `scripts/build-app.sh`, after copying the resource bundles and before writing `Info.plist`:

```bash
# App icon: drawn by scripts/make-icon.swift so no binary lives in the repo.
swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$OUT/Contents/Resources/AppIcon.icns"
```

and add to the plist dict:

```xml
  <key>CFBundleIconFile</key><string>AppIcon</string>
```

**Step 4: Verify**

Run: `scripts/build-app.sh` then `ls "build/Miracle Shot.app/Contents/Resources/"` — `AppIcon.icns` present; `open -R "build/Miracle Shot.app"` shows the icon in Finder (Finder may cache the old generic icon for a rebuilt bundle at the same path: `touch "build/Miracle Shot.app"` refreshes it).

**Step 5: Commit**

```bash
git add scripts/make-icon.swift scripts/build-app.sh
git commit -m "Generate the app icon at build time"
```

---

### Task 4: Brand fonts in the bundle

**Files:**
- Create: `scripts/fetch-fonts.sh`
- Add (binary, committed): `Sources/MiracleShotUI/Resources/fonts/Onest-Variable.ttf`, `JetBrainsMono-Variable.ttf`, `Geologica-Variable.ttf`
- Create: `Sources/MiracleShotUI/Support/BrandFont.swift`
- Modify: `Sources/MiracleShotUI/Support/BrandButton.swift` (font), `Sources/MiracleShotUI/Toast/ToastPresenter.swift:19,22` (fonts), `Sources/MiracleShotUI/Selection/SelectionView.swift:157` (mono size label)
- Test: `Tests/MiracleShotAppTests/BrandFontTests.swift`

**Step 1: Fetch the fonts**

`scripts/fetch-fonts.sh`:

```bash
#!/bin/bash
# Downloads the brand typefaces (OFL) from the Google Fonts repository into the UI resource bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="Sources/MiracleShotUI/Resources/fonts"
BASE="https://github.com/google/fonts/raw/main/ofl"
mkdir -p "$DEST"
curl -fsSL "$BASE/onest/Onest%5Bwght%5D.ttf" -o "$DEST/Onest-Variable.ttf"
curl -fsSL "$BASE/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf" -o "$DEST/JetBrainsMono-Variable.ttf"
curl -fsSL "$BASE/geologica/Geologica%5BCRSV,SHRP,slnt,wght%5D.ttf" -o "$DEST/Geologica-Variable.ttf"
ls -la "$DEST"
```

Run: `chmod +x scripts/fetch-fonts.sh && scripts/fetch-fonts.sh`
Expected: three `.ttf` files, each larger than 100 KB. Check the family names CoreText will report: `for f in Sources/MiracleShotUI/Resources/fonts/*.ttf; do fc-scan --format '%{family}\n' "$f" 2>/dev/null || mdls -name kMDItemFonts "$f"; done`. If `fc-scan` is missing, the test in Step 2 reports the actual family names; adjust `BrandFont.Family` raw values to match.

**Step 2: Write the failing test**

`Tests/MiracleShotAppTests/BrandFontTests.swift`:

```swift
import AppKit
import XCTest
@testable import MiracleShotUI

final class BrandFontTests: XCTestCase {
    func testBundleShipsThreeVariableFonts() throws {
        let dir = try XCTUnwrap(UIResources.bundle.url(forResource: "fonts", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".ttf") }.sorted()
        XCTAssertEqual(files, ["Geologica-Variable.ttf", "JetBrainsMono-Variable.ttf", "Onest-Variable.ttf"])
    }

    func testBrandFacesResolveToBrandFamilies() {
        XCTAssertEqual(BrandFont.text(size: 12).familyName, "Onest")
        XCTAssertEqual(BrandFont.text(size: 12, weight: 600).familyName, "Onest")
        XCTAssertEqual(BrandFont.mono(size: 11).familyName, "JetBrains Mono")
        XCTAssertEqual(BrandFont.display(size: 20).familyName, "Geologica")
    }

    func testRequestedSizeIsKept() {
        XCTAssertEqual(BrandFont.text(size: 13).pointSize, 13)
        XCTAssertEqual(BrandFont.mono(size: 11).pointSize, 11)
    }
}
```

Run: `swift test --filter BrandFontTests`
Expected: compile error, `BrandFont` unknown.

**Step 3: Implement**

`Sources/MiracleShotUI/Support/BrandFont.swift`:

```swift
import AppKit
import CoreText

/// Brand typefaces from the UI resource bundle (variable TTFs, registered once per process). Every accessor falls
/// back to the system font when a face is missing, so a broken bundle degrades to SF instead of crashing.
public enum BrandFont {
    public enum Family: String {
        case text = "Onest"
        case mono = "JetBrains Mono"
        case display = "Geologica"
    }

    /// Onest, chrome text. `weight` is the OpenType wght axis value (400 regular, 500 medium, 600 semibold).
    public static func text(size: CGFloat, weight: CGFloat = 400) -> NSFont { font(.text, size: size, weight: weight) }
    /// JetBrains Mono, sizes, HUD values and every number.
    public static func mono(size: CGFloat, weight: CGFloat = 500) -> NSFont { font(.mono, size: size, weight: weight) }
    /// Geologica, large headings only.
    public static func display(size: CGFloat, weight: CGFloat = 600) -> NSFont { font(.display, size: size, weight: weight) }

    private static let registered: Bool = {
        guard let dir = UIResources.bundle.url(forResource: "fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return false
        }
        var any = false
        for url in files where url.pathExtension.lowercased() == "ttf" {
            // Returns false when the font is already registered (e.g. by a second test bundle); that is still usable.
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { any = true }
        }
        return any
    }()

    /// 'wght' as a four-character tag.
    private static let weightAxis = 0x77676874

    static func font(_ family: Family, size: CGFloat, weight: CGFloat) -> NSFont {
        _ = registered
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family.rawValue,
            kCTFontVariationAttribute: [NSNumber(value: weightAxis): weight],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
        guard font.familyName == family.rawValue else { return fallback(family, size: size, weight: weight) }
        return font
    }

    private static func fallback(_ family: Family, size: CGFloat, weight: CGFloat) -> NSFont {
        let systemWeight: NSFont.Weight = weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular
        switch family {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: systemWeight)
        case .text, .display: return .systemFont(ofSize: size, weight: systemWeight)
        }
    }
}
```

Then apply the faces:
- `BrandButton.swift`: `font = BrandFont.text(size: 12, weight: 500)` and in `setTitleColor` use `font ?? BrandFont.text(size: 12, weight: 500)`.
- `ToastPresenter.swift`: title `BrandFont.text(size: 13, weight: 600)`, body `BrandFont.text(size: 12)`.
- `SelectionView.swift` size label: `.font: BrandFont.mono(size: 11, weight: 500)`.

**Step 4: Run tests**

Run: `swift test`
Expected: green. If `familyName` comes back as e.g. "Onest Variable", change the `Family` raw value to the reported name and keep the test expectation in sync with the actual family name (the test is the source of truth for what CoreText reports).

**Step 5: Commit**

```bash
git add scripts/fetch-fonts.sh Sources/MiracleShotUI/Resources/fonts Sources/MiracleShotUI/Support/BrandFont.swift Sources/MiracleShotUI/Support/BrandButton.swift Sources/MiracleShotUI/Toast/ToastPresenter.swift Sources/MiracleShotUI/Selection/SelectionView.swift Tests/MiracleShotAppTests/BrandFontTests.swift
git commit -m "Ship Onest, JetBrains Mono and Geologica and use them in the chrome"
```

---

### Task 5: "Background" button and preset menu in the quick preview

**Files:**
- Modify: `Sources/MiracleShotUI/Preview/QuickPreviewPanel.swift`

No automated test: the panel is AppKit-only and covered by the manual check in Task 7. Keep the change small and obvious.

**Step 1: Add the action and the API**

In `Action`, add `case background` before `.reveal` (order: `edit, pin, ocr, ai, background, reveal`) with title `"Background"`.

Add public state next to `handlers`:

```swift
    /// Presets offered by the Background button; the button is hidden when this is empty or no handler is set.
    public var backgroundPresets: [BackgroundPreset] = []
    /// Called with the previewed capture and the chosen preset. The panel dismisses itself first.
    public var onApplyBackground: (@MainActor (Capture, URL?, BackgroundPreset) -> Void)?
```

**Step 2: Show the button**

Replace the `buttons` filter with an explicit visibility rule:

```swift
        let buttons = Action.allCases.filter { isVisible($0, fileURL: fileURL) }.map { action -> BrandButton in
```

and add:

```swift
    private func isVisible(_ action: Action, fileURL: URL?) -> Bool {
        switch action {
        case .background: return onApplyBackground != nil && !backgroundPresets.isEmpty
        case .reveal: return handlers[.reveal] != nil && fileURL != nil   // nothing to reveal after a failed save
        default: return handlers[action] != nil
        }
    }
```

**Step 3: Pop the menu**

`hoverChanged` must ignore the mouseExited the open menu triggers, or the countdown restarts underneath it:

```swift
    private func hoverChanged(_ inside: Bool) {
        // The open menu steals the pointer and sends a mouseExited that must not restart the countdown.
        guard !isShowingBackgroundMenu else { return }
        if inside { timing?.hoverBegan(now: Self.now()) } else { timing?.hoverEnded(now: Self.now()) }
    }
```

In `buttonPressed(_:)`:

```swift
    @objc private func buttonPressed(_ sender: NSButton) {
        let action = Action.allCases[sender.tag]
        if action == .background { showBackgroundMenu(from: sender) } else { run(action) }
    }
```

Add:

```swift
    private var isShowingBackgroundMenu = false

    private func showBackgroundMenu(from button: NSView) {
        guard current != nil else { return }
        let menu = NSMenu()
        for (index, preset) in backgroundPresets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(backgroundChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            // Rendered at 2x so the tile stays crisp on Retina menus.
            if let swatch = BackgroundRenderer.swatch(preset, size: 28) {
                item.image = NSImage(cgImage: swatch, size: NSSize(width: 14, height: 14))
            }
            menu.addItem(item)
        }
        // The menu runs its own event loop; hold the countdown while it is open (see `hoverChanged`) and resume it
        // afterwards only if the pointer left the panel, otherwise the usual mouseExited will do it later.
        isShowingBackgroundMenu = true
        timing?.hoverBegan(now: Self.now())
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        isShowingBackgroundMenu = false
        if let panel, !panel.frame.contains(NSEvent.mouseLocation) {
            timing?.hoverEnded(now: Self.now())
        }
    }

    @objc private func backgroundChosen(_ sender: NSMenuItem) {
        guard let current, let handler = onApplyBackground, backgroundPresets.indices.contains(sender.tag) else { return }
        let preset = backgroundPresets[sender.tag]
        let payload = current
        dismiss(animated: true)
        handler(payload.capture, payload.fileURL, preset)
    }
```

**Step 4: Build and run the suite**

Run: `swift build && swift test`
Expected: green (no new tests; the suite proves nothing broke).

**Step 5: Commit**

```bash
git add Sources/MiracleShotUI/Preview/QuickPreviewPanel.swift
git commit -m "Add Background preset menu to the quick preview"
```

---

### Task 6: `CaptureCoordinator.applyBackground`

**Files:**
- Modify: `Sources/MiracleShotUI/Coordinator/CaptureCoordinator.swift`
- Modify: `Tests/MiracleShotAppTests/Helpers/Fakes.swift` (`FakeFiles.lastSaved`)
- Test: `Tests/MiracleShotAppTests/CaptureCoordinatorTests.swift`

**Step 1: Write the failing tests**

In `Fakes.swift`, `FakeFiles` gets `var lastSaved: Capture?` set at the top of `save` (before the throw check).

Append to `CaptureCoordinatorTests` (look at the existing `setUp` for the names of `sut`, `log`, `files`, `preview`, `notifications`, `historyURL`; use exactly those):

```swift
    private var solidPreset: BackgroundPreset {
        BackgroundPreset(id: "t", name: "T", fill: .solid(color: BrandPalette.lime), padding: 10, cornerRadius: 0, shadow: nil)
    }

    func testApplyBackgroundRunsTheFinishPathAgain() async {
        await sut.perform(.captureArea)
        let source = sut.lastCapture!
        log.entries.removeAll()

        sut.applyBackground(solidPreset, to: source)

        XCTAssertEqual(log.entries.first, "copy")
        XCTAssertTrue(log.entries[1].hasPrefix("save("))
        XCTAssertEqual(log.entries.last, "preview")
        XCTAssertEqual(log.entries.count, 3)
        XCTAssertEqual(files.lastSaved?.pixelWidth, source.pixelWidth + 20)
        XCTAssertEqual(files.lastSaved?.pixelHeight, source.pixelHeight + 20)
        XCTAssertEqual(sut.history.entries.count, 2)
        XCTAssertEqual(sut.history.entries.first?.sourceApp, "Safari")
        XCTAssertEqual(sut.state, .previewing)
        XCTAssertEqual(sut.lastCapture?.pixelWidth, source.pixelWidth + 20)
    }

    func testApplyBackgroundIsIgnoredWhenNotPreviewing() {
        let source = makeCapture()
        sut.applyBackground(solidPreset, to: source)
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertEqual(sut.state, .idle)
    }

    func testApplyBackgroundScalesPaddingByCaptureScale() async {
        await sut.perform(.captureArea)
        let source = Capture(image: makeTestImage(width: 8, height: 6), bounds: CGRect(x: 0, y: 0, width: 4, height: 3), scaleFactor: 2)
        sut.applyBackground(solidPreset, to: source)
        XCTAssertEqual(files.lastSaved?.pixelWidth, 8 + 40)
        XCTAssertEqual(files.lastSaved?.bounds.size, CGSize(width: 24, height: 23))
    }

    func testDismissOfSupersededPreviewDoesNotResetAfterApplyBackground() async {
        await sut.perform(.captureArea)
        let firstDismiss = preview.onDismiss
        sut.applyBackground(solidPreset, to: sut.lastCapture!)
        firstDismiss?()
        XCTAssertEqual(sut.state, .previewing)
        preview.onDismiss?()
        XCTAssertEqual(sut.state, .idle)
    }
```

`HistoryEntry` ordering: check `HistoryIndex.append` (newest first or last) and adjust `entries.first`/`.last` accordingly; the assertion is "the entry added by applyBackground carries the source app".

**Step 2: Run to verify failure**

Run: `swift test --filter CaptureCoordinatorTests`
Expected: compile error, `applyBackground` unknown.

**Step 3: Implement**

In `CaptureCoordinator`, after `clearHistory()`:

```swift
    /// Renders `source` on `preset` and pushes the result through the normal finish path, so it is copied, saved,
    /// listed in history and previewed exactly like a fresh capture. Only meaningful while the preview is up.
    public func applyBackground(_ preset: BackgroundPreset, to source: Capture) {
        guard state == .previewing else { return }
        guard let image = BackgroundRenderer.render(source.image, preset: preset, scale: source.scaleFactor) else {
            notifications.post(title: "Could not apply background", body: "Rendering \"\(preset.name)\" failed.", isError: true)
            return
        }
        let size = CGSize(width: CGFloat(image.width) / source.scaleFactor, height: CGFloat(image.height) / source.scaleFactor)
        let shot = Capture(image: image, sourceAppName: source.sourceAppName, sourceWindowTitle: source.sourceWindowTitle,
                           bounds: CGRect(origin: source.bounds.origin, size: size), scaleFactor: source.scaleFactor)
        finish(shot)
    }
```

**Step 4: Run tests**

Run: `swift test`
Expected: green.

**Step 5: Commit**

```bash
git add Sources/MiracleShotUI/Coordinator/CaptureCoordinator.swift Tests/MiracleShotAppTests
git commit -m "Apply a background preset through the coordinator finish path"
```

---

### Task 7: Wire it up, build, manual check

**Files:**
- Modify: `Sources/MiracleShotUI/App/AppDelegate.swift`
- Modify: `docs/plans/2026-09-14-miracle-shot-design.md` (§3.1: `BackgroundPreset` fields as built; note "button only")

**Step 1: Wire the preview**

In `applicationDidFinishLaunching`, after the `preview.handlers[.reveal]` block:

```swift
        preview.backgroundPresets = BackgroundPresetLibrary.load(
            userDirectory: Settings.supportDirectory.appendingPathComponent("presets", isDirectory: true))
        preview.onApplyBackground = { [weak self] capture, _, preset in
            self?.coordinator.applyBackground(preset, to: capture)
        }
        log.info("Background presets: \(self.preview.backgroundPresets.map(\.id).joined(separator: ", "), privacy: .public)")
```

**Step 2: Full suite and app build**

Run: `swift test && scripts/build-app.sh`
Expected: tests green; "Signed with Miracle Shot Dev"; `AppIcon.icns` and `MiracleShot_MiracleShotCore.bundle/presets/*.json` and `MiracleShot_MiracleShotUI.bundle/fonts/*.ttf` inside the app.

**Step 3: Manual check (controller does this with the user)**

1. Quit the running app, `open "build/Miracle Shot.app"`, log shows `Background presets: lab-dark, lime, bone, coral`.
2. Shift+Cmd+1, select an area. Preview shows buttons `Background`, `Reveal` in Onest.
3. Click `Background`: menu with four items and swatches; the preview does not disappear while the menu is open.
4. Pick `Lime`: preview reappears with the padded image; Cmd+V into any app pastes the padded version; a second file appears in the save folder; History has two entries.
5. Pick `Lab Dark` from the new preview: works again (stacking is allowed, not prevented).
6. Size label in the overlay is JetBrains Mono; toast title is Onest.
7. Finder shows the new icon on `build/Miracle Shot.app`.

**Step 4: Commit**

```bash
git add Sources/MiracleShotUI/App/AppDelegate.swift docs/plans/2026-09-14-miracle-shot-design.md
git commit -m "Wire background presets into the preview"
```

Then on master: `git tag phase-2a-complete`.

---

### Task 8: High-quality gradients (perceptual interpolation, dithering, glows)

User feedback after the first build: "make all backgrounds high-quality gradients". Two-stop sRGB gradients look flat (Lab Dark reads as a solid) and blend through muddy midtones (Coral to ink2 goes brown); subtle dark gradients band at 8 bits.

**Files:**
- Create: `Sources/MiracleShotCore/Brand/OKLab.swift`
- Modify: `Sources/MiracleShotCore/Background/BackgroundPreset.swift` (add `GradientGlow`, `glows`, custom decoder with default)
- Modify: `Sources/MiracleShotCore/Background/BackgroundRenderer.swift` (fill rendered in 16 bit, OKLab-expanded stops, glows, dithered to 8 bit)
- Modify: `Sources/MiracleShotCore/Resources/presets/*.json` (all four redesigned)
- Test: `Tests/MiracleShotCoreTests/OKLabTests.swift`, `Tests/MiracleShotCoreTests/BackgroundRendererTests.swift`, `Tests/MiracleShotCoreTests/BackgroundPresetTests.swift`

**Step 1: OKLab (failing tests first)**

`Tests/MiracleShotCoreTests/OKLabTests.swift`:

```swift
import XCTest
@testable import MiracleShotCore

final class OKLabTests: XCTestCase {
    func testBlackAndWhiteAnchorLightness() {
        XCTAssertEqual(OKLab.from(BrandColor(red: 0, green: 0, blue: 0)).l, 0, accuracy: 1e-4)
        XCTAssertEqual(OKLab.from(BrandColor(red: 1, green: 1, blue: 1)).l, 1, accuracy: 1e-3)
    }

    func testMidGrayIsPerceptuallyAboveHalf() {
        // sRGB 50 percent gray sits near L = 0.6 in OKLab, not 0.5: that is the whole point of the space.
        let l = OKLab.from(BrandColor(hex: "#808080")!).l
        XCTAssertEqual(l, 0.6, accuracy: 0.02)
    }

    func testRoundTripsPaletteColors() {
        for color in BrandPalette.all {
            let back = OKLab.from(color).toSRGB()
            XCTAssertEqual(back.red, color.red, accuracy: 0.002, color.hex)
            XCTAssertEqual(back.green, color.green, accuracy: 0.002, color.hex)
            XCTAssertEqual(back.blue, color.blue, accuracy: 0.002, color.hex)
        }
    }

    func testMixIsLinearInLab() {
        let a = OKLab.from(BrandPalette.coral), b = OKLab.from(BrandPalette.ink2)
        let mid = OKLab.mix(a, b, 0.5)
        XCTAssertEqual(mid.l, (a.l + b.l) / 2, accuracy: 1e-9)
        XCTAssertEqual(mid.a, (a.a + b.a) / 2, accuracy: 1e-9)
    }

    func testToSRGBClampsOutOfGamut() {
        let hot = OKLab(l: 1.2, a: 0.4, b: 0.4).toSRGB()
        XCTAssertLessThanOrEqual(hot.red, 1)
        XCTAssertGreaterThanOrEqual(hot.blue, 0)
    }
}
```

`Sources/MiracleShotCore/Brand/OKLab.swift`:

```swift
import CoreGraphics
import Foundation

/// Bjorn Ottosson's OKLab: a perceptual space where straight-line blends stay clean (no gray or brown dip
/// halfway between two saturated colors). Used only to build gradient stops; storage stays sRGB.
public struct OKLab: Sendable, Equatable {
    public var l: Double
    public var a: Double
    public var b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    public static func from(_ color: BrandColor) -> OKLab {
        let r = linear(color.red), g = linear(color.green), bl = linear(color.blue)
        let l_ = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m_ = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s_ = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        return OKLab(l: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                     a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                     b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    /// Back to gamma-encoded sRGB, clamped to the gamut.
    public func toSRGB() -> BrandColor {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_
        let r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let bl = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        return BrandColor(red: gamma(r), green: gamma(g), blue: gamma(bl))
    }

    public static func mix(_ x: OKLab, _ y: OKLab, _ t: Double) -> OKLab {
        OKLab(l: x.l + (y.l - x.l) * t, a: x.a + (y.a - x.a) * t, b: x.b + (y.b - x.b) * t)
    }

    // MARK: - sRGB transfer function

    private static func linear(_ c: CGFloat) -> Double {
        let v = Double(c)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private func gamma(_ v: Double) -> CGFloat {
        let c = min(1, max(0, v))
        return CGFloat(c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055)
    }
}
```

Run `swift test --filter OKLabTests`: fails to compile, then passes after adding the file.

**Step 2: Model — glows**

In `BackgroundPreset.swift` add:

```swift
/// A soft radial spot of one palette color over the base fill; a few of them give the layered "mesh" look.
public struct GradientGlow: Codable, Sendable, Equatable {
    public var color: BrandColor
    /// Center in unit canvas coordinates: (0, 0) top-left, (1, 1) bottom-right.
    public var x: Double
    public var y: Double
    /// Radius as a fraction of the canvas diagonal.
    public var radius: Double
    /// Opacity at the center, fading to zero at the radius.
    public var opacity: Double

    public init(color: BrandColor, x: Double, y: Double, radius: Double, opacity: Double) { ... }
}
```

`BackgroundPreset` gains `public var glows: [GradientGlow]` (init parameter with default `[]`, placed after `fill`). Keep synthesized `encode`; write `init(from decoder:)` by hand so `glows` is optional in JSON (`decodeIfPresent ... ?? []`), everything else decoded as before. `Fill.colors` stays; add `public var colors: [BrandColor]` on the preset = `fill.colors + glows.map(\.color)` and switch `testBuiltInPresetsUseOnlyPaletteColors` to it.

Tests in `BackgroundPresetTests`:
- `testPresetWithoutGlowsDecodesToEmptyGlows` (the existing readable JSON has no `glows`).
- `testGlowsRoundTrip` (a preset with one glow encodes and decodes equal).

**Step 3: Renderer**

Replace the fill path in `BackgroundRenderer` with a dedicated high-quality pass:

```swift
    /// The fill is drawn in 16 bits per channel (base gradient with OKLab-expanded stops, then the glows) and
    /// quantized to 8 bits with triangular dither, so subtle dark ramps do not band and blends stay clean.
    static func fillImage(_ preset: BackgroundPreset, width: Int, height: Int) -> CGImage?
```

- 16-bit context: `CGContext(data: nil, width:, height:, bitsPerComponent: 16, bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)`.
- Base fill: `.solid` fills; `.linearGradient` expands the stops to `gradientSamples = 48` evenly spaced colors: for each t, find the surrounding stops (sorted by location, clamped at the ends), `OKLab.mix` them, `toSRGB()`. Single stop = solid. Then `CGGradient(colorsSpace:colors:locations:)` with the 48 samples and the same start/end geometry as today.
- Glows: for each glow, center = (x * width, (1 - y) * height) (CG is y-up), radius = glow.radius * hypot(width, height); 24 samples of the glow color with alpha `opacity * (1 - smoothstep(t))` where `smoothstep(t) = t * t * (3 - 2 * t)`; `drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])`.
- Dither to 8 bits: read the 16-bit buffer (`ctx.data`, `bytesPerRow`, components are `UInt16` little-endian, premultiplied but the fill is opaque so alpha is 65535), write an 8-bit premultipliedLast buffer: `v8 = clamp(round(v16 / 257 + noise))` with `noise` triangular in (-0.5, 0.5): the mean of two independent hashes of the same pixel with different salts, minus 0.5 (never reuse a neighbour's hash: that correlates adjacent pixels into horizontal streaks). Alpha is written as 255 directly. Deterministic, no randomness in tests. Build the 8-bit `CGImage` from the buffer with `CGDataProvider` (sRGB, premultipliedLast, 8 bpc).
- `render` draws `fillImage` into the canvas instead of calling `draw(fill)`; `swatch` uses it too (small sizes are fine). Keep `draw(_:in:ctx:)` only if still needed; otherwise remove it.
- `isRenderable` also checks glows: finite values, `0...1` for x, y, opacity, radius > 0 and finite.

Tests in `BackgroundRendererTests` (add; keep the existing ones passing):

```swift
    func testGradientBlendsPerceptually() throws {
        // Coral to ink2 through sRGB dips into brown; through OKLab the midpoint stays on the straight Lab line.
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.coral, location: 0),
                                                                GradientStop(color: BrandPalette.ink2, location: 1)], angle: 90)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: preset(fill: fill, padding: 100), scale: 1))
        let p = TestImages.pixel(out, x: out.width / 2, y: 5)
        let got = OKLab.from(BrandColor(red: CGFloat(p.r) / 255, green: CGFloat(p.g) / 255, blue: CGFloat(p.b) / 255))
        let want = OKLab.mix(OKLab.from(BrandPalette.coral), OKLab.from(BrandPalette.ink2), 0.5)
        XCTAssertEqual(got.l, want.l, accuracy: 0.02)
        XCTAssertEqual(got.a, want.a, accuracy: 0.02)
        XCTAssertEqual(got.b, want.b, accuracy: 0.02)
    }

    func testSubtleDarkGradientIsDitheredNotBanded() throws {
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.ink, location: 0),
                                                                GradientStop(color: BrandPalette.ink2, location: 1)], angle: 90)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: preset(fill: fill, padding: 300), scale: 1))
        // A horizontal ramp of 9 levels over 600 px: without dither every column is one flat value.
        var columnsWithNoise = 0
        for x in stride(from: 10, to: 290, by: 20) {
            let values = Set((0..<200).map { TestImages.pixel(out, x: x, y: $0).r })
            XCTAssertLessThanOrEqual(values.count, 3, "dither must stay within one level")
            if values.count >= 2 { columnsWithNoise += 1 }
        }
        XCTAssertGreaterThanOrEqual(columnsWithNoise, 8)
        // The ramp still runs left to right on average.
        func mean(_ x: Int) -> Double { (0..<200).map { Double(TestImages.pixel(out, x: x, y: $0).r) }.reduce(0, +) / 200 }
        XCTAssertLessThan(mean(20), mean(280))
    }

    func testGlowBrightensAroundItsCenter() throws {
        let glow = GradientGlow(color: BrandPalette.lime, x: 0.2, y: 0.2, radius: 0.3, opacity: 1)
        var p = preset(fill: .solid(color: BrandPalette.ink), padding: 100)
        p.glows = [glow]
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: p, scale: 1))
        let near = TestImages.pixel(out, x: Int(0.2 * Double(out.width)), y: Int(0.2 * Double(out.height)))
        let far = TestImages.pixel(out, x: out.width - 5, y: out.height - 5)
        XCTAssertGreaterThan(near.g, 200)
        TestImages.assertClose(far, TestImages.RGBA(r: 0x0b, g: 0x0b, b: 0x0c, a: 255), tolerance: 2)
    }

    func testUnrenderableGlowReturnsNil() {
        var p = preset(fill: .solid(color: BrandPalette.ink))
        p.glows = [GradientGlow(color: BrandPalette.lime, x: 2, y: 0, radius: 0.3, opacity: 1)]
        XCTAssertNil(BackgroundRenderer.render(source(), preset: p, scale: 1))
    }
```

Note for `testGradientBlendsPerceptually`: the sampled pixel sits at the horizontal center of a 90 degree gradient, i.e. t = 0.5. The dither adds at most half a level, well inside the 0.02 tolerance.

**Step 4: Presets** (palette only; hex tokens: ink `#0b0b0c`, ink2 `#141416`, ink3 `#1c1c1f`, bone `#f3f0e8`, boneDim `#b8b4a8`, boneFaint `#6f6c63`, lime `#d4ff3f`, limeDim `#9bbf2a`, coral `#ff5a36`, line `#2a2a2d`)

`01-lab-dark.json`: gradient angle 160, stops line@0, ink3@0.35, ink@1; glows: lime x 0.85 y 0.12 r 0.45 op 0.16; limeDim x 0.08 y 0.92 r 0.4 op 0.08. Shadow blur 48 offsetY 20 opacity 0.7.
`02-lime.json`: angle 135, stops lime@0, lime@0.45, limeDim@1; glows: bone x 0.12 y 0.1 r 0.45 op 0.35; limeDim x 0.95 y 0.95 r 0.5 op 0.5. Shadow 40/16/0.35.
`03-bone.json`: angle 135, stops bone@0, bone@0.4, boneDim@1; glows: bone x 0.15 y 0.12 r 0.5 op 0.7; boneFaint x 0.92 y 0.95 r 0.5 op 0.25. Shadow 40/16/0.25.
`04-coral.json`: angle 135, stops coral@0, coral@0.55, ink2@1; glows: bone x 0.12 y 0.1 r 0.4 op 0.3; ink x 0.95 y 0.95 r 0.5 op 0.45. Shadow 40/16/0.5.

Padding 64, corner radius 12 everywhere.

**Step 5: Full suite, commit**

`swift test` green (existing renderer tests must still pass unchanged). Commit: "Render backgrounds in 16 bit with OKLab stops, dithering and glows".

---

### Task 9: Proportional geometry (padding, radius, shadow in percent)

User feedback: a fixed 64 pt padding is half the picture on a small fragment and a thin rim on a 5K capture. Geometry becomes a percentage of the capture's size so every screenshot gets the same proportions.

**Reference size:** `reference = (source.width + source.height) / 2` in source pixels. Padding, corner radius, shadow blur and shadow offset are percentages of it. Floors in points (multiplied by `scale`) keep tiny captures usable: padding at least 24 pt, corner radius at least 6 pt. Nothing is scaled by `scale` except the floors, because the reference is already in pixels.

**Files:**
- Modify: `Sources/MiracleShotCore/Background/BackgroundPreset.swift` — rename `padding` -> `paddingPercent`, `cornerRadius` -> `cornerRadiusPercent`; `BackgroundShadow` fields `blur` -> `blurPercent`, `offsetY` -> `offsetPercent`, `opacity` unchanged. Update doc comments ("percent of the mean side of the screenshot"). JSON keys follow the property names.
- Modify: `Sources/MiracleShotCore/Background/BackgroundRenderer.swift` — compute pixel values from the reference; add `public static let minimumPadding: CGFloat = 24` and `minimumCornerRadius: CGFloat = 6` (points); `isRenderable` checks the renamed fields (finite, non-negative).
- Modify: the four preset JSON files: `paddingPercent` 8, `cornerRadiusPercent` 1.2, shadow `blurPercent` 5, `offsetPercent` 2, opacities unchanged (Lab Dark keeps 0.7 etc.).
- Modify tests: `BackgroundRendererTests` (all geometry expectations), `BackgroundPresetTests` (field names, built-in checks use `paddingPercent > 0`), `CaptureCoordinatorTests` (`solidPreset` and pixel expectations), keep every existing assertion's intent.

**Renderer geometry (exact):**

```swift
let reference = CGFloat(source.width + source.height) / 2
let padding = max(Self.minimumPadding * scale, reference * CGFloat(preset.paddingPercent) / 100).rounded()
let radius = min(max(Self.minimumCornerRadius * scale, reference * CGFloat(preset.cornerRadiusPercent) / 100),
                 imageRect.width / 2, imageRect.height / 2)
// shadow
blur: reference * CGFloat(shadow.blurPercent) / 100
offset: CGSize(width: 0, height: -reference * CGFloat(shadow.offsetPercent) / 100)
```

`cornerRadiusPercent == 0` means square corners: apply the floor only when the percent is greater than zero (same for padding: `paddingPercent == 0` gives zero padding, so a test can render edge to edge).

**Tests to rewrite (keep names where the intent is unchanged):**
- Use a 200x100 source (reference 150). `paddingPercent: 20` -> padding 30 px -> output 260x160; image spans x 30..<230, y 30..<130. Update `testSolidFillPadsAndKeepsSource`, `testCornerRadiusClipsSourceCorners` (`cornerRadiusPercent: 8` -> 12 px radius; corner pixel (30,30) is fill, (130,30) top edge midpoint is red), `testShadowDarkensBelowTheImage` (`blurPercent 4`, `offsetPercent 6` -> 6 px blur, 9 px offset; sample 4 px under the bottom edge and 12 px above the top edge).
- `testScaleMultipliesPointValues` becomes `testScaleOnlyRaisesTheFloors`: 200x100 with `paddingPercent 20` at scale 1 is 260x160; at scale 2 the 48 px floor beats the 30 px percent value -> 296x196; a 20x10 source with `paddingPercent 20` at scale 1 gets the 24 pt floor -> 68x58, at scale 2 -> 116x106.
- `testFractionalScaleKeepsMarginsEqual`: 200x100, `paddingPercent 15.5` -> 23.25 -> but floor 24 * 1.5 = 36 wins at scale 1.5 -> 272x172, margins equal (check pixels at 35 and 36 like before).
- Gradient, dither, glow and perceptual tests: they use a 2x2 source with big padding; switch to `paddingPercent` values that give the same canvas: with a 2x2 source the floor applies, so use a 2x2 source with the floor (24 px -> 50x50) only where the canvas size does not matter, and otherwise set `paddingPercent` on a 200x200 source (reference 200): `paddingPercent 150` -> 300 px -> 800x800 canvas; keep sampled coordinates inside the padding area and away from the image.
- `testUnrenderablePresetsReturnNil`: NaN and negative `paddingPercent`, NaN `cornerRadiusPercent`, empty stops.
- New `testPaddingIsProportionalToTheCapture`: `paddingPercent 10` on 400x200 (reference 300 -> 30 px) and on 4000x2000 (reference 3000 -> 300 px); assert both widths.
- `CaptureCoordinatorTests`: `solidPreset` uses `paddingPercent: 10, cornerRadiusPercent: 0`; the 8x6 test capture hits the 24 pt floor: expect `pixelWidth + 48` at scale 1 and, in the scale-2 test, `8 + 96` px wide with bounds size `(4 + 48, 3 + 48)`.

**Commit:** "Make background padding, radius and shadow proportional to the capture".
