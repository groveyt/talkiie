import SwiftUI
import TalkiieLicensing

@MainActor
final class PublicLicense {
    static let shared = PublicLicense()
    let entitlement = Entitlement.locked
    func installAtLaunch() {}
}

struct PublicSpeedSection: View {
    var body: some View { EmptyView() }
}

struct PublicPlusSection: View {
    var body: some View { EmptyView() }
}
