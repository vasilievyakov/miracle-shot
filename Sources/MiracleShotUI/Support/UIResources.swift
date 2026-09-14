import Foundation

public enum UIResources {
    public static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("MiracleShot_MiracleShotUI.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
