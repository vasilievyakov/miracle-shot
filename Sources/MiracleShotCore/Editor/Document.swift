import CoreGraphics
import Foundation

/// The editor's in-memory document: the source screenshot plus every mutation the user has made.
/// `Equatable` compares `source` by identity (`===`); everything else structurally.
public struct Document: Sendable, Equatable {
    public let source: CGImage
    public let scaleFactor: CGFloat
    public var annotations: [Annotation]
    public var background: BackgroundPreset?
    /// In source pixels; nil means the full image.
    public var cropRect: CGRect?

    public init(source: CGImage, scaleFactor: CGFloat, annotations: [Annotation] = [], background: BackgroundPreset? = nil,
                cropRect: CGRect? = nil) {
        self.source = source
        self.scaleFactor = scaleFactor
        self.annotations = annotations
        self.background = background
        self.cropRect = cropRect
    }

    /// Source image size in pixels.
    public var sourceSize: CGSize { CGSize(width: source.width, height: source.height) }

    /// `cropRect` (or the full image), intersected with the image bounds and rounded outward to integers.
    public var effectiveCrop: CGRect {
        let full = CGRect(origin: .zero, size: sourceSize)
        let intersection = (cropRect ?? full).intersection(full)
        guard !intersection.isNull, !intersection.isEmpty else { return full }
        return intersection.integral
    }

    /// Appends `annotation`, then renumbers steps.
    public mutating func add(_ annotation: Annotation) {
        annotations.append(annotation)
        normalizeSteps()
    }

    /// Replaces the annotation with the same id; no-op if absent.
    public mutating func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    /// Removes the annotation with `id`, then renumbers steps.
    public mutating func remove(id: UUID) {
        annotations.removeAll { $0.id == id }
        normalizeSteps()
    }

    public mutating func bringToFront(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations.append(annotations.remove(at: index))
    }

    public func annotation(id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    /// Renumbers `step` annotations 1...n in array order.
    public mutating func normalizeSteps() {
        var number = 1
        for index in annotations.indices {
            if case .step(let center, _) = annotations[index].shape {
                annotations[index].shape = .step(center: center, number: number)
                number += 1
            }
        }
    }

    /// The number the next step gets.
    public var nextStepNumber: Int {
        annotations.filter {
            if case .step = $0.shape { return true }
            return false
        }.count + 1
    }

    public static func == (lhs: Document, rhs: Document) -> Bool {
        lhs.source === rhs.source && lhs.scaleFactor == rhs.scaleFactor && lhs.annotations == rhs.annotations
            && lhs.background == rhs.background && lhs.cropRect == rhs.cropRect
    }
}
