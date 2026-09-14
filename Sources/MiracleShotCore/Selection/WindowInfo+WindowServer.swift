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
