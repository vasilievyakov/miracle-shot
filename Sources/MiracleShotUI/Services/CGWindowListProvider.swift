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
