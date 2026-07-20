import Foundation

enum Settings {
    private static let includeFinderKey = "includeFinderWindows"

    // Defaults to false: Finder windows stay out of the switcher unless enabled.
    static var includeFinderWindows: Bool {
        get { UserDefaults.standard.bool(forKey: includeFinderKey) }
        set { UserDefaults.standard.set(newValue, forKey: includeFinderKey) }
    }
}
