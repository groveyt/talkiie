import Foundation
import NaturalInputCore

@MainActor
final class ThemeTrialPreview: ObservableObject {
    static let shared = ThemeTrialPreview()
    @Published private(set) var active: HUDTheme?

    private init() {}

    func start(_ theme: HUDTheme) {}
    func stop() {}
}

#if DEBUG
extension HUDSelfTest {
    static func themeTrialPreviewBehaves() async -> Bool {
        let trial = ThemeTrialPreview.shared
        let savedStored = UserDefaults.standard.string(forKey: HUDTheme.defaultsKey)
        defer {
            if let savedStored { UserDefaults.standard.set(savedStored, forKey: HUDTheme.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: HUDTheme.defaultsKey) }
        }
        UserDefaults.standard.set(HUDTheme.classic.rawValue, forKey: HUDTheme.defaultsKey)
        trial.start(.aurora)
        return trial.active == nil && HUDStyle.theme == .classic && !RecordingHUD.isVisible && !RecordingHUD.glowVisible
            && UserDefaults.standard.string(forKey: HUDTheme.defaultsKey) == HUDTheme.classic.rawValue
    }
}
#endif
