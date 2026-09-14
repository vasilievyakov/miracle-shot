import CoreGraphics
import Foundation

public enum ArrowGeometry {
    private static let halfAngle: CGFloat = 28 * .pi / 180

    /// Head length is `max(12, lineWidth * 4)`, half-angle 28 degrees. Returns the three points of the filled
    /// head (tip == `to`) and the point where the shaft should stop (inside the head) so the stroke does not
    /// poke out. For a zero-length arrow, tip == left == right == shaftEnd == `to`.
    public static func head(from: CGPoint, to: CGPoint, lineWidth: CGFloat)
        -> (tip: CGPoint, left: CGPoint, right: CGPoint, shaftEnd: CGPoint) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        guard dx != 0 || dy != 0 else {
            return (tip: to, left: to, right: to, shaftEnd: to)
        }
        let headLength = max(12, lineWidth * 4)
        let backAngle = atan2(dy, dx) + .pi
        let left = to.offset(by: headLength, at: backAngle - halfAngle)
        let right = to.offset(by: headLength, at: backAngle + halfAngle)
        let shaftEnd = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        return (tip: to, left: left, right: right, shaftEnd: shaftEnd)
    }
}

private extension CGPoint {
    func offset(by distance: CGFloat, at angle: CGFloat) -> CGPoint {
        CGPoint(x: x + distance * cos(angle), y: y + distance * sin(angle))
    }
}
