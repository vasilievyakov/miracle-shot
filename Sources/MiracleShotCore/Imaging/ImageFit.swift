import CoreGraphics

/// Scales a size proportionally to fit a box, never up past its natural size, except that a tiny image is
/// enlarged uniformly until it reaches `minimum` so it stays visible. Aspect ratio is always preserved.
public enum ImageFit {
    public static func size(_ size: CGSize, into box: CGSize, minimum: CGSize = CGSize(width: 60, height: 40)) -> CGSize {
        guard size.width > 0, size.height > 0 else { return minimum }
        var scale = min(box.width / size.width, box.height / size.height, 1)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        if fitted.width < minimum.width && fitted.height < minimum.height {
            // Both sides are tiny: grow uniformly until the first side reaches its minimum.
            scale *= min(minimum.width / fitted.width, minimum.height / fitted.height)
        }
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}
