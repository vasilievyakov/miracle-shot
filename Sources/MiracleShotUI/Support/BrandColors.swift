import AppKit
import MiracleShotCore

extension BrandColor {
    public func nsColor(alpha: CGFloat = 1) -> NSColor {
        NSColor(cgColor: cgColor(alpha: alpha)) ?? .black
    }
}
