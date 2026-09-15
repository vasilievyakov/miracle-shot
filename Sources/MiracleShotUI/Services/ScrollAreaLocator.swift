import ApplicationServices
import CoreGraphics
import Foundation
import MiracleShotCore

@MainActor public protocol ScrollAreaLocating: AnyObject {
    /// The frame (CG global points) of the innermost scroll area under `point`, if Accessibility reveals one.
    func scrollArea(near point: CGPoint) -> CGRect?
}

/// Asks Accessibility for the element under a point and walks up to the nearest `AXScrollArea`. Attribute
/// names are spelled out: the `kAX...` C globals are not concurrency-safe under Swift 6.
@MainActor
public final class ScrollAreaLocator: ScrollAreaLocating {
    private static let maxDepth = 24

    public init() {}

    public func scrollArea(near point: CGPoint) -> CGRect? {
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &found) == .success,
              var element = found else { return nil }
        for _ in 0..<Self.maxDepth {
            if attribute(of: element, "AXRole") as? String == "AXScrollArea" {
                return frame(of: element)
            }
            guard let parent = attribute(of: element, "AXParent"), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = parent as! AXUIElement
        }
        return nil
    }

    private func attribute(of element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(of: element, "AXPosition"), CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = attribute(of: element, "AXSize"), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}
