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
