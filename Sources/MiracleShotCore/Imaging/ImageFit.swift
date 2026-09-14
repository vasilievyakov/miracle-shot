import CoreGraphics

/// Scales a size down proportionally to fit a box, never up, with a small floor so tiny images stay visible.
public enum ImageFit {
    public static func size(_ size: CGSize, into box: CGSize, minimum: CGSize = CGSize(width: 60, height: 40)) -> CGSize {
        guard size.width > 0, size.height > 0 else { return minimum }
        let ratio = min(box.width / size.width, box.height / size.height, 1)
        return CGSize(width: max(minimum.width, (size.width * ratio).rounded()),
                      height: max(minimum.height, (size.height * ratio).rounded()))
    }
}
