import Foundation

/// Locates this target's resource bundle both when running from `swift run`/tests and from the packaged app.
public enum CoreResources {
    public static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("MiracleShot_MiracleShotCore.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
