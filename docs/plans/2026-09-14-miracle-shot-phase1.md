# Miracle Shot — Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or superpowers:subagent-driven-development) to implement this plan task-by-task.

**Goal:** Menu-bar macOS app that captures area / window / full screen by hotkey, copies to clipboard, saves to disk, shows a floating preview, keeps history, and has a settings window.

**Architecture:** One SwiftPM package. `MiracleShotCore` (pure logic, no AppKit) holds the capture state machine, geometry, naming, timing, settings and history. `MiracleShotUI` (AppKit + SwiftUI library) holds the coordinator, system-service protocols with real implementations, panels and windows. `MiracleShotApp` is a thin executable with `main.swift`. Tests: `MiracleShotCoreTests` for Core, `MiracleShotAppTests` for the coordinator and service tables through fakes.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, XCTest, AppKit, SwiftUI, ScreenCaptureKit, Carbon (hotkeys), CoreGraphics, ImageIO. macOS 14+. Design: `docs/plans/2026-09-14-miracle-shot-design.md`.

---

## Conventions for every task

- **TDD.** Write the failing test, run it, see it fail for the expected reason, implement the minimum, run it green, commit. Never write implementation before a red test for Core and coordinator code.
- **Run tests:** `swift test --filter <TestClassName>` for the task, `swift test` for everything before commit. `swift build` must be warning-free for the files you touch.
- **Swift 6 strict concurrency is on.** Core types are value types and `Sendable`. AppKit classes are `@MainActor`. `CGImage` is already `Sendable` in this SDK; do not wrap it.
- **No `import AppKit` inside `Sources/MiracleShotCore`.** Foundation, CoreGraphics, CoreImage, ImageIO only.
- **Colors and fonts come only from `BrandPalette` (Core).** No hex literals anywhere else.
- **Commit messages:** English, imperative, short. Every commit message ends with a blank line and:
  `Claude-Session: https://claude.ai/code/session_012TeusS6XfhDMHoM7fu1tzs`
- **Text in code, comments and commits is English.** No emoji. Written Russian uses "е", never "ё".
- **Do not touch `Package.swift` after Task 1.** All targets, resources and fixture folders are declared there once.
- **Do not touch files owned by another task in the same wave.** Integration of parallel work happens in the dedicated integration task.
- **Parallel execution:** each subagent works in its own git worktree (`git worktree add ../miracle-shot-<task> -b task/<n>-<slug>`), because a shared `.build` under concurrent `swift test` produces phantom failures. Merge into `main` with `git merge --no-ff` after review.
- **Manual checks** are listed per task under "Manual check" and are executed by the reviewer on the real machine after merge; they are the only verification for pure AppKit drawing and permissions.

## Task graph (waves)

| Wave | Tasks | Parallel? |
|------|-------|-----------|
| A | 1 Package scaffold | no |
| B | 2 CaptureState, 3 NamingTemplate, 4 SelectionGeometry, 5 PreviewTiming, 6 JSONStore + HistoryIndex, 8 BrandPalette + PNGEncoder | yes, all independent |
| B2 | 7 Settings + HotkeySpec + KeyCodeMap (needs 6) | after 6 |
| C | 9 Service protocols + fakes + CaptureCoordinator (needs B, B2), 10 HotkeyManager (needs 7), 11 ScreenCaptureService, 12 SelectionOverlay basic (needs 4) | yes |
| D | 13 Milestone wiring: hotkey -> area -> clipboard + file + toast, build-app.sh | no |
| E | 14 SelectionOverlay full, 15 QuickPreviewPanel, 16 HistoryMenu, 17 SettingsWindow | yes |
| F | 18 Integration of wave E into AppDelegate, full manual checklist | no |

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/MiracleShotCore/Core.swift`
- Create: `Sources/MiracleShotCore/Resources/presets/.gitkeep`
- Create: `Sources/MiracleShotUI/UI.swift`
- Create: `Sources/MiracleShotUI/Resources/fonts/.gitkeep`
- Create: `Sources/MiracleShotApp/main.swift`
- Create: `Tests/MiracleShotCoreTests/CoreSmokeTests.swift`
- Create: `Tests/MiracleShotCoreTests/Fixtures/scroll/.gitkeep`
- Create: `Tests/MiracleShotAppTests/AppSmokeTests.swift`
- Create: `scripts/build-app.sh`
- Modify: `.gitignore`

**Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiracleShot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MiracleShot", targets: ["MiracleShotApp"]),
    ],
    targets: [
        .target(
            name: "MiracleShotCore",
            resources: [.copy("Resources/presets")]
        ),
        .target(
            name: "MiracleShotUI",
            dependencies: ["MiracleShotCore"],
            resources: [.copy("Resources/fonts")]
        ),
        .executableTarget(
            name: "MiracleShotApp",
            dependencies: ["MiracleShotUI", "MiracleShotCore"]
        ),
        .testTarget(
            name: "MiracleShotCoreTests",
            dependencies: ["MiracleShotCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "MiracleShotAppTests",
            dependencies: ["MiracleShotUI", "MiracleShotCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

**Step 2: Write placeholder sources**

`Sources/MiracleShotCore/Core.swift`:
```swift
/// Namespace marker for the Core module. Real types live in their own files.
public enum MiracleShotCore {
    public static let version = "0.1.0"
}
```

`Sources/MiracleShotUI/UI.swift`:
```swift
import AppKit
import MiracleShotCore

/// Namespace marker for the UI module.
public enum MiracleShotUI {
    public static let coreVersion = MiracleShotCore.version
}
```

`Sources/MiracleShotApp/main.swift`:
```swift
import AppKit
import MiracleShotUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "MS"
let menu = NSMenu()
menu.addItem(withTitle: "Quit Miracle Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
statusItem.menu = menu
app.run()
```

Create the three `.gitkeep` files so the resource and fixture directories exist:
```bash
mkdir -p Sources/MiracleShotCore/Resources/presets Sources/MiracleShotUI/Resources/fonts Tests/MiracleShotCoreTests/Fixtures/scroll
touch Sources/MiracleShotCore/Resources/presets/.gitkeep Sources/MiracleShotUI/Resources/fonts/.gitkeep Tests/MiracleShotCoreTests/Fixtures/scroll/.gitkeep
```

**Step 3: Write smoke tests**

`Tests/MiracleShotCoreTests/CoreSmokeTests.swift`:
```swift
import XCTest
@testable import MiracleShotCore

final class CoreSmokeTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(MiracleShotCore.version.isEmpty)
    }
}
```

`Tests/MiracleShotAppTests/AppSmokeTests.swift`:
```swift
import XCTest
@testable import MiracleShotUI

final class AppSmokeTests: XCTestCase {
    func testUIModuleLinksAgainstCore() {
        XCTAssertEqual(MiracleShotUI.coreVersion, "0.1.0")
    }
}
```

**Step 4: Run tests**

Run: `swift test`
Expected: both test targets build, 2 tests pass. If `swift test` reports `no such module 'XCTest'`, Xcode is not the active developer directory: run `sudo xcode-select -s /Applications/Xcode.app` and `sudo xcodebuild -license accept`, then retry.

**Step 5: Write `scripts/build-app.sh`**

```bash
#!/bin/bash
# Builds "Miracle Shot.app" from the SwiftPM executable with a stable ad-hoc signature,
# so the Screen Recording permission survives rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Miracle Shot"
BUNDLE_ID="agency.blackbloom.miracleshot"
OUT="build/$APP_NAME.app"

swift build -c release --product MiracleShot
BIN="$(swift build -c release --show-bin-path)/MiracleShot"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/MiracleShot"

# SwiftPM resource bundles sit next to the binary; copy them into Resources.
for bundle in "$(dirname "$BIN")"/MiracleShot_*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$OUT/Contents/Resources/"
done

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>MiracleShot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Miracle Shot needs screen recording access to take screenshots.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier "$BUNDLE_ID" "$OUT"
echo "Built $OUT"
if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$OUT" /Applications/
  echo "Installed to /Applications/$APP_NAME.app"
fi
```

Run: `chmod +x scripts/build-app.sh && scripts/build-app.sh`
Expected: `Built build/Miracle Shot.app`. Then `open "build/Miracle Shot.app"` shows "MS" in the menu bar with a Quit item. Quit it.

**Step 6: Update `.gitignore`**

Append:
```
build/
.build/
.swiftpm/
*.xcodeproj
.DS_Store
```
(Some lines already exist; keep the file deduplicated.)

**Step 7: Commit**

```bash
git add -A
git commit -m "Scaffold SwiftPM package with Core, UI, App and test targets"
```

---

### Task 2: CaptureState machine and Capture model

**Files:**
- Create: `Sources/MiracleShotCore/Capture/Capture.swift`
- Create: `Sources/MiracleShotCore/Capture/CaptureState.swift`
- Test: `Tests/MiracleShotCoreTests/CaptureStateTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import MiracleShotCore

final class CaptureStateTests: XCTestCase {
    func testHotkeyFromIdleStartsSelection() {
        XCTAssertEqual(CaptureStateMachine.reduce(.idle, .hotkey(.area)), .selecting(.area))
        XCTAssertEqual(CaptureStateMachine.reduce(.idle, .hotkey(.window)), .selecting(.window))
    }

    func testFullScreenHotkeySkipsSelection() {
        XCTAssertEqual(CaptureStateMachine.reduce(.idle, .hotkey(.fullScreen)), .capturing)
    }

    func testHotkeyWhileSelectingIsIgnored() {
        XCTAssertEqual(CaptureStateMachine.reduce(.selecting(.area), .hotkey(.window)), .selecting(.area))
    }

    func testHotkeyWhileCapturingIsIgnored() {
        XCTAssertEqual(CaptureStateMachine.reduce(.capturing, .hotkey(.area)), .capturing)
    }

    func testEscapeCancelsSelection() {
        XCTAssertEqual(CaptureStateMachine.reduce(.selecting(.window), .selectionCancelled), .idle)
    }

    func testSelectionMadeStartsCapture() {
        XCTAssertEqual(CaptureStateMachine.reduce(.selecting(.area), .selectionMade), .capturing)
    }

    func testCaptureOutcomes() {
        XCTAssertEqual(CaptureStateMachine.reduce(.capturing, .captureSucceeded), .previewing)
        XCTAssertEqual(CaptureStateMachine.reduce(.capturing, .captureFailed), .idle)
    }

    func testPreviewDismissReturnsToIdle() {
        XCTAssertEqual(CaptureStateMachine.reduce(.previewing, .previewDismissed), .idle)
    }

    func testHotkeyWhilePreviewingStartsNewCapture() {
        XCTAssertEqual(CaptureStateMachine.reduce(.previewing, .hotkey(.area)), .selecting(.area))
        XCTAssertEqual(CaptureStateMachine.reduce(.previewing, .hotkey(.fullScreen)), .capturing)
    }

    func testIrrelevantEventsLeaveStateUnchanged() {
        XCTAssertEqual(CaptureStateMachine.reduce(.idle, .selectionMade), .idle)
        XCTAssertEqual(CaptureStateMachine.reduce(.idle, .captureSucceeded), .idle)
        XCTAssertEqual(CaptureStateMachine.reduce(.selecting(.area), .captureFailed), .selecting(.area))
        XCTAssertEqual(CaptureStateMachine.reduce(.previewing, .selectionCancelled), .previewing)
    }

