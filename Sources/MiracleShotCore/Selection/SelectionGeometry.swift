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

    /// Snaps each edge independently to the nearest window edge within `threshold`. The result never inverts,
    /// but it can collapse to zero width or height when both opposite edges snap to the same line; callers
    /// must reject selections smaller than one point.
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

    /// Magnifier sits bottom-right of the cursor and flips to the other side near the right and bottom edges.
    /// After flipping it is clamped into `screen`, which only matters when the screen is narrower than `2 * (size + offset)`.
    public static func magnifierFrame(cursor: CGPoint, size: CGFloat, offset: CGFloat, in screen: CGRect) -> CGRect {
        var x = cursor.x + offset
        var y = cursor.y + offset
        if x + size > screen.maxX { x = cursor.x - offset - size }
        if y + size > screen.maxY { y = cursor.y - offset - size }
        x = max(screen.minX, min(x, screen.maxX - size))
        y = max(screen.minY, min(y, screen.maxY - size))
        return CGRect(x: x, y: y, width: size, height: size)
    }

    /// Rounds the corners to device pixels; width and height are derived from the rounded corners so the
    /// right and bottom edges land on the same pixel a rounded `maxX`/`maxY` would.
    public static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        func r(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let minX = r(rect.minX), minY = r(rect.minY), maxX = r(rect.maxX), maxY = r(rect.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// AppKit <-> CoreGraphics global coordinate flip. Applying it twice returns the input.
    public static func flipped(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    public static func flipped(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}
