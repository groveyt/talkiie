import AppKit
import NaturalInputCore
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    static var defaultOn: Bool { Edition.launchAtLoginDefaultOn }

    @Published private(set) var status: LaunchAtLoginPolicy.Status = LaunchAtLogin.readStatus()
    @Published private(set) var registerFailed = false

    static func readStatus() -> LaunchAtLoginPolicy.Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .notRegistered
        @unknown default: return .notRegistered
        }
    }

    func refresh() { status = Self.readStatus() }

    func autoRegisterIfNeeded() {
        let d = UserDefaults.standard
        let choice = d.object(forKey: LaunchAtLoginPolicy.userChoiceKey) as? Bool
        guard LaunchAtLoginPolicy.shouldAutoRegister(consented: ConsentStore.allowsCapture, defaultOn: Self.defaultOn,
                                                     alreadyAutoRegistered: d.bool(forKey: LaunchAtLoginPolicy.autoRegisteredKey),
                                                     userChoice: choice) else { return }
        d.set(true, forKey: LaunchAtLoginPolicy.autoRegisteredKey)
        let ok = (try? SMAppService.mainApp.register()) != nil
        Log.record(.launchAtLogin(on: true, byUser: false, ok: ok))
        registerFailed = !ok
        refresh()
    }

    func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: LaunchAtLoginPolicy.userChoiceKey)
        let ok: Bool
        if on {
            ok = (try? SMAppService.mainApp.register()) != nil
        } else {
            ok = (try? SMAppService.mainApp.unregister()) != nil
        }
        Log.record(.launchAtLogin(on: on, byUser: true, ok: ok))
        registerFailed = on && !ok
        refresh()
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