    func testCanStartCaptureOnlyFromIdleOrPreviewing() {
        XCTAssertTrue(CaptureState.idle.canStartCapture)
        XCTAssertTrue(CaptureState.previewing.canStartCapture)
        XCTAssertFalse(CaptureState.selecting(.area).canStartCapture)
        XCTAssertFalse(CaptureState.capturing.canStartCapture)
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter CaptureStateTests`
Expected: compile error `cannot find 'CaptureStateMachine' in scope`.

**Step 3: Implement**

`Sources/MiracleShotCore/Capture/Capture.swift`:
```swift
import CoreGraphics
import Foundation

/// What the user asked to capture.
public enum CaptureMode: Sendable, Equatable, Hashable {
    case area
    case window
    case fullScreen
}

/// A finished screenshot plus the metadata the rest of the app needs.
public struct Capture: Sendable {
    public let image: CGImage
    public let timestamp: Date
    public let sourceAppName: String?
    public let sourceWindowTitle: String?
    /// Global rect in CoreGraphics coordinates (origin top-left of the primary display), in points.
    public let bounds: CGRect
    public let scaleFactor: CGFloat

    public init(image: CGImage, timestamp: Date = Date(), sourceAppName: String? = nil,
                sourceWindowTitle: String? = nil, bounds: CGRect, scaleFactor: CGFloat) {
        self.image = image
        self.timestamp = timestamp
        self.sourceAppName = sourceAppName
        self.sourceWindowTitle = sourceWindowTitle
        self.bounds = bounds
        self.scaleFactor = scaleFactor
    }

    public var pixelWidth: Int { image.width }
    public var pixelHeight: Int { image.height }
}
```

`Sources/MiracleShotCore/Capture/CaptureState.swift`:
```swift
/// Events that drive the capture flow. Produced by hotkeys, the selection overlay, the capture service and the preview.
public enum CaptureEvent: Sendable, Equatable {
    case hotkey(CaptureMode)
    case selectionCancelled
    case selectionMade
    case captureSucceeded
    case captureFailed
    case previewDismissed
}

public enum CaptureState: Sendable, Equatable {
    case idle
    case selecting(CaptureMode)
    case capturing
    case previewing

    /// A new capture may only start when nothing is in flight. Previewing counts as free.
    public var canStartCapture: Bool {
        switch self {
        case .idle, .previewing: return true
        case .selecting, .capturing: return false
        }
    }
}

/// Pure transition table. Unknown combinations leave the state untouched.
public enum CaptureStateMachine {
    public static func reduce(_ state: CaptureState, _ event: CaptureEvent) -> CaptureState {
        switch (state, event) {
        case (.idle, .hotkey(let mode)), (.previewing, .hotkey(let mode)):
            return mode == .fullScreen ? .capturing : .selecting(mode)
        case (.selecting, .selectionCancelled):
            return .idle
        case (.selecting, .selectionMade):
            return .capturing
        case (.capturing, .captureSucceeded):
            return .previewing
        case (.capturing, .captureFailed):
            return .idle
        case (.previewing, .previewDismissed):
            return .idle
        default:
            return state
        }
    }
}
```

**Step 4: Run to verify it passes**

Run: `swift test --filter CaptureStateTests`
Expected: 11 tests pass.

**Step 5: Commit**

```bash
git add Sources/MiracleShotCore/Capture Tests/MiracleShotCoreTests/CaptureStateTests.swift
git commit -m "Add capture state machine and Capture model"
```

---

### Task 3: NamingTemplate

**Files:**
- Create: `Sources/MiracleShotCore/Storage/NamingTemplate.swift`
- Test: `Tests/MiracleShotCoreTests/NamingTemplateTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import MiracleShotCore

final class NamingTemplateTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // 2026-09-14 14:05:09 UTC
    private let date = Date(timeIntervalSince1970: 1_789_394_709)

    func testDefaultPattern() {
        let name = NamingTemplate.default.fileName(date: date, appName: "Safari", sequence: 1, timeZone: utc)
        XCTAssertEqual(name, "Miracle Shot 2026-09-14 at 14.05.09.png")
    }

    func testAllTokens() {
        let t = NamingTemplate(pattern: "{app}_{date}_{time}_{seq}")
        XCTAssertEqual(t.fileName(date: date, appName: "Safari", sequence: 7, timeZone: utc),
                       "Safari_2026-09-14_14.05.09_7.png")
    }

    func testMissingAppFallsBackToScreen() {
        let t = NamingTemplate(pattern: "{app}")
        XCTAssertEqual(t.fileName(date: date, appName: nil, sequence: 1, timeZone: utc), "Screen.png")
    }

    func testUnsafeCharactersAreReplaced() {
        let t = NamingTemplate(pattern: "{app}")
        XCTAssertEqual(t.fileName(date: date, appName: "Google/Chrome: Beta", sequence: 1, timeZone: utc),
                       "Google-Chrome- Beta.png")
    }

    func testEmptyPatternUsesDefault() {
        let t = NamingTemplate(pattern: "   ")
        XCTAssertEqual(t.fileName(date: date, appName: nil, sequence: 1, timeZone: utc),
                       NamingTemplate.default.fileName(date: date, appName: nil, sequence: 1, timeZone: utc))
    }

    func testCustomExtension() {
        let t = NamingTemplate(pattern: "x")
        XCTAssertEqual(t.fileName(date: date, appName: nil, sequence: 1, fileExtension: "jpg", timeZone: utc), "x.jpg")
    }

    func testVeryLongNameIsTruncated() {
        let t = NamingTemplate(pattern: String(repeating: "a", count: 400))
        let name = t.fileName(date: date, appName: nil, sequence: 1, timeZone: utc)
        XCTAssertLessThanOrEqual(name.count, 200 + ".png".count)
    }

    func testCodableRoundTrip() throws {
        let t = NamingTemplate(pattern: "{date}-{seq}")
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(NamingTemplate.self, from: data), t)
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter NamingTemplateTests`
Expected: compile error `cannot find 'NamingTemplate' in scope`.

**Step 3: Implement**

`Sources/MiracleShotCore/Storage/NamingTemplate.swift`:
```swift
import Foundation

/// File name pattern with `{date}`, `{time}`, `{app}` and `{seq}` tokens.
public struct NamingTemplate: Sendable, Equatable, Codable {
    public static let `default` = NamingTemplate(pattern: "Miracle Shot {date} at {time}")
    public static let maxBaseNameLength = 200

    public var pattern: String

    public init(pattern: String) {
        self.pattern = pattern
    }

    public func fileName(date: Date, appName: String?, sequence: Int,
                         fileExtension: String = "png", timeZone: TimeZone = .current) -> String {
        let effective = pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.default.pattern : pattern
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH.mm.ss"

        var name = effective
            .replacingOccurrences(of: "{date}", with: dateFormatter.string(from: date))
            .replacingOccurrences(of: "{time}", with: timeFormatter.string(from: date))
            .replacingOccurrences(of: "{app}", with: Self.sanitize(appName ?? "") .isEmpty ? "Screen" : Self.sanitize(appName ?? ""))
            .replacingOccurrences(of: "{seq}", with: String(sequence))
        name = Self.sanitize(name)
        if name.count > Self.maxBaseNameLength {
            name = String(name.prefix(Self.maxBaseNameLength))
        }
        return "\(name).\(fileExtension)"
    }

    /// Replaces path separators and colons, which Finder cannot display, with dashes.
    static func sanitize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Step 4: Run to verify it passes**

Run: `swift test --filter NamingTemplateTests`
Expected: 8 tests pass.

**Step 5: Commit**

```bash
git add Sources/MiracleShotCore/Storage/NamingTemplate.swift Tests/MiracleShotCoreTests/NamingTemplateTests.swift
git commit -m "Add NamingTemplate with date, time, app and seq tokens"
```

---

### Task 4: SelectionGeometry

All geometry is in **CoreGraphics global coordinates**: origin at the top-left of the primary display, y grows downward. That is what `CGWindowListCopyWindowInfo` and ScreenCaptureKit use. AppKit panels convert at the edge with `flipped(_:primaryScreenHeight:)`.

**Files:**
- Create: `Sources/MiracleShotCore/Selection/WindowInfo.swift`
- Create: `Sources/MiracleShotCore/Selection/SelectionGeometry.swift`
- Test: `Tests/MiracleShotCoreTests/SelectionGeometryTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import MiracleShotCore

final class SelectionGeometryTests: XCTestCase {
    private func win(_ id: UInt32, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     layer: Int = 0, pid: Int32 = 100) -> WindowInfo {
        WindowInfo(id: id, frame: CGRect(x: x, y: y, width: w, height: h), layer: layer,
                   ownerName: "App\(id)", ownerPID: pid, title: nil)
    }

    // MARK: rect(from:to:)

    func testRectNormalizesAnyDragDirection() {
        let expected = CGRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(SelectionGeometry.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 40, y: 60)), expected)
        XCTAssertEqual(SelectionGeometry.rect(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 10, y: 20)), expected)
        XCTAssertEqual(SelectionGeometry.rect(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 10, y: 60)), expected)
    }

    func testIsClickWithinTolerance() {
        XCTAssertTrue(SelectionGeometry.isClick(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 2, y: 2)))
        XCTAssertFalse(SelectionGeometry.isClick(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 4, y: 0)))
    }

    // MARK: window(at:)

    func testFrontmostWindowWins() {
        let front = win(1, 0, 0, 100, 100)
        let back = win(2, 0, 0, 200, 200)
        XCTAssertEqual(SelectionGeometry.window(at: CGPoint(x: 50, y: 50), in: [front, back]), front)
        XCTAssertEqual(SelectionGeometry.window(at: CGPoint(x: 150, y: 150), in: [front, back]), back)
    }

    func testNonZeroLayerWindowsAreIgnored() {
        let menuBar = win(1, 0, 0, 1000, 24, layer: 25)
        let normal = win(2, 0, 0, 1000, 500)
        XCTAssertEqual(SelectionGeometry.window(at: CGPoint(x: 10, y: 10), in: [menuBar, normal]), normal)
    }

    func testOwnPIDIsExcluded() {
        let overlay = win(1, 0, 0, 1000, 1000, pid: 42)
        let normal = win(2, 0, 0, 500, 500, pid: 7)
        XCTAssertEqual(SelectionGeometry.window(at: CGPoint(x: 10, y: 10), in: [overlay, normal], excludingPID: 42), normal)
    }

    func testNoWindowUnderPoint() {
        XCTAssertNil(SelectionGeometry.window(at: CGPoint(x: 999, y: 999), in: [win(1, 0, 0, 10, 10)]))
    }

    // MARK: snapped

    func testEdgesSnapWithinThreshold() {
        let w = win(1, 100, 100, 300, 200)   // edges x: 100/400, y: 100/300
        let rect = CGRect(x: 105, y: 96, width: 290, height: 210)   // edges 105/395, 96/306
        let snapped = SelectionGeometry.snapped(rect, to: [w], threshold: 8)
        XCTAssertEqual(snapped, CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    func testEdgesBeyondThresholdDoNotSnap() {
        let w = win(1, 100, 100, 300, 200)
        let rect = CGRect(x: 120, y: 120, width: 100, height: 100)
        XCTAssertEqual(SelectionGeometry.snapped(rect, to: [w], threshold: 8), rect)
    }

    func testSnapPicksNearestEdge() {
        let a = win(1, 0, 0, 100, 100)     // maxX = 100
        let b = win(2, 103, 0, 100, 100)   // minX = 103
        let rect = CGRect(x: 102, y: 50, width: 20, height: 10)
        XCTAssertEqual(SelectionGeometry.snapped(rect, to: [a, b], threshold: 8).minX, 103)
    }

    // MARK: magnifier

    func testMagnifierSitsBottomRightOfCursor() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = SelectionGeometry.magnifierFrame(cursor: CGPoint(x: 100, y: 100), size: 120, offset: 20, in: screen)
        XCTAssertEqual(f, CGRect(x: 120, y: 120, width: 120, height: 120))
    }

    func testMagnifierFlipsNearRightAndBottomEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = SelectionGeometry.magnifierFrame(cursor: CGPoint(x: 950, y: 750), size: 120, offset: 20, in: screen)
        XCTAssertEqual(f, CGRect(x: 950 - 20 - 120, y: 750 - 20 - 120, width: 120, height: 120))
    }

    // MARK: pixel alignment and flipping

    func testPixelAlignedRoundsToDevicePixels() {
        let r = SelectionGeometry.pixelAligned(CGRect(x: 10.3, y: 10.7, width: 20.2, height: 20.6), scale: 2)
        XCTAssertEqual(r, CGRect(x: 10.5, y: 10.5, width: 20, height: 20.5))
    }

    func testFlippedIsAnInvolution() {
        let r = CGRect(x: 10, y: 20, width: 100, height: 50)
        let once = SelectionGeometry.flipped(r, primaryScreenHeight: 800)
        XCTAssertEqual(once, CGRect(x: 10, y: 730, width: 100, height: 50))
        XCTAssertEqual(SelectionGeometry.flipped(once, primaryScreenHeight: 800), r)
        XCTAssertEqual(SelectionGeometry.flipped(CGPoint(x: 5, y: 100), primaryScreenHeight: 800), CGPoint(x: 5, y: 700))
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter SelectionGeometryTests`
Expected: compile error `cannot find 'WindowInfo' in scope`.

**Step 3: Implement**

`Sources/MiracleShotCore/Selection/WindowInfo.swift`:
```swift
import CoreGraphics

/// Snapshot of an on-screen window as reported by the window server. Frame is in CG global coordinates.
public struct WindowInfo: Sendable, Equatable, Hashable {
    public let id: UInt32
    public let frame: CGRect
    public let layer: Int
    public let ownerName: String
    public let ownerPID: Int32
    public let title: String?

    public init(id: UInt32, frame: CGRect, layer: Int, ownerName: String, ownerPID: Int32, title: String?) {
        self.id = id
        self.frame = frame
        self.layer = layer
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.title = title
    }
}
```

`Sources/MiracleShotCore/Selection/SelectionGeometry.swift`:
```swift
import CoreGraphics

/// Pure geometry for the selection overlay. CG global coordinates, origin top-left, y down.
public enum SelectionGeometry {
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    public static func isClick(from a: CGPoint, to b: CGPoint, tolerance: CGFloat = 3) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    /// `windows` must be ordered front-to-back, as `CGWindowListCopyWindowInfo` returns them.
    public static func window(at point: CGPoint, in windows: [WindowInfo], excludingPID: Int32? = nil) -> WindowInfo? {
        windows.first { w in
            w.layer == 0 && w.ownerPID != excludingPID && w.frame.contains(point)
        }
    }

    public static func snapped(_ rect: CGRect, to windows: [WindowInfo], threshold: CGFloat) -> CGRect {
        let xs = windows.flatMap { [$0.frame.minX, $0.frame.maxX] }
        let ys = windows.flatMap { [$0.frame.minY, $0.frame.maxY] }
        let minX = nearest(to: rect.minX, in: xs, threshold: threshold)
        let maxX = nearest(to: rect.maxX, in: xs, threshold: threshold)
        let minY = nearest(to: rect.minY, in: ys, threshold: threshold)
        let maxY = nearest(to: rect.maxY, in: ys, threshold: threshold)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func nearest(to value: CGFloat, in candidates: [CGFloat], threshold: CGFloat) -> CGFloat {
        guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(best - value) <= threshold else { return value }
        return best
    }

    public static func magnifierFrame(cursor: CGPoint, size: CGFloat, offset: CGFloat, in screen: CGRect) -> CGRect {
        var x = cursor.x + offset
        var y = cursor.y + offset
        if x + size > screen.maxX { x = cursor.x - offset - size }
        if y + size > screen.maxY { y = cursor.y - offset - size }
        return CGRect(x: x, y: y, width: size, height: size)
    }

    public static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        func r(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        return CGRect(x: r(rect.minX), y: r(rect.minY), width: r(rect.width), height: r(rect.height))
    }

    /// AppKit <-> CoreGraphics global coordinate flip. Applying it twice returns the input.
    public static func flipped(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    public static func flipped(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}
```

**Step 4: Run to verify it passes**

Run: `swift test --filter SelectionGeometryTests`
Expected: 13 tests pass.

**Step 5: Commit**

```bash
git add Sources/MiracleShotCore/Selection Tests/MiracleShotCoreTests/SelectionGeometryTests.swift
git commit -m "Add SelectionGeometry: window hit-test, snapping, magnifier, flips"
```

---

### Task 5: PreviewTiming

**Files:**
- Create: `Sources/MiracleShotCore/Preview/PreviewTiming.swift`
- Test: `Tests/MiracleShotCoreTests/PreviewTimingTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import MiracleShotCore

final class PreviewTimingTests: XCTestCase {
    func testStartsRunningWithFullDuration() {
        let t = PreviewTiming(duration: 6, now: 100)
        XCTAssertEqual(t.phase, .running(deadline: 106))
        XCTAssertEqual(t.remaining(now: 102), 4)
    }

    func testTickBeforeDeadlineDoesNothing() {
        var t = PreviewTiming(duration: 6, now: 100)
        XCTAssertFalse(t.tick(now: 105.9))
        XCTAssertEqual(t.phase, .running(deadline: 106))
    }

    func testTickAtDeadlineExpiresOnce() {
        var t = PreviewTiming(duration: 6, now: 100)
        XCTAssertTrue(t.tick(now: 106))
        XCTAssertEqual(t.phase, .expired)
        XCTAssertFalse(t.tick(now: 200))
    }

    func testHoverPausesAndResumesWithRemainingTime() {
        var t = PreviewTiming(duration: 6, now: 100)
        t.hoverBegan(now: 104)
        XCTAssertEqual(t.phase, .paused(remaining: 2))
        XCTAssertFalse(t.tick(now: 500))
        t.hoverEnded(now: 500)
        XCTAssertEqual(t.phase, .running(deadline: 502))
        XCTAssertTrue(t.tick(now: 502))
    }

    func testHoverAfterExpiryIsNoop() {
        var t = PreviewTiming(duration: 1, now: 0)
        _ = t.tick(now: 1)
        t.hoverBegan(now: 2)
        XCTAssertEqual(t.phase, .expired)
    }

    func testRemainingNeverNegative() {
        let t = PreviewTiming(duration: 1, now: 0)
        XCTAssertEqual(t.remaining(now: 50), 0)
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter PreviewTimingTests`
Expected: compile error `cannot find 'PreviewTiming' in scope`.

**Step 3: Implement**

`Sources/MiracleShotCore/Preview/PreviewTiming.swift`:
```swift
import Foundation

/// Auto-dismiss timer state for the floating preview. Hover pauses it, leaving resumes it.
/// Time is injected as `TimeInterval` so the logic is testable without clocks.
public struct PreviewTiming: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case running(deadline: TimeInterval)
        case paused(remaining: TimeInterval)
        case expired
    }

    public let duration: TimeInterval
    public private(set) var phase: Phase

    public init(duration: TimeInterval, now: TimeInterval) {
        self.duration = duration
        self.phase = .running(deadline: now + duration)
    }

    public func remaining(now: TimeInterval) -> TimeInterval {
        switch phase {
        case .running(let deadline): return max(0, deadline - now)
        case .paused(let remaining): return remaining
        case .expired: return 0
        }
    }

    public mutating func hoverBegan(now: TimeInterval) {
        if case .running(let deadline) = phase {
            phase = .paused(remaining: max(0, deadline - now))
        }
    }

    public mutating func hoverEnded(now: TimeInterval) {
        if case .paused(let remaining) = phase {
            phase = .running(deadline: now + remaining)
        }
    }

    /// Returns true exactly once, when the deadline is reached.
    public mutating func tick(now: TimeInterval) -> Bool {
        guard case .running(let deadline) = phase, now >= deadline else { return false }
        phase = .expired
        return true
    }
}
```

**Step 4: Run to verify it passes**

Run: `swift test --filter PreviewTimingTests`
Expected: 6 tests pass.

**Step 5: Commit**

```bash
git add Sources/MiracleShotCore/Preview Tests/MiracleShotCoreTests/PreviewTimingTests.swift
git commit -m "Add PreviewTiming with hover pause"
```

---

### Task 6: JSONStore and HistoryIndex

**Files:**
- Create: `Sources/MiracleShotCore/Storage/JSONStore.swift`
- Create: `Sources/MiracleShotCore/Storage/HistoryIndex.swift`
- Test: `Tests/MiracleShotCoreTests/JSONStoreTests.swift`
- Test: `Tests/MiracleShotCoreTests/HistoryIndexTests.swift`

**Step 1: Write the failing tests**

`Tests/MiracleShotCoreTests/JSONStoreTests.swift`:
```swift
import XCTest
@testable import MiracleShotCore

final class JSONStoreTests: XCTestCase {
    private struct Doc: Codable, Equatable { var name: String; var when: Date }
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileLoadsNil() {
        XCTAssertNil(JSONStore.load(Doc.self, from: dir.appendingPathComponent("x.json")))
    }

    func testRoundTripCreatesDirectories() throws {
        let url = dir.appendingPathComponent("nested/doc.json")
        let doc = Doc(name: "a", when: Date(timeIntervalSince1970: 1_000_000))
        try JSONStore.save(doc, to: url)
        XCTAssertEqual(JSONStore.load(Doc.self, from: url), doc)
    }

    func testCorruptFileIsRenamedToBrokenAndLoadsNil() throws {
        let url = dir.appendingPathComponent("doc.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        XCTAssertNil(JSONStore.load(Doc.self, from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("doc.json.broken").path))
    }

    func testSecondCorruptFileReplacesOldBroken() throws {
        let url = dir.appendingPathComponent("doc.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("bad1".utf8).write(to: url)
        _ = JSONStore.load(Doc.self, from: url)
        try Data("bad2".utf8).write(to: url)
        _ = JSONStore.load(Doc.self, from: url)
        let broken = try String(contentsOf: dir.appendingPathComponent("doc.json.broken"), encoding: .utf8)
        XCTAssertEqual(broken, "bad2")
    }
}
```

`Tests/MiracleShotCoreTests/HistoryIndexTests.swift`:
```swift
import XCTest
@testable import MiracleShotCore

final class HistoryIndexTests: XCTestCase {
    private func entry(_ n: Int) -> HistoryEntry {
        HistoryEntry(id: UUID(), path: "/tmp/\(n).png", date: Date(timeIntervalSince1970: TimeInterval(n)),
                     width: 10, height: 10, sourceApp: nil)
    }

    func testAppendPutsNewestFirst() {
        var index = HistoryIndex(limit: 10)
        index.append(entry(1))
        index.append(entry(2))
        XCTAssertEqual(index.entries.map(\.path), ["/tmp/2.png", "/tmp/1.png"])
    }

    func testAppendTrimsToLimit() {
        var index = HistoryIndex(limit: 2)
        (1...3).forEach { index.append(entry($0)) }
        XCTAssertEqual(index.entries.map(\.path), ["/tmp/3.png", "/tmp/2.png"])
    }

    func testRemoveById() {
        var index = HistoryIndex(limit: 10)
        let e = entry(1)
        index.append(e)
        index.remove(id: e.id)
        XCTAssertTrue(index.entries.isEmpty)
    }

    func testLoadMissingGivesEmptyWithLimit() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let index = HistoryIndex.load(from: url, limit: 7)
        XCTAssertTrue(index.entries.isEmpty)
        XCTAssertEqual(index.limit, 7)
    }

    func testSaveAndLoadRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        var index = HistoryIndex(limit: 5)
        index.append(entry(1))
        try index.save(to: url)
        let loaded = HistoryIndex.load(from: url, limit: 5)
        XCTAssertEqual(loaded, index)
    }

    func testLoadAppliesNewLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        var index = HistoryIndex(limit: 10)
        (1...5).forEach { index.append(entry($0)) }
        try index.save(to: url)
        XCTAssertEqual(HistoryIndex.load(from: url, limit: 2).entries.count, 2)
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter "JSONStoreTests|HistoryIndexTests"`
Expected: compile errors for `JSONStore` and `HistoryIndex`.

**Step 3: Implement**

`Sources/MiracleShotCore/Storage/JSONStore.swift`:
```swift
import Foundation

/// JSON persistence with one rule: a corrupt file is never fatal. It is renamed to `<name>.broken` and treated as missing.
public enum JSONStore {
    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder().decode(T.self, from: data)
        } catch {
            quarantine(url)
            return nil
        }
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private static func quarantine(_ url: URL) {
        let broken = url.appendingPathExtension("broken")
        try? FileManager.default.removeItem(at: broken)
        try? FileManager.default.moveItem(at: url, to: broken)
    }
}
```

`Sources/MiracleShotCore/Storage/HistoryIndex.swift`:
```swift
import Foundation

public struct HistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let path: String
    public let date: Date
    public let width: Int
    public let height: Int
    public let sourceApp: String?

    public init(id: UUID = UUID(), path: String, date: Date, width: Int, height: Int, sourceApp: String?) {
        self.id = id
        self.path = path
        self.date = date
        self.width = width
        self.height = height
        self.sourceApp = sourceApp
    }
}

/// Newest-first list of recent captures, capped at `limit`.
public struct HistoryIndex: Codable, Sendable, Equatable {
    public private(set) var entries: [HistoryEntry]
    public let limit: Int

    public init(limit: Int, entries: [HistoryEntry] = []) {
        self.limit = limit
        self.entries = Array(entries.prefix(limit))
    }

    public mutating func append(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    public mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public static func load(from url: URL, limit: Int) -> HistoryIndex {
        let stored = JSONStore.load(HistoryIndex.self, from: url)
        return HistoryIndex(limit: limit, entries: stored?.entries ?? [])
    }

    public func save(to url: URL) throws {
        try JSONStore.save(self, to: url)
    }
}
```

**Step 4: Run to verify it passes**

Run: `swift test --filter "JSONStoreTests|HistoryIndexTests"`
Expected: 10 tests pass.

**Step 5: Commit**

```bash
git add Sources/MiracleShotCore/Storage/JSONStore.swift Sources/MiracleShotCore/Storage/HistoryIndex.swift Tests/MiracleShotCoreTests/JSONStoreTests.swift Tests/MiracleShotCoreTests/HistoryIndexTests.swift
git commit -m "Add JSONStore with quarantine and HistoryIndex"
```

---

### Task 7: HotkeySpec, KeyCodeMap, CaptureAction and Settings

Depends on Task 6 (`JSONStore`).

**Files:**
- Create: `Sources/MiracleShotCore/Settings/CaptureAction.swift`
- Create: `Sources/MiracleShotCore/Settings/KeyCodeMap.swift`
- Create: `Sources/MiracleShotCore/Settings/HotkeySpec.swift`
- Create: `Sources/MiracleShotCore/Settings/Settings.swift`
- Test: `Tests/MiracleShotCoreTests/HotkeySpecTests.swift`
- Test: `Tests/MiracleShotCoreTests/SettingsTests.swift`

**Step 1: Write the failing tests**

`Tests/MiracleShotCoreTests/HotkeySpecTests.swift`:
```swift
import XCTest
@testable import MiracleShotCore

final class HotkeySpecTests: XCTestCase {
    func testParsesModifiersAndKeyCaseInsensitively() throws {
        let spec = try XCTUnwrap(HotkeySpec(parsing: "Cmd+Shift+4"))
        XCTAssertEqual(spec.key, "4")
        XCTAssertEqual(spec.modifiers, [.command, .shift])
    }

    func testAcceptsAliases() throws {
        let spec = try XCTUnwrap(HotkeySpec(parsing: "control + option + command + a"))
        XCTAssertEqual(spec.modifiers, [.control, .option, .command])
        XCTAssertEqual(spec.key, "a")
    }

    func testDescriptionIsCanonical() throws {
        XCTAssertEqual(HotkeySpec(parsing: "shift+CMD+4")?.description, "shift+cmd+4")
        XCTAssertEqual(HotkeySpec(parsing: "cmd+ctrl+opt+shift+space")?.description, "ctrl+opt+shift+cmd+space")
    }

    func testRejectsUnknownKeyOrMissingKey() {
        XCTAssertNil(HotkeySpec(parsing: "cmd+shift+"))
        XCTAssertNil(HotkeySpec(parsing: "cmd+shift+bogus"))
        XCTAssertNil(HotkeySpec(parsing: ""))
    }

    func testRejectsKeyWithoutModifiers() {
        XCTAssertNil(HotkeySpec(parsing: "4"))
    }

    func testCarbonValues() throws {
        let spec = try XCTUnwrap(HotkeySpec(parsing: "cmd+shift+4"))
        XCTAssertEqual(spec.carbonKeyCode, 21)
        XCTAssertEqual(spec.carbonModifiers, 256 | 512)
        XCTAssertEqual(KeyCodeMap.code(for: "space"), 49)
        XCTAssertEqual(KeyCodeMap.code(for: "f12"), 111)
        XCTAssertNil(KeyCodeMap.code(for: "nope"))
    }

    func testCodableRoundTrip() throws {
        let spec = try XCTUnwrap(HotkeySpec(parsing: "ctrl+shift+w"))
        let data = try JSONEncoder().encode(spec)
        XCTAssertEqual(try JSONDecoder().decode(HotkeySpec.self, from: data), spec)
    }
}
```

`Tests/MiracleShotCoreTests/SettingsTests.swift`:
```swift
import XCTest
@testable import MiracleShotCore

final class SettingsTests: XCTestCase {
    func testDefaultsAreSane() {
        let s = Settings.default
        XCTAssertEqual(s.hotkeys[.captureArea]?.description, "shift+cmd+1")
        XCTAssertEqual(s.hotkeys[.captureWindow]?.description, "shift+cmd+2")
        XCTAssertEqual(s.hotkeys[.captureFullScreen]?.description, "shift+cmd+0")
        XCTAssertEqual(s.previewTimeout, 6)
        XCTAssertEqual(s.historyLimit, 50)
        XCTAssertEqual(s.namingTemplate, .default)
        XCTAssertTrue(s.saveDirectoryURL.path.hasSuffix("/Pictures/Miracle Shot"))
    }

    func testRoundTrip() throws {
        var s = Settings.default
        s.previewTimeout = 3
        s.hotkeys[.captureArea] = HotkeySpec(parsing: "ctrl+opt+s")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try s.save(to: url)
        XCTAssertEqual(Settings.load(from: url), s)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        let data = Data(#"{"previewTimeout": 2}"#.utf8)
        let s = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(s.previewTimeout, 2)
        XCTAssertEqual(s.historyLimit, Settings.default.historyLimit)
        XCTAssertEqual(s.hotkeys, Settings.default.hotkeys)
    }

    func testMissingOrCorruptFileLoadsDefault() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        XCTAssertEqual(Settings.load(from: url), .default)
        try Data("garbage".utf8).write(to: url)
        XCTAssertEqual(Settings.load(from: url), .default)
    }

    func testTildeIsExpandedInSaveDirectory() {
        var s = Settings.default
        s.saveDirectoryPath = "~/Desktop/Shots"
        XCTAssertFalse(s.saveDirectoryURL.path.contains("~"))
        XCTAssertTrue(s.saveDirectoryURL.path.hasSuffix("/Desktop/Shots"))
    }
}
```

**Step 2: Run to verify it fails**

Run: `swift test --filter "HotkeySpecTests|SettingsTests"`
Expected: compile errors for missing types.

**Step 3: Implement**

`Sources/MiracleShotCore/Settings/CaptureAction.swift`:
```swift
/// User-triggerable actions bound to hotkeys. Later phases append cases; never reorder or rename existing ones,
/// the raw values are persisted in settings.json.
public enum CaptureAction: String, Codable, Sendable, CaseIterable, Hashable {
    case captureArea
    case captureWindow
    case captureFullScreen

    public var captureMode: CaptureMode {
        switch self {
        case .captureArea: return .area
        case .captureWindow: return .window
        case .captureFullScreen: return .fullScreen
        }
    }

    public var title: String {
        switch self {
        case .captureArea: return "Capture Area"
        case .captureWindow: return "Capture Window"
        case .captureFullScreen: return "Capture Full Screen"
        }
    }
}
```

`Sources/MiracleShotCore/Settings/KeyCodeMap.swift`:
```swift
/// Carbon virtual key codes for the US ANSI layout. Only the key names users are allowed to type in settings.
public enum KeyCodeMap {
    private static let codes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51,
        "escape": 53, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "forwarddelete": 117,
    ]

    public static func code(for key: String) -> UInt32? {
        codes[key.lowercased()]
    }
}
```

`Sources/MiracleShotCore/Settings/HotkeySpec.swift`:
```swift
/// A global hotkey such as `shift+cmd+4`. Parsed from and rendered to a canonical string.
public struct HotkeySpec: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    public enum Modifier: String, Codable, Sendable, CaseIterable, Hashable {
        case control, option, shift, command

        /// Carbon `controlKey`, `optionKey`, `shiftKey`, `cmdKey` bit masks.
        var carbonFlag: UInt32 {
            switch self {
            case .command: return 1 << 8
            case .shift: return 1 << 9
            case .option: return 1 << 11
            case .control: return 1 << 12
            }
        }

        var shortName: String {
            switch self {
            case .control: return "ctrl"
            case .option: return "opt"
            case .shift: return "shift"
            case .command: return "cmd"
            }
        }

        static let aliases: [String: Modifier] = [
            "cmd": .command, "command": .command,
            "shift": .shift,
            "opt": .option, "option": .option, "alt": .option,
            "ctrl": .control, "control": .control,
        ]
    }

    public let key: String
    public let modifiers: Set<Modifier>

    public init?(key: String, modifiers: Set<Modifier>) {
        guard !modifiers.isEmpty, KeyCodeMap.code(for: key) != nil else { return nil }
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    public init?(parsing text: String) {
        let parts = text.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard parts.count >= 2, let key = parts.last, !key.isEmpty else { return nil }
        var mods = Set<Modifier>()
        for part in parts.dropLast() {
            guard let m = Modifier.aliases[part] else { return nil }
            mods.insert(m)
        }
        self.init(key: key, modifiers: mods)
    }

    /// Canonical order: ctrl, opt, shift, cmd, then the key.
    public var description: String {
        (Modifier.allCases.filter { modifiers.contains($0) }.map(\.shortName) + [key]).joined(separator: "+")
    }

    public var carbonKeyCode: UInt32 { KeyCodeMap.code(for: key) ?? 0 }
    public var carbonModifiers: UInt32 { modifiers.reduce(0) { $0 | $1.carbonFlag } }
}
```

`Sources/MiracleShotCore/Settings/Settings.swift`:
```swift
import Foundation

/// Persisted user settings. Every field has a default so older files keep loading when fields are added.
public struct Settings: Codable, Sendable, Equatable {
    public var hotkeys: [CaptureAction: HotkeySpec]
    public var saveDirectoryPath: String
    public var namingTemplate: NamingTemplate
    public var previewTimeout: TimeInterval
    public var historyLimit: Int

    public static let `default` = Settings(
        hotkeys: [
            .captureArea: HotkeySpec(parsing: "shift+cmd+1")!,
            .captureWindow: HotkeySpec(parsing: "shift+cmd+2")!,
            .captureFullScreen: HotkeySpec(parsing: "shift+cmd+0")!,
        ],
        saveDirectoryPath: "~/Pictures/Miracle Shot",
        namingTemplate: .default,
        previewTimeout: 6,
        historyLimit: 50
    )

    public init(hotkeys: [CaptureAction: HotkeySpec], saveDirectoryPath: String, namingTemplate: NamingTemplate,
                previewTimeout: TimeInterval, historyLimit: Int) {
        self.hotkeys = hotkeys
        self.saveDirectoryPath = saveDirectoryPath
        self.namingTemplate = namingTemplate
        self.previewTimeout = previewTimeout
        self.historyLimit = historyLimit
    }

    private enum CodingKeys: String, CodingKey {
        case hotkeys, saveDirectoryPath, namingTemplate, previewTimeout, historyLimit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        hotkeys = try c.decodeIfPresent([CaptureAction: HotkeySpec].self, forKey: .hotkeys) ?? d.hotkeys
        saveDirectoryPath = try c.decodeIfPresent(String.self, forKey: .saveDirectoryPath) ?? d.saveDirectoryPath
        namingTemplate = try c.decodeIfPresent(NamingTemplate.self, forKey: .namingTemplate) ?? d.namingTemplate
        previewTimeout = try c.decodeIfPresent(TimeInterval.self, forKey: .previewTimeout) ?? d.previewTimeout
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? d.historyLimit
    }

    // MARK: Locations

    public static let supportDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Miracle Shot", isDirectory: true)
    public static let settingsURL = supportDirectory.appendingPathComponent("settings.json")
    public static let historyURL = supportDirectory.appendingPathComponent("history.json")
    public static let fallbackSaveDirectory: URL = FileManager.default
        .urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Miracle Shot", isDirectory: true)

    public var saveDirectoryURL: URL {
        URL(fileURLWithPath: (saveDirectoryPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    // MARK: Persistence

    public static func load(from url: URL = settingsURL) -> Settings {
        JSONStore.load(Settings.self, from: url) ?? .default
    }

    public func save(to url: URL = Settings.settingsURL) throws {
        try JSONStore.save(self, to: url)
    }
}
```

**Step 4: Run to verify it passes**

Run: `swift test --filter "HotkeySpecTests|SettingsTests"`
Expected: 12 tests pass.

**Step 5: Commit**

```bash
git add Sources/MiracleShotCore/Settings Tests/MiracleShotCoreTests/HotkeySpecTests.swift Tests/MiracleShotCoreTests/SettingsTests.swift
git commit -m "Add HotkeySpec, KeyCodeMap, CaptureAction and Settings"
```

---

### Task 8: BrandPalette, ImageCodec and test image helpers

**Files:**
- Create: `Sources/MiracleShotCore/Brand/BrandPalette.swift`
- Create: `Sources/MiracleShotCore/Imaging/ImageCodec.swift`
- Create: `Tests/MiracleShotCoreTests/Helpers/TestImages.swift`
- Test: `Tests/MiracleShotCoreTests/BrandPaletteTests.swift`
- Test: `Tests/MiracleShotCoreTests/ImageCodecTests.swift`

**Step 1: Write the test helper**

`Tests/MiracleShotCoreTests/Helpers/TestImages.swift` (no `@testable` needed; pure CoreGraphics):
```swift
import CoreGraphics
import Foundation

enum TestImages {
    struct RGBA: Equatable { var r: UInt8; var g: UInt8; var b: UInt8; var a: UInt8 }

    /// Solid-color image, premultiplied RGBA8, sRGB.
    static func solid(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) -> CGImage {
        let ctx = context(width: width, height: height)
        ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Reads one pixel. `y` counts from the top, like screen coordinates. (Implementation on the branch also un-premultiplies alpha.)
    static func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        let ctx = context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let row = y   // CGBitmapContext buffers are top-down: row 0 is the top scanline
        let i = row * ctx.bytesPerRow + x * 4
        return RGBA(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3])
    }

    static func assertClose(_ p: RGBA, _ q: RGBA, tolerance: Int = 2, file: StaticString = #filePath, line: UInt = #line) {
        let ok = abs(Int(p.r) - Int(q.r)) <= tolerance && abs(Int(p.g) - Int(q.g)) <= tolerance
            && abs(Int(p.b) - Int(q.b)) <= tolerance && abs(Int(p.a) - Int(q.a)) <= tolerance
        if !ok { XCTFail("\(p) is not within \(tolerance) of \(q)", file: file, line: line) }
    }
}
```
Add `import XCTest` at the top of that file (needed for `XCTFail`).

**Step 2: Write the failing tests**

`Tests/MiracleShotCoreTests/BrandPaletteTests.swift`:
```swift
import XCTest
@testable import MiracleShotCore

final class BrandPaletteTests: XCTestCase {
    func testHexParsing() throws {
        let c = try XCTUnwrap(BrandColor(hex: "#d4ff3f"))
        XCTAssertEqual(c.red, 0xd4 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.green, 1.0, accuracy: 0.001)
        XCTAssertEqual(c.blue, 0x3f / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.hex, "#d4ff3f")
    }

    func testHexRejectsGarbage() {
        XCTAssertNil(BrandColor(hex: "d4ff3"))
        XCTAssertNil(BrandColor(hex: "#zzzzzz"))
    }

    func testTokensMatchAgenticLab() {
        XCTAssertEqual(BrandPalette.ink.hex, "#0b0b0c")
        XCTAssertEqual(BrandPalette.ink2.hex, "#141416")
        XCTAssertEqual(BrandPalette.ink3.hex, "#1c1c1f")
        XCTAssertEqual(BrandPalette.bone.hex, "#f3f0e8")
        XCTAssertEqual(BrandPalette.boneDim.hex, "#b8b4a8")
        XCTAssertEqual(BrandPalette.boneFaint.hex, "#6f6c63")
        XCTAssertEqual(BrandPalette.lime.hex, "#d4ff3f")
        XCTAssertEqual(BrandPalette.limeDim.hex, "#9bbf2a")
        XCTAssertEqual(BrandPalette.coral.hex, "#ff5a36")
        XCTAssertEqual(BrandPalette.line.hex, "#2a2a2d")
    }

    func testCGColorIsSRGBWithAlpha() {
        let cg = BrandPalette.lime.cgColor(alpha: 0.5)
        XCTAssertEqual(cg.alpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(cg.numberOfComponents, 4)
    }
}
```

`Tests/MiracleShotCoreTests/ImageCodecTests.swift`:
```swift
import XCTest
@testable import MiracleShotCore

final class ImageCodecTests: XCTestCase {
    func testPNGRoundTripKeepsPixels() throws {
        let image = TestImages.solid(width: 4, height: 3, r: 1, g: 0, b: 0)
        let data = try XCTUnwrap(ImageCodec.pngData(from: image))
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let decoded = try XCTUnwrap(ImageCodec.image(from: data))
        XCTAssertEqual(decoded.width, 4)
        XCTAssertEqual(decoded.height, 3)
        TestImages.assertClose(TestImages.pixel(decoded, x: 1, y: 1), .init(r: 255, g: 0, b: 0, a: 255))
    }

    func testWritePNGCreatesFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try ImageCodec.writePNG(TestImages.solid(width: 2, height: 2, r: 0, g: 1, b: 0), to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testGarbageDataDecodesToNil() {
        XCTAssertNil(ImageCodec.image(from: Data("nope".utf8)))
    }
}
```

**Step 3: Run to verify it fails**

Run: `swift test --filter "BrandPaletteTests|ImageCodecTests"`
Expected: compile errors for `BrandColor`, `BrandPalette`, `ImageCodec`.

**Step 4: Implement**

`Sources/MiracleShotCore/Brand/BrandPalette.swift`:
```swift
import CoreGraphics

/// sRGB color with 0...1 components. The only place hex literals are allowed is `BrandPalette`.
public struct BrandColor: Sendable, Equatable, Hashable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255)
    }

    public var hex: String {
        String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    public func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, alpha])!
    }
}

/// Agentic Lab design tokens. Source of truth: ~/.claude/scripts/lab-brand.py.
public enum BrandPalette {
    /// Panel and frame background.
    public static let ink = BrandColor(hex: "#0b0b0c")!
    /// Raised plate, inset.
    public static let ink2 = BrandColor(hex: "#141416")!
    /// Nested block, code field.
    public static let ink3 = BrandColor(hex: "#1c1c1f")!
    /// Primary text.
    public static let bone = BrandColor(hex: "#f3f0e8")!
    /// Secondary text.
    public static let boneDim = BrandColor(hex: "#b8b4a8")!
    /// Service captions.
    public static let boneFaint = BrandColor(hex: "#6f6c63")!
    /// The accent. Exactly one place per screen.
    public static let lime = BrandColor(hex: "#d4ff3f")!
    /// Muted accent, "was" state.
    public static let limeDim = BrandColor(hex: "#9bbf2a")!
    /// Failure only: error, denied permission.
    public static let coral = BrandColor(hex: "#ff5a36")!
    /// Separators and borders.
    public static let line = BrandColor(hex: "#2a2a2d")!

    /// Selection overlay dimming, black at 35 percent.
    public static let overlayDim = BrandColor(red: 0, green: 0, blue: 0)
    public static let overlayDimAlpha: CGFloat = 0.35
}
```

`Sources/MiracleShotCore/Imaging/ImageCodec.swift`:
```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodec {
    public static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public enum CodecError: Error { case encodingFailed }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let data = pngData(from: image) else { throw CodecError.encodingFailed }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
```

**Step 5: Run to verify it passes**

Run: `swift test --filter "BrandPaletteTests|ImageCodecTests"`
Expected: 7 tests pass.

**Step 6: Commit**

```bash
git add Sources/MiracleShotCore/Brand Sources/MiracleShotCore/Imaging Tests/MiracleShotCoreTests/Helpers Tests/MiracleShotCoreTests/BrandPaletteTests.swift Tests/MiracleShotCoreTests/ImageCodecTests.swift
git commit -m "Add BrandPalette tokens, ImageCodec and test image helpers"
```

---

### Task 9: Service protocols, fakes and CaptureCoordinator

Depends on Tasks 2, 3, 4, 6, 7. Everything in this task lives in `MiracleShotUI` and its tests; the coordinator never touches AppKit directly.

**Files:**
- Create: `Sources/MiracleShotUI/Services/ServiceProtocols.swift`
- Create: `Sources/MiracleShotUI/Coordinator/CaptureCoordinator.swift`
- Create: `Tests/MiracleShotAppTests/Helpers/Fakes.swift`
- Test: `Tests/MiracleShotAppTests/CaptureCoordinatorTests.swift`

**Step 1: Write the protocols** (no test yet; they are contracts for the fakes and the real services)

`Sources/MiracleShotUI/Services/ServiceProtocols.swift`:
```swift
import CoreGraphics
import Foundation
import MiracleShotCore

/// What the selection overlay hands back. Rect is in CG global coordinates.
public enum SelectionResult: Sendable, Equatable {
    case area(rect: CGRect, displayID: CGDirectDisplayID)
    case window(WindowInfo)
}

public enum CaptureError: Error, Equatable, Sendable {
    case permissionDenied
    case displayNotFound
    case windowNotFound
    case emptyImage
}

@MainActor public protocol CaptureServicing: AnyObject {
    func hasPermission() -> Bool
    func requestPermission()
    func capture(_ selection: SelectionResult) async throws -> Capture
    /// Full display under the mouse cursor.
    func captureDisplayUnderCursor() async throws -> Capture
}

@MainActor public protocol SelectionPresenting: AnyObject {
    /// Shows the overlay and suspends until the user finishes or cancels. `nil` means cancelled.
    func present(mode: CaptureMode) async -> SelectionResult?
}

@MainActor public protocol ClipboardServicing: AnyObject {
    func copy(_ capture: Capture)
}

@MainActor public protocol FileSaving: AnyObject {
    /// Writes the capture as PNG and returns the final URL.
    func save(_ capture: Capture, named fileName: String, in directory: URL) throws -> URL
}

@MainActor public protocol NotificationPosting: AnyObject {
    func post(title: String, body: String, isError: Bool)
}

@MainActor public protocol PreviewPresenting: AnyObject {
    func show(capture: Capture, fileURL: URL?, onDismiss: @escaping @MainActor () -> Void)
}
```

**Step 2: Write the fakes**

`Tests/MiracleShotAppTests/Helpers/Fakes.swift`:
```swift
import CoreGraphics
import Foundation
import MiracleShotCore
@testable import MiracleShotUI

/// Shared call log so tests can assert the order of side effects.
@MainActor final class CallLog {
    var entries: [String] = []
    func add(_ s: String) { entries.append(s) }
}

func makeTestImage(width: Int = 8, height: Int = 6) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0.2, 0.4, 0.6, 1])!)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

func makeCapture() -> Capture {
    Capture(image: makeTestImage(), timestamp: Date(timeIntervalSince1970: 1_789_394_709),
            sourceAppName: "Safari", sourceWindowTitle: nil,
            bounds: CGRect(x: 0, y: 0, width: 8, height: 6), scaleFactor: 1)
}

@MainActor final class FakeCaptureService: CaptureServicing {
    let log: CallLog
    var permission = true
    var error: CaptureError?
    init(log: CallLog) { self.log = log }

    func hasPermission() -> Bool { log.add("hasPermission"); return permission }
    func requestPermission() { log.add("requestPermission") }
    func capture(_ selection: SelectionResult) async throws -> Capture {
        log.add("capture(\(selection))")
        if let error { throw error }
        return makeCapture()
    }
    func captureDisplayUnderCursor() async throws -> Capture {
        log.add("captureDisplay")
        if let error { throw error }
        return makeCapture()
    }
}

@MainActor final class FakeSelection: SelectionPresenting {
    let log: CallLog
    var result: SelectionResult? = .area(rect: CGRect(x: 1, y: 2, width: 30, height: 40), displayID: 1)
    var hold = false
    private(set) var presentCount = 0
    private var continuation: CheckedContinuation<SelectionResult?, Never>?
    init(log: CallLog) { self.log = log }

    func present(mode: CaptureMode) async -> SelectionResult? {
        presentCount += 1
        log.add("present(\(mode))")
        guard hold else { return result }
        return await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor final class FakeClipboard: ClipboardServicing {
    let log: CallLog
    init(log: CallLog) { self.log = log }
    func copy(_ capture: Capture) { log.add("copy") }
}

@MainActor final class FakeFiles: FileSaving {
    let log: CallLog
    /// Directories whose saves throw.
    var failingDirectories: Set<String> = []
    var failAll = false
    init(log: CallLog) { self.log = log }
    struct SaveError: Error {}

    func save(_ capture: Capture, named fileName: String, in directory: URL) throws -> URL {
        log.add("save(\(fileName), \(directory.lastPathComponent))")
        if failAll || failingDirectories.contains(directory.path) { throw SaveError() }
        return directory.appendingPathComponent(fileName)
    }
}

@MainActor final class FakeNotifications: NotificationPosting {
    let log: CallLog
    var posted: [(title: String, isError: Bool)] = []
    init(log: CallLog) { self.log = log }
    func post(title: String, body: String, isError: Bool) {
        log.add("notify(\(isError ? "error" : "info"))")
        posted.append((title, isError))
    }
}

@MainActor final class FakePreview: PreviewPresenting {
    let log: CallLog
    var lastFileURL: URL?
    var onDismiss: (@MainActor () -> Void)?
    init(log: CallLog) { self.log = log }
    func show(capture: Capture, fileURL: URL?, onDismiss: @escaping @MainActor () -> Void) {
        log.add("preview")
        lastFileURL = fileURL
        self.onDismiss = onDismiss
    }
}
```

**Step 3: Write the failing tests**

`Tests/MiracleShotAppTests/CaptureCoordinatorTests.swift`:
```swift
import XCTest
import MiracleShotCore
@testable import MiracleShotUI

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
    private var log: CallLog!
    private var capture: FakeCaptureService!
    private var selection: FakeSelection!
    private var clipboard: FakeClipboard!
    private var files: FakeFiles!
    private var notifications: FakeNotifications!
    private var preview: FakePreview!
    private var historyURL: URL!
    private var settings: Settings!
    private var sut: CaptureCoordinator!

    override func setUp() async throws {
        log = CallLog()
        capture = FakeCaptureService(log: log)
        selection = FakeSelection(log: log)
        clipboard = FakeClipboard(log: log)
        files = FakeFiles(log: log)
        notifications = FakeNotifications(log: log)
        preview = FakePreview(log: log)
        historyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        settings = Settings.default
        settings.saveDirectoryPath = "/tmp/miracle-shot-tests/shots"
        settings.namingTemplate = NamingTemplate(pattern: "{app}-{seq}")
        sut = CaptureCoordinator(settings: settings, historyURL: historyURL, capture: capture, selection: selection,
                                 clipboard: clipboard, files: files, notifications: notifications, preview: preview)
    }

    func testAreaCaptureHappyPath() async {
        await sut.perform(.captureArea)
        XCTAssertEqual(log.entries, [
            "hasPermission", "present(area)",
            "capture(area(rect: (1.0, 2.0, 30.0, 40.0), displayID: 1))",
            "copy", "save(Safari-1.png, shots)", "preview",
        ])
        XCTAssertEqual(sut.state, .previewing)
        XCTAssertEqual(sut.history.entries.count, 1)
        XCTAssertEqual(sut.history.entries.first?.path, "/tmp/miracle-shot-tests/shots/Safari-1.png")
        XCTAssertEqual(preview.lastFileURL?.lastPathComponent, "Safari-1.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path))
    }

    func testFullScreenSkipsSelection() async {
        await sut.perform(.captureFullScreen)
        XCTAssertEqual(log.entries.prefix(2), ["hasPermission", "captureDisplay"])
        XCTAssertEqual(sut.state, .previewing)
    }

    func testCancelledSelectionDoesNothingElse() async {
        selection.result = nil
        await sut.perform(.captureWindow)
        XCTAssertEqual(log.entries, ["hasPermission", "present(window)"])
        XCTAssertEqual(sut.state, .idle)
    }

    func testMissingPermissionRequestsAndNotifies() async {
        capture.permission = false
        await sut.perform(.captureArea)
        XCTAssertEqual(log.entries, ["hasPermission", "requestPermission", "notify(error)"])
        XCTAssertEqual(sut.state, .idle)
    }

    func testCaptureFailureNotifiesAndReturnsToIdle() async {
        capture.error = .emptyImage
        await sut.perform(.captureArea)
        XCTAssertEqual(log.entries.last, "notify(error)")
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.history.entries.isEmpty)
    }

    func testSaveFallsBackToPicturesFolder() async {
        files.failingDirectories = [settings.saveDirectoryURL.path]
        await sut.perform(.captureArea)
        XCTAssertEqual(log.entries.suffix(4), [
            "save(Safari-1.png, shots)", "save(Safari-1.png, Miracle Shot)", "notify(info)", "preview",
        ])
        XCTAssertEqual(sut.history.entries.first?.path, Settings.fallbackSaveDirectory.appendingPathComponent("Safari-1.png").path)
    }

    func testSaveFailingEverywhereStillCopiesAndPreviews() async {
        files.failAll = true
        await sut.perform(.captureArea)
        XCTAssertTrue(log.entries.contains("copy"))
        XCTAssertEqual(log.entries.last, "preview")
        XCTAssertEqual(notifications.posted.last?.isError, true)
        XCTAssertNil(preview.lastFileURL)
        XCTAssertTrue(sut.history.entries.isEmpty)
    }

    func testSecondHotkeyWhileSelectingIsIgnored() async {
        selection.hold = true
        let task = Task { await sut.perform(.captureArea) }
        while selection.presentCount == 0 { await Task.yield() }
        await sut.perform(.captureWindow)
        XCTAssertEqual(selection.presentCount, 1)
        XCTAssertEqual(sut.state, .selecting(.area))
        selection.resume()
        await task.value
        XCTAssertEqual(sut.state, .previewing)
    }

    func testPreviewDismissReturnsToIdleAndHotkeyWhilePreviewingRestarts() async {
        await sut.perform(.captureArea)
        preview.onDismiss?()
        XCTAssertEqual(sut.state, .idle)
        await sut.perform(.captureArea)
        XCTAssertEqual(sut.state, .previewing)
        XCTAssertEqual(sut.history.entries.map(\.path).first, "/tmp/miracle-shot-tests/shots/Safari-2.png")
    }

    func testStateChangeCallbackFires() async {
        var seen: [CaptureState] = []
        sut.onStateChange = { seen.append($0) }
        await sut.perform(.captureArea)
        XCTAssertEqual(seen, [.selecting(.area), .capturing, .previewing])
    }
}
```

**Step 4: Run to verify it fails**

Run: `swift test --filter CaptureCoordinatorTests`
Expected: compile error `cannot find 'CaptureCoordinator' in scope`.

**Step 5: Implement the coordinator**

`Sources/MiracleShotUI/Coordinator/CaptureCoordinator.swift`:
```swift
import Foundation
import MiracleShotCore

/// Owns the capture state machine and drives the services. All side effects go through protocols so
/// every path here is covered by `CaptureCoordinatorTests` with fakes.
@MainActor
public final class CaptureCoordinator {
    public private(set) var state: CaptureState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public private(set) var history: HistoryIndex
    public private(set) var lastCapture: Capture?
    public var settings: Settings
    public var onStateChange: ((CaptureState) -> Void)?
    public var onHistoryChange: ((HistoryIndex) -> Void)?

    private let historyURL: URL
    private let capture: CaptureServicing
    private let selection: SelectionPresenting
    private let clipboard: ClipboardServicing
    private let files: FileSaving
    private let notifications: NotificationPosting
    private let preview: PreviewPresenting
    private var sequence = 0

    public init(settings: Settings, historyURL: URL, capture: CaptureServicing, selection: SelectionPresenting,
                clipboard: ClipboardServicing, files: FileSaving, notifications: NotificationPosting,
                preview: PreviewPresenting) {
        self.settings = settings
        self.historyURL = historyURL
        self.history = HistoryIndex.load(from: historyURL, limit: settings.historyLimit)
        self.capture = capture
        self.selection = selection
        self.clipboard = clipboard
        self.files = files
        self.notifications = notifications
        self.preview = preview
    }

    public func perform(_ action: CaptureAction) async {
        guard state.canStartCapture else { return }
        guard capture.hasPermission() else {
            capture.requestPermission()
            notifications.post(title: "Screen Recording permission needed",
                               body: "Allow Miracle Shot in System Settings > Privacy & Security > Screen Recording.",
                               isError: true)
            return
        }

        let mode = action.captureMode
        transition(.hotkey(mode))

        var selected: SelectionResult?
        if mode != .fullScreen {
            guard let result = await selection.present(mode: mode) else {
                transition(.selectionCancelled)
                return
            }
            transition(.selectionMade)
            selected = result
        }

        do {
            let shot: Capture
            if let selected {
                shot = try await capture.capture(selected)
            } else {
                shot = try await capture.captureDisplayUnderCursor()
            }
            transition(.captureSucceeded)
            finish(shot)
        } catch {
            transition(.captureFailed)
            notifications.post(title: "Capture failed", body: String(describing: error), isError: true)
        }
    }

    public func removeFromHistory(id: UUID) {
        history.remove(id: id)
        persistHistory()
    }

    // MARK: - Private

    private func transition(_ event: CaptureEvent) {
        state = CaptureStateMachine.reduce(state, event)
    }

    private func finish(_ shot: Capture) {
        lastCapture = shot
        clipboard.copy(shot)
        let fileURL = saveToDisk(shot)
        if let fileURL {
            history.append(HistoryEntry(path: fileURL.path, date: shot.timestamp, width: shot.pixelWidth,
                                        height: shot.pixelHeight, sourceApp: shot.sourceAppName))
            persistHistory()
        }
        preview.show(capture: shot, fileURL: fileURL) { [weak self] in
            self?.transition(.previewDismissed)
        }
    }

    private func saveToDisk(_ shot: Capture) -> URL? {
        sequence += 1
        let name = settings.namingTemplate.fileName(date: shot.timestamp, appName: shot.sourceAppName, sequence: sequence)
        do {
            return try files.save(shot, named: name, in: settings.saveDirectoryURL)
        } catch {
            do {
                let url = try files.save(shot, named: name, in: Settings.fallbackSaveDirectory)
                notifications.post(title: "Saved to Pictures/Miracle Shot",
                                   body: "The configured folder is not writable.", isError: false)
                return url
            } catch {
                notifications.post(title: "Could not save screenshot", body: String(describing: error), isError: true)
                return nil
            }
        }
    }

    private func persistHistory() {
        try? history.save(to: historyURL)
        onHistoryChange?(history)
    }
}
```

**Step 6: Run to verify it passes**

Run: `swift test --filter CaptureCoordinatorTests`
Expected: 10 tests pass. If the `capture(area(...))` string differs in formatting, fix the expectation in the test to the actual `String(describing:)` output once, not the implementation.

**Step 7: Commit**

```bash
git add Sources/MiracleShotUI/Services/ServiceProtocols.swift Sources/MiracleShotUI/Coordinator Tests/MiracleShotAppTests
git commit -m "Add service protocols, fakes and CaptureCoordinator"
```

---

### Task 10: HotkeyManager (Carbon)

Depends on Task 7. Carbon `RegisterEventHotKey` works without the Accessibility permission. There is no automated test: registering global hotkeys from the test runner would hijack the machine. Verification is the manual check in Task 13.

**Files:**
- Create: `Sources/MiracleShotUI/Hotkeys/HotkeyManager.swift`

**Step 1: Implement**

```swift
import Carbon
import MiracleShotCore

/// Registers global hotkeys through Carbon and maps them back to `CaptureAction`.
@MainActor
public final class HotkeyManager {
    public typealias Handler = @MainActor (CaptureAction) -> Void

    private static let signature: OSType = 0x4D53_4854 // "MSHT"
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: CaptureAction] = [:]
    private var eventHandler: EventHandlerRef?
    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
        installEventHandler()
    }

    /// Replaces all bindings. Returns the actions whose hotkey could not be registered (already taken by another app).
    @discardableResult
    public func register(_ bindings: [CaptureAction: HotkeySpec]) -> [CaptureAction] {
        unregisterAll()
        var failed: [CaptureAction] = []
        for (index, action) in CaptureAction.allCases.enumerated() {
            guard let spec = bindings[action] else { continue }
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(spec.carbonKeyCode, spec.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
                actionsByID[id.id] = action
            } else {
                failed.append(action)
            }
        }
        return failed
    }

    public func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actionsByID.removeAll()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        // The C callback cannot capture context; `userData` carries the manager. Carbon delivers on the main thread.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { manager.fire(id: hotKeyID.id) }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)
    }

    private func fire(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        handler(action)
    }
}
```

**Step 2: Build**

Run: `swift build`
Expected: no errors. If the compiler complains that `fire` is inaccessible from the closure, make it `fileprivate`.

**Step 3: Commit**

```bash
git add Sources/MiracleShotUI/Hotkeys
git commit -m "Add Carbon HotkeyManager"
```

---

### Task 11: ScreenCaptureService (ScreenCaptureKit)

Depends on Task 9 (protocols). Real implementation of `CaptureServicing`. Verified manually in Task 13.

**Files:**
- Create: `Sources/MiracleShotUI/Support/NSScreen+DisplayID.swift`
- Create: `Sources/MiracleShotUI/Services/ScreenCaptureService.swift`

**Step 1: Implement**

`Sources/MiracleShotUI/Support/NSScreen+DisplayID.swift`:
```swift
import AppKit

extension NSScreen {
    public var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    public static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    /// The screen containing the mouse cursor, falling back to the main screen.
    public static var underCursor: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }

    /// Height of the primary screen; needed to flip between AppKit and CG coordinates.
    public static var primaryHeight: CGFloat { screens.first?.frame.height ?? 0 }
}
```

`Sources/MiracleShotUI/Services/ScreenCaptureService.swift`:
```swift
import AppKit
import MiracleShotCore
import ScreenCaptureKit

@MainActor
public final class ScreenCaptureService: CaptureServicing {
    public init() {}

    public func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    public func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    public func capture(_ selection: SelectionResult) async throws -> Capture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }

        switch selection {
        case .area(let rect, let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayNotFound
            }
            let scale = NSScreen.screen(for: displayID)?.backingScaleFactor ?? 2
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let config = Self.configuration()
            config.sourceRect = CGRect(x: rect.minX - display.frame.minX, y: rect.minY - display.frame.minY,
                                       width: rect.width, height: rect.height)
            config.width = Int((rect.width * scale).rounded())
            config.height = Int((rect.height * scale).rounded())
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return Capture(image: image, bounds: rect, scaleFactor: scale)

        case .window(let info):
            guard let window = content.windows.first(where: { $0.windowID == info.id }) else {
                throw CaptureError.windowNotFound
            }
            let displayID = Self.displayID(containing: window.frame)
            let scale = NSScreen.screen(for: displayID)?.backingScaleFactor ?? 2
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = Self.configuration()
            config.width = Int((window.frame.width * scale).rounded())
            config.height = Int((window.frame.height * scale).rounded())
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return Capture(image: image, sourceAppName: window.owningApplication?.applicationName,
                           sourceWindowTitle: window.title, bounds: window.frame, scaleFactor: scale)
        }
    }

    public func captureDisplayUnderCursor() async throws -> Capture {
        guard let screen = NSScreen.underCursor else { throw CaptureError.displayNotFound }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let scale = screen.backingScaleFactor
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let config = Self.configuration()
        config.width = Int((CGFloat(display.width) * scale).rounded())
        config.height = Int((CGFloat(display.height) * scale).rounded())
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(image: image, bounds: display.frame, scaleFactor: scale)
    }

    private static func configuration() -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.showsCursor = false
        c.captureResolution = .best
        c.scalesToFit = false
        return c
    }

    private static func displayID(containing rect: CGRect) -> CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetDisplaysWithRect(rect, 16, &ids, &count)
        return count > 0 ? ids[0] : CGMainDisplayID()
    }
}
```

**Step 2: Build**

Run: `swift build`
Expected: no errors. Under strict concurrency, if `SCShareableContent` or `SCWindow` is reported as non-Sendable across the `await`, keep all uses inside this `@MainActor` class (they already are) and add `nonisolated(unsafe)` only where the compiler insists, with a comment.

**Step 3: Commit**

```bash
git add Sources/MiracleShotUI/Support Sources/MiracleShotUI/Services/ScreenCaptureService.swift
git commit -m "Add ScreenCaptureKit-based capture service"
```

---

### Task 12: SelectionOverlay, basic version

Depends on Tasks 4 and 9. Drag a rectangle, Esc cancels, a click without drag cancels (Task 14 turns the click into window capture and adds magnifier, size label and snapping). One panel per screen. No automated test; geometry is already tested in Core.

**Files:**
- Create: `Sources/MiracleShotUI/Selection/SelectionOverlayController.swift`
- Create: `Sources/MiracleShotUI/Selection/SelectionPanel.swift`
- Create: `Sources/MiracleShotUI/Selection/SelectionView.swift`
- Create: `Sources/MiracleShotUI/Support/BrandColors.swift`

**Step 1: Implement brand color bridge**

`Sources/MiracleShotUI/Support/BrandColors.swift`:
```swift
import AppKit
import MiracleShotCore

extension BrandColor {
    public func nsColor(alpha: CGFloat = 1) -> NSColor {
        NSColor(cgColor: cgColor(alpha: alpha)) ?? .black
    }
}
```

**Step 2: Implement the controller**

`Sources/MiracleShotUI/Selection/SelectionOverlayController.swift`:
```swift
import AppKit
import MiracleShotCore

/// Shows one transparent panel per screen and resolves the `present` continuation exactly once.
@MainActor
public final class SelectionOverlayController: SelectionPresenting {
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<SelectionResult?, Never>?

    public init() {}

    public func present(mode: CaptureMode) async -> SelectionResult? {
        guard continuation == nil else { return nil }
        panels = NSScreen.screens.map { SelectionPanel(screen: $0, mode: mode, controller: self) }
        for panel in panels { panel.orderFrontRegardless() }
        panels.first?.makeKey()
        NSCursor.crosshair.push()
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(with result: SelectionResult?) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        continuation.resume(returning: result)
    }
}
```

`Sources/MiracleShotUI/Selection/SelectionPanel.swift`:
```swift
import AppKit
import MiracleShotCore

@MainActor
final class SelectionPanel: NSPanel {
    init(screen: NSScreen, mode: CaptureMode, controller: SelectionOverlayController) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = SelectionView(screen: screen, mode: mode, controller: controller)
    }

    override var canBecomeKey: Bool { true }
}
```

`Sources/MiracleShotUI/Selection/SelectionView.swift`:
```swift
import AppKit
import MiracleShotCore

/// Draws the dimming, the rubber-band rectangle and converts events into CG global coordinates.
@MainActor
final class SelectionView: NSView {
    private let screen: NSScreen
    private let mode: CaptureMode
    private unowned let controller: SelectionOverlayController
    private var dragStart: CGPoint?
    private var selection: CGRect?

    init(screen: NSScreen, mode: CaptureMode, controller: SelectionOverlayController) {
        self.screen = screen
        self.mode = mode
        self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller.finish(with: nil) }   // Escape
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        dragStart = cgPoint(from: event)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        selection = SelectionGeometry.rect(from: start, to: cgPoint(from: event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let end = cgPoint(from: event)
        dragStart = nil
        if SelectionGeometry.isClick(from: start, to: end) {
            controller.finish(with: nil)
            return
        }
        let rect = SelectionGeometry.pixelAligned(SelectionGeometry.rect(from: start, to: end), scale: screen.backingScaleFactor)
        controller.finish(with: .area(rect: rect, displayID: screen.displayID))
    }

    override func draw(_ dirtyRect: NSRect) {
        BrandPalette.overlayDim.nsColor(alpha: BrandPalette.overlayDimAlpha).setFill()
        bounds.fill()
        guard let selection, let viewRect = viewRect(fromCG: selection) else { return }
        NSColor.clear.setFill()
        viewRect.fill(using: .copy)
        BrandPalette.lime.nsColor().setStroke()
        let path = NSBezierPath(rect: viewRect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: Coordinates

    private func cgPoint(from event: NSEvent) -> CGPoint {
        guard let window else { return .zero }
        let global = window.convertPoint(toScreen: event.locationInWindow)
        return SelectionGeometry.flipped(global, primaryScreenHeight: NSScreen.primaryHeight)
    }

    private func viewRect(fromCG rect: CGRect) -> NSRect? {
        guard let window else { return nil }
        let appKit = SelectionGeometry.flipped(rect, primaryScreenHeight: NSScreen.primaryHeight)
        return convert(window.convertFromScreen(appKit), from: nil)
    }
}
```

**Step 3: Build**

Run: `swift build`
Expected: no errors.

**Step 4: Commit**

```bash
git add Sources/MiracleShotUI/Selection Sources/MiracleShotUI/Support/BrandColors.swift
git commit -m "Add basic selection overlay: drag rectangle, Escape cancels"
```

---

### Task 13: Milestone — hotkey, area, clipboard, file, toast

Depends on Tasks 9–12. After this task the app is usable for real: `shift+cmd+1`, drag, paste. Preview is a stub that dismisses immediately (Task 15 replaces it).

**Files:**
- Create: `Sources/MiracleShotUI/Services/ClipboardService.swift`
- Create: `Sources/MiracleShotUI/Services/FileSaveService.swift`
- Create: `Sources/MiracleShotUI/Services/ImmediateDismissPreview.swift`
- Create: `Sources/MiracleShotCore/Support/CoreResources.swift`
- Create: `Sources/MiracleShotUI/Support/UIResources.swift`
- Modify: `Tests/MiracleShotCoreTests/CoreSmokeTests.swift`
- Create: `Sources/MiracleShotUI/Toast/ToastPresenter.swift`
- Create: `Sources/MiracleShotUI/App/AppDelegate.swift`
- Modify: `Sources/MiracleShotApp/main.swift`
- Test: `Tests/MiracleShotAppTests/FileSaveServiceTests.swift`

**Step 1: Write the failing test for unique file names**

`Tests/MiracleShotAppTests/FileSaveServiceTests.swift`:
```swift
import XCTest
import MiracleShotCore
@testable import MiracleShotUI

@MainActor
final class FileSaveServiceTests: XCTestCase {
    func testSavesPNGAndAvoidsOverwriting() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = FileSaveService()
        let first = try service.save(makeCapture(), named: "shot.png", in: dir)
        let second = try service.save(makeCapture(), named: "shot.png", in: dir)
        let third = try service.save(makeCapture(), named: "shot.png", in: dir)
        XCTAssertEqual(first.lastPathComponent, "shot.png")
        XCTAssertEqual(second.lastPathComponent, "shot 2.png")
        XCTAssertEqual(third.lastPathComponent, "shot 3.png")
        XCTAssertNotNil(ImageCodec.image(at: second))
    }

    func testThrowsWhenDirectoryCannotBeCreated() {
        let service = FileSaveService()
        XCTAssertThrowsError(try service.save(makeCapture(), named: "x.png", in: URL(fileURLWithPath: "/System/nope")))
    }
}
```

Run: `swift test --filter FileSaveServiceTests`
Expected: compile error `cannot find 'FileSaveService' in scope`.

**Step 2: Implement services**

`Sources/MiracleShotUI/Services/FileSaveService.swift`:
```swift
import Foundation
import MiracleShotCore

@MainActor
public final class FileSaveService: FileSaving {
    public init() {}

    public func save(_ capture: Capture, named fileName: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = Self.uniqueURL(for: fileName, in: directory)
        try ImageCodec.writePNG(capture.image, to: url)
        return url
    }

    /// "shot.png" -> "shot 2.png" -> "shot 3.png" while the name is taken.
    static func uniqueURL(for fileName: String, in directory: URL) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
```

`Sources/MiracleShotUI/Services/ClipboardService.swift`:
```swift
import AppKit
import MiracleShotCore

@MainActor
public final class ClipboardService: ClipboardServicing {
    public init() {}

    public func copy(_ capture: Capture) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        if let png = ImageCodec.pngData(from: capture.image) {
            pasteboard.setData(png, forType: .png)
        }
        let image = NSImage(cgImage: capture.image, size: capture.bounds.size)
        if let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
```

`Sources/MiracleShotUI/Services/ImmediateDismissPreview.swift`:
```swift
import Foundation
import MiracleShotCore

/// Placeholder until the floating preview exists: reports dismissal right away so the state machine returns to idle.
@MainActor
public final class ImmediateDismissPreview: PreviewPresenting {
    public init() {}
    public func show(capture: Capture, fileURL: URL?, onDismiss: @escaping @MainActor () -> Void) {
        onDismiss()
    }
}
```

**Step 2b: Resource bundle locator**

SwiftPM's generated `Bundle.module` looks for `MiracleShot_<Target>.bundle` next to the executable or at a build-time absolute path under `.build/`; inside a packaged `.app` neither exists (the script puts bundles in `Contents/Resources`), and copying them to the app root would break code signing ("unsealed contents"). Every bundled resource must therefore go through these locators, never through `Bundle.module` directly.

`Sources/MiracleShotCore/Support/CoreResources.swift`:
```swift
import Foundation

/// Locates this target's resource bundle both when running from `swift run`/tests and from the packaged app.
public enum CoreResources {
    public static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("MiracleShot_MiracleShotCore.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
```

`Sources/MiracleShotUI/Support/UIResources.swift`:
```swift
import Foundation

public enum UIResources {
    public static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("MiracleShot_MiracleShotUI.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
```

Add to `Tests/MiracleShotCoreTests/CoreSmokeTests.swift`:
```swift
    func testCoreResourceBundleContainsPresetsFolder() {
        XCTAssertNotNil(CoreResources.bundle.url(forResource: "presets", withExtension: nil))
    }
```

Add to the manual check of this task: `rm -rf .build && scripts/build-app.sh && open "build/Miracle Shot.app"` must launch without a crash (the `.build` fallback path no longer exists, so a wrong locator would `fatalError` on the first resource access once Phase 2 loads presets).

**Step 3: Implement the toast**

`Sources/MiracleShotUI/Toast/ToastPresenter.swift`:
```swift
import AppKit
import MiracleShotCore

/// Small floating notice at the top-right of the screen under the cursor. Replaces UNUserNotificationCenter,
/// which needs a bundle and permission prompts.
@MainActor
public final class ToastPresenter: NotificationPosting {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    public init() {}

    public func post(title: String, body: String, isError: Bool) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let width: CGFloat = 320
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = BrandPalette.bone.nsColor()
        let bodyLabel = NSTextField(wrappingLabelWithString: body)
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = BrandPalette.boneDim.nsColor()
        bodyLabel.preferredMaxLayoutWidth = width - 32

        let stack = NSStackView(views: [titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = BrandPalette.ink2.cgColor()
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = (isError ? BrandPalette.coral : BrandPalette.line).cgColor()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: width),
        ])
        container.layoutSubtreeIfNeeded()
        let size = container.fittingSize

        let screen = NSScreen.underCursor ?? NSScreen.screens[0]
        let origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 16, y: screen.visibleFrame.maxY - size.height - 16)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.contentView = container
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 5 : 3))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
        self.panel = nil
    }
}
```

**Step 4: Implement the app delegate**

`Sources/MiracleShotUI/App/AppDelegate.swift`:
```swift
import AppKit
import MiracleShotCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeys: HotkeyManager!
    private(set) var coordinator: CaptureCoordinator!
    private let toast = ToastPresenter()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let settings = Settings.load()
        coordinator = CaptureCoordinator(
            settings: settings,
            historyURL: Settings.historyURL,
            capture: ScreenCaptureService(),
            selection: SelectionOverlayController(),
            clipboard: ClipboardService(),
            files: FileSaveService(),
            notifications: toast,
            preview: ImmediateDismissPreview()
        )
        hotkeys = HotkeyManager { [weak self] action in
            self?.trigger(action)
        }
        let failed = hotkeys.register(settings.hotkeys)
        if !failed.isEmpty {
            toast.post(title: "Some hotkeys are taken",
                       body: failed.map(\.title).joined(separator: ", ") + ". Change them in Settings.", isError: true)
        }
        buildStatusItem(settings: settings)
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    private func trigger(_ action: CaptureAction) {
        Task { await coordinator.perform(action) }
    }

    private func buildStatusItem(settings: Settings) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MS"
        statusItem.menu = buildMenu(settings: settings)
    }

    func buildMenu(settings: Settings) -> NSMenu {
        let menu = NSMenu()
        for action in CaptureAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(menuCapture(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            if let spec = settings.hotkeys[action] { item.toolTip = spec.description }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Miracle Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func menuCapture(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = CaptureAction(rawValue: raw) else { return }
        // Let the menu close before the overlay appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.trigger(action) }
    }
}
```

`Sources/MiracleShotApp/main.swift` (replace the whole file):
```swift
import AppKit
import MiracleShotUI

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

**Step 5: Run tests and build the bundle**

Run: `swift test`
Expected: all tests pass, including `FileSaveServiceTests`.

Run: `scripts/build-app.sh && open "build/Miracle Shot.app"`

**Manual check (reviewer, on the real machine):**
1. "MS" appears in the menu bar. On first launch macOS asks for Screen Recording; enable Miracle Shot in System Settings, then quit and relaunch the app.
2. Press `shift+cmd+1`: every screen dims (35 percent black), cursor is a crosshair. Drag: a clear rectangle with a 1 pt lime border. Release: overlay disappears.
3. Paste into Notes or Slack: the screenshot appears. `~/Pictures/Miracle Shot/` contains `Miracle Shot <date> at <time>.png` with the right pixels at Retina resolution (2x).
4. `shift+cmd+1` then Escape: overlay disappears, nothing copied. Click without drag: same.
5. `shift+cmd+0`: the whole display under the cursor is captured without any dimming.
6. Menu items "Capture Area" and "Capture Full Screen" do the same as the hotkeys.
7. Rebuild with `scripts/build-app.sh`, relaunch: no new permission prompt. This holds only when the app is signed with the `Miracle Shot Dev` identity (`scripts/make-signing-cert.sh`); with ad-hoc signing TCC binds the grant to the build's cdhash, shows the toggle as on, yet `CGPreflightScreenCaptureAccess()` returns false. After changing the signing identity run `tccutil reset ScreenCapture agency.blackbloom.miracleshot` and grant again.
8. Quit and run `open "build/Miracle Shot.app"` twice: only one "MS" icon (second launch focuses the first; if two appear, add `LSMultipleInstancesProhibited` to Info.plist in `build-app.sh`).

**Step 6: Commit**

```bash
git add Sources Tests
git commit -m "Wire menu bar app: hotkeys, capture, clipboard, file save, toast"
git tag milestone-1-hotkey-to-clipboard
```

---

### Task 14: SelectionOverlay, full version

Depends on Task 13. Adds: frozen screen background, magnifier with pixel grid, size label, window highlight and click-to-capture-window, edge snapping (hold Option to disable). Window list comes from `CGWindowListCopyWindowInfo`; parsing is a pure Core function with tests.

**Files:**
- Create: `Sources/MiracleShotCore/Selection/WindowInfo+WindowServer.swift`
- Create: `Sources/MiracleShotUI/Services/CGWindowListProvider.swift`
- Modify: `Sources/MiracleShotUI/Services/ServiceProtocols.swift` (add `WindowListProviding`, add `captureDisplay(_:)`)
- Modify: `Sources/MiracleShotUI/Services/ScreenCaptureService.swift`
- Modify: `Tests/MiracleShotAppTests/Helpers/Fakes.swift` (add `captureDisplay` to the fake)
- Modify: `Sources/MiracleShotUI/Selection/SelectionOverlayController.swift`
- Modify: `Sources/MiracleShotUI/Selection/SelectionPanel.swift`
- Modify: `Sources/MiracleShotUI/Selection/SelectionView.swift`
- Modify: `Sources/MiracleShotUI/App/AppDelegate.swift` (pass dependencies to the overlay)
- Test: `Tests/MiracleShotCoreTests/WindowInfoParsingTests.swift`

**Step 1: Write the failing test for window-server dictionary parsing**

```swift
import XCTest
@testable import MiracleShotCore

final class WindowInfoParsingTests: XCTestCase {
    private func dict(id: Int = 12, bounds: CGRect = CGRect(x: 10, y: 20, width: 300, height: 200),
                      layer: Int = 0, pid: Int = 500, owner: String? = "Safari", name: String? = "Apple") -> [String: Any] {
        var d: [String: Any] = [
            "kCGWindowNumber": id,
            "kCGWindowBounds": bounds.dictionaryRepresentation,
            "kCGWindowLayer": layer,
            "kCGWindowOwnerPID": pid,
        ]
        if let owner { d["kCGWindowOwnerName"] = owner }
        if let name { d["kCGWindowName"] = name }
        return d
    }

    func testParsesFullDictionary() throws {
        let w = try XCTUnwrap(WindowInfo(windowServerDictionary: dict()))
        XCTAssertEqual(w.id, 12)
        XCTAssertEqual(w.frame, CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertEqual(w.layer, 0)
        XCTAssertEqual(w.ownerPID, 500)
        XCTAssertEqual(w.ownerName, "Safari")
        XCTAssertEqual(w.title, "Apple")
    }

    func testMissingOptionalFieldsAreTolerated() throws {
        let w = try XCTUnwrap(WindowInfo(windowServerDictionary: dict(owner: nil, name: nil)))
        XCTAssertEqual(w.ownerName, "")
        XCTAssertNil(w.title)
    }

    func testMissingRequiredFieldReturnsNil() {
        var d = dict()
        d.removeValue(forKey: "kCGWindowBounds")
        XCTAssertNil(WindowInfo(windowServerDictionary: d))
    }

    func testDegenerateWindowsAreRejected() {
        XCTAssertNil(WindowInfo(windowServerDictionary: dict(bounds: CGRect(x: 0, y: 0, width: 1, height: 1))))
    }
}
```

Run: `swift test --filter WindowInfoParsingTests`
Expected: compile error, no such initializer.

**Step 2: Implement parsing in Core**

`Sources/MiracleShotCore/Selection/WindowInfo+WindowServer.swift`:
```swift
import CoreGraphics
import Foundation

extension WindowInfo {
    /// Builds a `WindowInfo` from one entry of `CGWindowListCopyWindowInfo`. Keys are the string values of
    /// `kCGWindowNumber`, `kCGWindowBounds`, `kCGWindowLayer`, `kCGWindowOwnerPID`, `kCGWindowOwnerName`, `kCGWindowName`.
    public init?(windowServerDictionary d: [String: Any]) {
        guard let id = (d["kCGWindowNumber"] as? NSNumber)?.uint32Value,
              let boundsDict = d["kCGWindowBounds"] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDict),
              let layer = (d["kCGWindowLayer"] as? NSNumber)?.intValue,
              let pid = (d["kCGWindowOwnerPID"] as? NSNumber)?.int32Value,
              frame.width > 1, frame.height > 1
        else { return nil }
        self.init(id: id, frame: frame, layer: layer,
                  ownerName: d["kCGWindowOwnerName"] as? String ?? "",
                  ownerPID: pid, title: d["kCGWindowName"] as? String)
    }
}
```

Run: `swift test --filter WindowInfoParsingTests`
Expected: 4 tests pass.

**Step 3: Extend protocols and services**

Add to `ServiceProtocols.swift`:
```swift
@MainActor public protocol WindowListProviding: AnyObject {
    /// On-screen windows, front to back, excluding this process.
    func onScreenWindows() -> [WindowInfo]
}
```
and add to `CaptureServicing`:
```swift
    func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> Capture
```

`Sources/MiracleShotUI/Services/CGWindowListProvider.swift`:
```swift
import CoreGraphics
import Foundation
import MiracleShotCore

@MainActor
public final class CGWindowListProvider: WindowListProviding {
    public init() {}

    public func onScreenWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = getpid()
        return list.compactMap(WindowInfo.init(windowServerDictionary:)).filter { $0.ownerPID != ownPID }
    }
}
```

In `ScreenCaptureService`, extract the body of `captureDisplayUnderCursor` into `captureDisplay(_ displayID:)` and make `captureDisplayUnderCursor` call it with `NSScreen.underCursor!.displayID`. In `Fakes.swift` add to `FakeCaptureService`:
```swift
    func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> Capture {
        log.add("captureDisplay(\(displayID))")
        if let error { throw error }
        return makeCapture()
    }
```
Run `swift test` — everything still green.

**Step 4: Rewrite the overlay**

`SelectionOverlayController.swift`:
```swift
import AppKit
import MiracleShotCore

@MainActor
public final class SelectionOverlayController: SelectionPresenting {
    private let capture: CaptureServicing
    private let windowList: WindowListProviding
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<SelectionResult?, Never>?

    public init(capture: CaptureServicing, windowList: WindowListProviding) {
        self.capture = capture
        self.windowList = windowList
    }

    public func present(mode: CaptureMode) async -> SelectionResult? {
        guard continuation == nil else { return nil }
        let windows = windowList.onScreenWindows()
        var frozen: [CGDirectDisplayID: CGImage] = [:]
        for screen in NSScreen.screens {
            if let shot = try? await capture.captureDisplay(screen.displayID) { frozen[screen.displayID] = shot.image }
        }
        panels = NSScreen.screens.map {
            SelectionPanel(screen: $0, mode: mode, controller: self, windows: windows, frozen: frozen[$0.displayID])
        }
        for panel in panels { panel.orderFrontRegardless() }
        panels.first?.makeKey()
        NSCursor.crosshair.push()
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(with result: SelectionResult?) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        continuation.resume(returning: result)
    }
}
```

`SelectionPanel.swift`: change the initializer to `init(screen:mode:controller:windows:frozen:)` and pass `windows` and `frozen` into `SelectionView`.

`SelectionView.swift` (full replacement):
```swift
import AppKit
import MiracleShotCore

@MainActor
final class SelectionView: NSView {
    private static let snapThreshold: CGFloat = 8
    private static let magnifierSize: CGFloat = 120
    private static let magnifierOffset: CGFloat = 20
    private static let magnifierPixels = 15   // source points shown in the magnifier

    private let screen: NSScreen
    private let mode: CaptureMode
    private unowned let controller: SelectionOverlayController
    private let windows: [WindowInfo]
    private let frozen: CGImage?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var cursor: CGPoint?
    private var hoveredWindow: WindowInfo?
    private var trackingArea: NSTrackingArea?

    init(screen: NSScreen, mode: CaptureMode, controller: SelectionOverlayController, windows: [WindowInfo], frozen: CGImage?) {
        self.screen = screen
        self.mode = mode
        self.controller = controller
        self.windows = windows
        self.frozen = frozen
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Events

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller.finish(with: nil) }
    }

    override func mouseMoved(with event: NSEvent) {
        cursor = cgPoint(from: event)
        hoveredWindow = cursor.flatMap { SelectionGeometry.window(at: $0, in: windows) }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        dragStart = cgPoint(from: event)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        cursor = cgPoint(from: event)
        var rect = SelectionGeometry.rect(from: start, to: cursor!)
        if !event.modifierFlags.contains(.option) {
            rect = SelectionGeometry.snapped(rect, to: windows, threshold: Self.snapThreshold)
        }
        selection = rect
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let end = cgPoint(from: event)
        dragStart = nil
        if SelectionGeometry.isClick(from: start, to: end) {
            if let hovered = SelectionGeometry.window(at: end, in: windows) {
                controller.finish(with: .window(hovered))
            } else {
                controller.finish(with: nil)
            }
            return
        }
        guard let selection, selection.width >= 1, selection.height >= 1 else { controller.finish(with: nil); return }
        let rect = SelectionGeometry.pixelAligned(selection, scale: screen.backingScaleFactor)
        controller.finish(with: .area(rect: rect, displayID: screen.displayID))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if let frozen {
            NSGraphicsContext.current?.cgContext.draw(frozen, in: bounds)
        }
        BrandPalette.overlayDim.nsColor(alpha: BrandPalette.overlayDimAlpha).setFill()
        bounds.fill()

        let highlight: CGRect? = selection ?? (dragStart == nil && mode == .window ? hoveredWindow?.frame : nil)
        if let highlight, let viewRect = viewRect(fromCG: highlight) {
            if let frozen {
                NSGraphicsContext.saveGraphicsState()
                viewRect.clip()
                NSGraphicsContext.current?.cgContext.draw(frozen, in: bounds)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor.clear.setFill()
                viewRect.fill(using: .copy)
            }
            BrandPalette.lime.nsColor().setStroke()
            let path = NSBezierPath(rect: viewRect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
            drawSizeLabel(for: highlight, near: viewRect)
        }

        if let cursor, let viewCursor = viewPoint(fromCG: cursor), screenContains(cursor) {
            drawMagnifier(at: viewCursor, cgCursor: cursor)
        }
    }

    private func drawSizeLabel(for cgRect: CGRect, near viewRect: NSRect) {
        let text = "\(Int(cgRect.width)) × \(Int(cgRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: BrandPalette.bone.nsColor(),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        var origin = NSPoint(x: viewRect.maxX - size.width - 12, y: viewRect.minY - size.height - 12)
        if origin.y < 4 { origin.y = viewRect.minY + 6 }
        let box = NSRect(origin: origin, size: size).insetBy(dx: -6, dy: -3)
        BrandPalette.ink2.nsColor().setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func drawMagnifier(at viewCursor: NSPoint, cgCursor: CGPoint) {
        guard let frozen else { return }
        let scale = screen.backingScaleFactor
        let screenBounds = CGRect(origin: .zero, size: bounds.size)
        let cgFrame = SelectionGeometry.magnifierFrame(
            cursor: CGPoint(x: cgCursor.x - screenFrameCG.minX, y: cgCursor.y - screenFrameCG.minY),
            size: Self.magnifierSize, offset: Self.magnifierOffset, in: screenBounds)
        // Local CG (top-left) -> view (bottom-left).
        let frame = NSRect(x: cgFrame.minX, y: bounds.height - cgFrame.maxY, width: cgFrame.width, height: cgFrame.height)

        let half = CGFloat(Self.magnifierPixels) / 2
        let localX = cgCursor.x - screenFrameCG.minX
        let localY = cgCursor.y - screenFrameCG.minY
        let sourceRect = CGRect(x: (localX - half) * scale, y: (localY - half) * scale,
                                width: CGFloat(Self.magnifierPixels) * scale, height: CGFloat(Self.magnifierPixels) * scale)
        guard let crop = frozen.cropping(to: sourceRect) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSGraphicsContext.current?.cgContext.draw(crop, in: frame)
        // Pixel grid and center crosshair.
        BrandPalette.line.nsColor(alpha: 0.6).setStroke()
        let cell = frame.width / CGFloat(Self.magnifierPixels)
        for i in 1..<Self.magnifierPixels {
            let x = frame.minX + CGFloat(i) * cell
            let y = frame.minY + CGFloat(i) * cell
            NSBezierPath.strokeLine(from: NSPoint(x: x, y: frame.minY), to: NSPoint(x: x, y: frame.maxY))
            NSBezierPath.strokeLine(from: NSPoint(x: frame.minX, y: y), to: NSPoint(x: frame.maxX, y: y))
        }
        BrandPalette.lime.nsColor().setStroke()
        let center = NSRect(x: frame.midX - cell / 2, y: frame.midY - cell / 2, width: cell, height: cell)
        NSBezierPath(rect: center).stroke()
        NSGraphicsContext.restoreGraphicsState()
        BrandPalette.lime.nsColor().setStroke()
        NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

    // MARK: Coordinates

    private var screenFrameCG: CGRect {
        SelectionGeometry.flipped(screen.frame, primaryScreenHeight: NSScreen.primaryHeight)
    }

    private func screenContains(_ cgPoint: CGPoint) -> Bool { screenFrameCG.contains(cgPoint) }

    private func cgPoint(from event: NSEvent) -> CGPoint {
        guard let window else { return .zero }
        let global = window.convertPoint(toScreen: event.locationInWindow)
        return SelectionGeometry.flipped(global, primaryScreenHeight: NSScreen.primaryHeight)
    }

    private func viewRect(fromCG rect: CGRect) -> NSRect? {
        guard let window else { return nil }
        let appKit = SelectionGeometry.flipped(rect, primaryScreenHeight: NSScreen.primaryHeight)
        return convert(window.convertFromScreen(appKit), from: nil)
    }

    private func viewPoint(fromCG point: CGPoint) -> NSPoint? {
        guard let window else { return nil }
        let appKit = SelectionGeometry.flipped(point, primaryScreenHeight: NSScreen.primaryHeight)
        return convert(window.convertPoint(fromScreen: appKit), from: nil)
    }
}
```

In `AppDelegate`, construct the overlay with dependencies:
```swift
        let captureService = ScreenCaptureService()
        ...
            capture: captureService,
            selection: SelectionOverlayController(capture: captureService, windowList: CGWindowListProvider()),
```

**Step 5: Build, test, manual check**

Run: `swift test && scripts/build-app.sh && open "build/Miracle Shot.app"`

**Manual check:**
1. `shift+cmd+1`: the screen freezes (frozen screenshot under the dim), a 120 pt magnifier with a pixel grid follows the cursor and flips sides near the right and bottom edges.
2. Dragging near a window edge snaps the rectangle to it; holding Option disables snapping. The size label shows "W × H" in points at the bottom-right of the selection.
3. `shift+cmd+2`: hovering highlights the window under the cursor (undimmed, lime border); clicking captures exactly that window (title bar included, shadow excluded). The saved file name contains the app name when the template has `{app}`.
4. In area mode a click without drag captures the window under the cursor; a click on the desktop cancels.
5. Multi-display: the magnifier and highlight appear on the screen where the cursor is.

**Step 6: Commit**

```bash
git add Sources Tests
git commit -m "Complete selection overlay: frozen background, magnifier, snapping, window pick"
```

---

### Task 15: QuickPreviewPanel

Depends on Tasks 5, 9, 13. Floating thumbnail at the bottom-right of the screen under the cursor. Fade + 8 pt slide in (180 ms ease-out), fade out (120 ms). Hover pauses the auto-dismiss timer (`PreviewTiming`). Buttons appear for the actions that have handlers; Phase 1 wires only "Reveal". Dragging the thumbnail drags the file. No automated test beyond `PreviewTiming`; manual check below.

**Files:**
- Create: `Sources/MiracleShotUI/Preview/QuickPreviewPanel.swift`
- Create: `Sources/MiracleShotUI/Preview/PreviewContentView.swift`
- Create: `Sources/MiracleShotUI/Support/BrandButton.swift`

**Step 1: Implement a brand-styled button**

`Sources/MiracleShotUI/Support/BrandButton.swift`:
```swift
import AppKit
import MiracleShotCore

/// Flat button on ink3 with bone text. Keyboard focus ring off; hover turns the text lime.
@MainActor
final class BrandButton: NSButton {
    private var tracking: NSTrackingArea?

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = BrandPalette.ink3.cgColor()
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = BrandPalette.line.cgColor()
        font = .systemFont(ofSize: 12, weight: .medium)
        setTitleColor(BrandPalette.bone)
        focusRingType = .none
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func setTitleColor(_ color: BrandColor) {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color.nsColor(), .font: font ?? .systemFont(ofSize: 12, weight: .medium),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setTitleColor(BrandPalette.lime) }
    override func mouseExited(with event: NSEvent) { setTitleColor(BrandPalette.bone) }
}
```

**Step 2: Implement the content view**

`Sources/MiracleShotUI/Preview/PreviewContentView.swift`:
```swift
import AppKit
import MiracleShotCore
import UniformTypeIdentifiers

/// Thumbnail plus action buttons. Reports hover to the owner and starts a file drag from the thumbnail.
@MainActor
final class PreviewContentView: NSView, NSDraggingSource {
    static let maxThumbnail = NSSize(width: 240, height: 150)

    var onHover: ((Bool) -> Void)?
    var onPrimaryAction: (() -> Void)?

    private let capture: Capture
    private let fileURL: URL?
    private let thumbnail = NSImageView()
    private var tracking: NSTrackingArea?
    private var mouseDownPoint: NSPoint?

    init(capture: Capture, fileURL: URL?, buttons: [BrandButton]) {
        self.capture = capture
        self.fileURL = fileURL
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = BrandPalette.ink2.cgColor()
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = BrandPalette.line.cgColor()

        let image = NSImage(cgImage: capture.image, size: capture.bounds.size)
        thumbnail.image = image
        thumbnail.imageScaling = .scaleProportionallyDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 6
        thumbnail.layer?.masksToBounds = true
        let fit = Self.fit(capture.bounds.size, into: Self.maxThumbnail)
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.widthAnchor.constraint(equalToConstant: fit.width).isActive = true
        thumbnail.heightAnchor.constraint(equalToConstant: fit.height).isActive = true

        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 6

        let stack = NSStackView(views: buttons.isEmpty ? [thumbnail] : [thumbnail, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    static func fit(_ size: CGSize, into box: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return NSSize(width: 60, height: 60) }
        let ratio = min(box.width / size.width, box.height / size.height, 1)
        return NSSize(width: max(60, (size.width * ratio).rounded()), height: max(40, (size.height * ratio).rounded()))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    // MARK: Click and drag on the thumbnail

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = thumbnail.frame.contains(point) ? point : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard abs(point.x - start.x) > 4 || abs(point.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        let item = NSPasteboardItem()
        if let fileURL {
            item.setString(fileURL.absoluteString, forType: .fileURL)
        } else if let png = ImageCodec.pngData(from: capture.image) {
            item.setData(png, forType: .png)
        }
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(thumbnail.frame, contents: thumbnail.image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownPoint != nil { onPrimaryAction?() }
        mouseDownPoint = nil
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
```

**Step 3: Implement the panel**

`Sources/MiracleShotUI/Preview/QuickPreviewPanel.swift`:
```swift
import AppKit
import MiracleShotCore

@MainActor
public final class QuickPreviewPanel: PreviewPresenting {
    public enum Action: CaseIterable, Sendable {
        case edit, pin, ocr, ai, reveal

        var title: String {
            switch self {
            case .edit: return "Edit"
            case .pin: return "Pin"
            case .ocr: return "OCR"
            case .ai: return "AI"
            case .reveal: return "Reveal"
            }
        }
    }

    public typealias Handler = @MainActor (Capture, URL?) -> Void

    /// Buttons are shown for exactly these actions, in `Action.allCases` order.
    public var handlers: [Action: Handler] = [:]
    public var timeout: TimeInterval = 6

    private var panel: NSPanel?
    private var timing: PreviewTiming?
    private var timer: Timer?
    private var onDismiss: (@MainActor () -> Void)?
    private var current: (capture: Capture, fileURL: URL?)?

    public init() {}

    public func show(capture: Capture, fileURL: URL?, onDismiss: @escaping @MainActor () -> Void) {
        dismiss(animated: false)
        self.onDismiss = onDismiss
        current = (capture, fileURL)

        let buttons = Action.allCases.filter { handlers[$0] != nil }.map { action -> BrandButton in
            let b = BrandButton(title: action.title, target: self, action: #selector(buttonPressed(_:)))
            b.tag = Action.allCases.firstIndex(of: action)!
            return b
        }
        let content = PreviewContentView(capture: capture, fileURL: fileURL, buttons: buttons)
        content.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        content.onPrimaryAction = { [weak self] in self?.run(self?.handlers[.edit] != nil ? .edit : .reveal) }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize

        let screen = NSScreen.underCursor ?? NSScreen.screens[0]
        let finalOrigin = NSPoint(x: screen.visibleFrame.maxX - size.width - 16, y: screen.visibleFrame.minY + 16)
        let panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: finalOrigin.x, y: finalOrigin.y - 8), size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.contentView = content
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(finalOrigin)
        }
        self.panel = panel

        timing = PreviewTiming(duration: timeout, now: Self.now())
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    public func dismiss(animated: Bool) {
        timer?.invalidate()
        timer = nil
        timing = nil
        guard let panel else { return }
        self.panel = nil
        let finish: @MainActor () -> Void = { [weak self] in
            panel.orderOut(nil)
            let callback = self?.onDismiss
            self?.onDismiss = nil
            self?.current = nil
            callback?()
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: { Task { @MainActor in finish() } })
        } else {
            finish()
        }
    }

    // MARK: - Private

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func tick() {
        guard timing != nil else { return }
        if timing!.tick(now: Self.now()) { dismiss(animated: true) }
    }

    private func hoverChanged(_ inside: Bool) {
        if inside { timing?.hoverBegan(now: Self.now()) } else { timing?.hoverEnded(now: Self.now()) }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        run(Action.allCases[sender.tag])
    }

    private func run(_ action: Action) {
        guard let current, let handler = handlers[action] else { return }
        let payload = current
        dismiss(animated: true)
        handler(payload.capture, payload.fileURL)
    }
}
```

**Step 4: Build**

Run: `swift build`
Expected: no errors. Do not wire it into `AppDelegate` here; Task 18 does the integration.

**Step 5: Commit**

```bash
git add Sources/MiracleShotUI/Preview Sources/MiracleShotUI/Support/BrandButton.swift
git commit -m "Add floating quick preview panel with hover pause and file drag"
```

**Manual check (after Task 18):**
1. After a capture the preview slides up 8 pt while fading in at the bottom-right; it disappears after 6 s with a 120 ms fade.
2. Moving the cursor over it stops the countdown; leaving resumes it with the remaining time.
3. Dragging the thumbnail into Finder copies the PNG file; into Slack or Notes inserts the image.
4. "Reveal" opens Finder with the file selected. Clicking the thumbnail does the same in Phase 1.
5. Capturing again while a preview is visible replaces it and the state machine keeps working (a third capture is possible).

---

### Task 16: History menu

Depends on Tasks 6, 13. A "History" submenu in the status menu: last N captures with a small thumbnail, file name and "W × H · time ago"; click reveals the file in Finder; "Clear History" at the bottom. Formatting is a pure Core function with tests.

**Files:**
- Create: `Sources/MiracleShotCore/Storage/HistoryPresentation.swift`
- Create: `Sources/MiracleShotUI/History/HistoryMenuBuilder.swift`
- Test: `Tests/MiracleShotCoreTests/HistoryPresentationTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import MiracleShotCore

final class HistoryPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_394_709)

    private func entry(secondsAgo: TimeInterval, path: String = "/tmp/Miracle Shot 2026-09-14 at 14.05.09.png") -> HistoryEntry {
        HistoryEntry(path: path, date: now.addingTimeInterval(-secondsAgo), width: 1200, height: 800, sourceApp: "Safari")
    }

    func testTitleIsFileNameWithoutExtension() {
        XCTAssertEqual(HistoryPresentation.title(for: entry(secondsAgo: 0)), "Miracle Shot 2026-09-14 at 14.05.09")
    }

    func testSubtitleCombinesSizeAndRelativeTime() {
        XCTAssertEqual(HistoryPresentation.subtitle(for: entry(secondsAgo: 5), now: now), "1200 × 800 · just now")
        XCTAssertEqual(HistoryPresentation.subtitle(for: entry(secondsAgo: 90), now: now), "1200 × 800 · 1 min ago")
        XCTAssertEqual(HistoryPresentation.subtitle(for: entry(secondsAgo: 3 * 3600), now: now), "1200 × 800 · 3 h ago")
        XCTAssertEqual(HistoryPresentation.subtitle(for: entry(secondsAgo: 2 * 86400), now: now), "1200 × 800 · 2 d ago")
    }

    func testRelativeTimeBoundaries() {
        XCTAssertEqual(HistoryPresentation.relativeTime(seconds: 59), "just now")
        XCTAssertEqual(HistoryPresentation.relativeTime(seconds: 60), "1 min ago")
        XCTAssertEqual(HistoryPresentation.relativeTime(seconds: 3599), "59 min ago")
        XCTAssertEqual(HistoryPresentation.relativeTime(seconds: 3600), "1 h ago")
        XCTAssertEqual(HistoryPresentation.relativeTime(seconds: 86400), "1 d ago")
    }
}
```

Run: `swift test --filter HistoryPresentationTests`
Expected: compile error.

**Step 2: Implement**

`Sources/MiracleShotCore/Storage/HistoryPresentation.swift`:
```swift
import Foundation

public enum HistoryPresentation {
    public static func title(for entry: HistoryEntry) -> String {
        ((entry.path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    public static func subtitle(for entry: HistoryEntry, now: Date = Date()) -> String {
        "\(entry.width) × \(entry.height) · \(relativeTime(seconds: now.timeIntervalSince(entry.date)))"
    }

    public static func relativeTime(seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(s / 60) min ago"
        case ..<86400: return "\(s / 3600) h ago"
        default: return "\(s / 86400) d ago"
        }
    }
}
```

`Sources/MiracleShotUI/History/HistoryMenuBuilder.swift`:
```swift
import AppKit
import MiracleShotCore

/// Builds the History submenu. Thumbnails are loaded lazily and cached by path.
@MainActor
public final class HistoryMenuBuilder {
    public var onReveal: ((HistoryEntry) -> Void)?
    public var onClear: (() -> Void)?
    private var thumbnails: [String: NSImage] = [:]

    public init() {}

    public func menu(for history: HistoryIndex) -> NSMenu {
        let menu = NSMenu(title: "History")
        if history.entries.isEmpty {
            let empty = NSMenuItem(title: "No captures yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return menu
        }
        for entry in history.entries {
            let item = NSMenuItem(title: HistoryPresentation.title(for: entry), action: #selector(reveal(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id.uuidString
            item.image = thumbnail(for: entry)
            item.attributedTitle = attributedTitle(for: entry)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear History", action: #selector(clear(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        currentEntries = history.entries
        return menu
    }

    private var currentEntries: [HistoryEntry] = []

    private func attributedTitle(for entry: HistoryEntry) -> NSAttributedString {
        let title = NSMutableAttributedString(string: HistoryPresentation.title(for: entry) + "\n",
                                              attributes: [.font: NSFont.menuFont(ofSize: 13)])
        title.append(NSAttributedString(string: HistoryPresentation.subtitle(for: entry), attributes: [
            .font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return title
    }

    private func thumbnail(for entry: HistoryEntry) -> NSImage? {
        if let cached = thumbnails[entry.path] { return cached }
        guard let cg = ImageCodec.image(at: URL(fileURLWithPath: entry.path)) else { return nil }
        let image = NSImage(cgImage: cg, size: PreviewContentView.fit(CGSize(width: cg.width, height: cg.height),
                                                                       into: NSSize(width: 48, height: 32)))
        thumbnails[entry.path] = image
        return image
    }

    @objc private func reveal(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let entry = currentEntries.first(where: { $0.id.uuidString == raw }) else { return }
        onReveal?(entry)
    }

    @objc private func clear(_ sender: NSMenuItem) { onClear?() }
}
```

Run: `swift test --filter HistoryPresentationTests && swift build`
Expected: 3 tests pass, build clean.

**Step 3: Commit**

```bash
git add Sources/MiracleShotCore/Storage/HistoryPresentation.swift Sources/MiracleShotUI/History Tests/MiracleShotCoreTests/HistoryPresentationTests.swift
git commit -m "Add history presentation and menu builder"
```

---

### Task 17: Settings window (SwiftUI)

Depends on Tasks 7, 13. A single window: three hotkey fields (validated with `HotkeySpec`), save folder with "Choose…" (NSOpenPanel), naming template with a live example, preview timeout slider, history limit. Every change is applied immediately through `onChange`. No automated UI test; parsing and templates are already covered.

**Files:**
- Create: `Sources/MiracleShotUI/Settings/SettingsView.swift`
- Create: `Sources/MiracleShotUI/Settings/SettingsWindowController.swift`

**Step 1: Implement the view**

`Sources/MiracleShotUI/Settings/SettingsView.swift`:
```swift
import AppKit
import MiracleShotCore
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: Settings {
        didSet { onChange?(settings) }
    }
    @Published var hotkeyText: [CaptureAction: String]
    var onChange: ((Settings) -> Void)?

    init(settings: Settings) {
        self.settings = settings
        self.hotkeyText = Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { ($0, settings.hotkeys[$0]?.description ?? "") })
    }

    func hotkeyError(for action: CaptureAction) -> String? {
        let text = hotkeyText[action] ?? ""
        if text.isEmpty { return nil }
        return HotkeySpec(parsing: text) == nil ? "Use modifiers plus a key, e.g. shift+cmd+4" : nil
    }

    func commitHotkey(for action: CaptureAction) {
        let text = hotkeyText[action] ?? ""
        if text.isEmpty {
            settings.hotkeys.removeValue(forKey: action)
        } else if let spec = HotkeySpec(parsing: text) {
            settings.hotkeys[action] = spec
            hotkeyText[action] = spec.description
        }
    }

    var namingExample: String {
        settings.namingTemplate.fileName(date: Date(), appName: "Safari", sequence: 1)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Hotkeys") {
                ForEach(CaptureAction.allCases, id: \.self) { action in
                    VStack(alignment: .leading, spacing: 2) {
                        TextField(action.title, text: Binding(
                            get: { model.hotkeyText[action] ?? "" },
                            set: { model.hotkeyText[action] = $0 }
                        ))
                        .onSubmit { model.commitHotkey(for: action) }
                        if let error = model.hotkeyError(for: action) {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                Text("Modifiers: ctrl, opt, shift, cmd. Keys: letters, digits, f1-f12, space, arrows. Press Return to apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Files") {
                HStack {
                    TextField("Save folder", text: $model.settings.saveDirectoryPath)
                    Button("Choose…") { chooseFolder() }
                }
                TextField("File name template", text: $model.settings.namingTemplate.pattern)
                Text("Example: \(model.namingExample)").font(.caption).foregroundStyle(.secondary)
            }
            Section("Behavior") {
                Slider(value: $model.settings.previewTimeout, in: 2...15, step: 1) {
                    Text("Preview stays \(Int(model.settings.previewTimeout)) s")
                }
                Stepper("Keep \(model.settings.historyLimit) captures in history", value: $model.settings.historyLimit, in: 5...200, step: 5)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.vertical, 8)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.settings.saveDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.saveDirectoryPath = url.path
        }
    }
}
```

**Step 2: Implement the window controller**

`Sources/MiracleShotUI/Settings/SettingsWindowController.swift`:
```swift
import AppKit
import MiracleShotCore
import SwiftUI

@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?
    private var model: SettingsModel?
    private let onChange: (Settings) -> Void

    public init(onChange: @escaping (Settings) -> Void) {
        self.onChange = onChange
    }

    public func show(settings: Settings) {
        if let window {
            model?.settings = settings
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = SettingsModel(settings: settings)
        model.onChange = { [weak self] in self?.onChange($0) }
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Miracle Shot Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        self.model = model
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
```

Run: `swift build`
Expected: clean build.

**Step 3: Commit**

```bash
git add Sources/MiracleShotUI/Settings
git commit -m "Add settings window"
```

---

### Task 18: Integrate preview, history and settings into the app

Depends on Tasks 14–17. Only `AppDelegate.swift` changes here.

**Files:**
- Modify: `Sources/MiracleShotUI/App/AppDelegate.swift`

**Step 1: Rewrite `AppDelegate`**

```swift
import AppKit
import MiracleShotCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeys: HotkeyManager!
    private(set) var coordinator: CaptureCoordinator!
    private let toast = ToastPresenter()
    private let preview = QuickPreviewPanel()
    private let historyMenu = HistoryMenuBuilder()
    private var settingsWindow: SettingsWindowController!
    private var settings = Settings.default

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings = Settings.load()
        preview.timeout = settings.previewTimeout
        preview.handlers[.reveal] = { _, url in
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }

        let captureService = ScreenCaptureService()
        coordinator = CaptureCoordinator(
            settings: settings,
            historyURL: Settings.historyURL,
            capture: captureService,
            selection: SelectionOverlayController(capture: captureService, windowList: CGWindowListProvider()),
            clipboard: ClipboardService(),
            files: FileSaveService(),
            notifications: toast,
            preview: preview
        )
        coordinator.onHistoryChange = { [weak self] _ in self?.rebuildMenu() }

        historyMenu.onReveal = { entry in
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
        }
        historyMenu.onClear = { [weak self] in
            guard let self else { return }
            for entry in coordinator.history.entries { coordinator.removeFromHistory(id: entry.id) }
        }

        settingsWindow = SettingsWindowController { [weak self] updated in self?.apply(updated) }

        hotkeys = HotkeyManager { [weak self] action in self?.trigger(action) }
        registerHotkeys()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MS"
        rebuildMenu()

        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
    }

    // MARK: - Actions

    private func trigger(_ action: CaptureAction) {
        Task { await coordinator.perform(action) }
    }

    private func apply(_ updated: Settings) {
        let hotkeysChanged = updated.hotkeys != settings.hotkeys
        settings = updated
        coordinator.settings = updated
        preview.timeout = updated.previewTimeout
        try? updated.save()
        if hotkeysChanged { registerHotkeys() }
        rebuildMenu()
    }

    private func registerHotkeys() {
        let failed = hotkeys.register(settings.hotkeys)
        if !failed.isEmpty {
            toast.post(title: "Some hotkeys are taken",
                       body: failed.map(\.title).joined(separator: ", ") + ". Change them in Settings.", isError: true)
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        for action in CaptureAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(menuCapture(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            if let spec = settings.hotkeys[action] { item.toolTip = spec.description }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let history = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        history.submenu = historyMenu.menu(for: coordinator.history)
        menu.addItem(history)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(withTitle: "Quit Miracle Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func menuCapture(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = CaptureAction(rawValue: raw) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.trigger(action) }
    }

    @objc private func openSettings() {
        settingsWindow.show(settings: settings)
    }
}
```

**Step 2: Full test run and build**

Run: `swift test && scripts/build-app.sh --install && open "/Applications/Miracle Shot.app"`
Expected: all tests green; app installed in /Applications.

**Phase 1 manual checklist (reviewer):**
1. Everything from Task 13 and Task 14 still holds.
2. Preview: appears bottom-right, pauses on hover, "Reveal" opens Finder, drag into Finder copies the file.
3. History submenu lists captures newest first with thumbnails and "W × H · time ago"; clicking reveals the file; "Clear History" empties it and `~/Library/Application Support/Miracle Shot/history.json` is rewritten.
4. Settings: change area hotkey to `ctrl+opt+1`, press Return, close the window, the new hotkey works and the old one does nothing; `settings.json` contains it; relaunch keeps it.
5. Settings: choose a folder on the Desktop; the next capture lands there. Point the folder at `/System/x`: the capture lands in `~/Pictures/Miracle Shot` and a non-error toast explains why.
6. Settings: template `{app}-{seq}` produces `Safari-1.png`, `Safari-2.png` for two window captures of Safari.
7. Preview timeout set to 2 s: preview disappears after 2 s.
8. Corrupt `settings.json` by hand (write `garbage`), relaunch: app starts with defaults, `settings.json.broken` exists.

**Step 3: Commit and tag**

```bash
git add Sources
git commit -m "Integrate preview, history menu and settings window"
git tag phase-1-complete
```

---

## Phase 1 done when

- `swift test` is green, `scripts/build-app.sh --install` produces a working app.
- The manual checklist above passes on the real machine, including one multi-display check if a second display is available.
- `docs/plans/2026-09-14-miracle-shot-design.md` still matches what was built; if a decision changed during implementation, the design doc is updated in the same commit.
