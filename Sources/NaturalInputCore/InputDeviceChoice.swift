public enum InputDeviceChoice {
    public static let defaultsKey = "inputDeviceUID"

    public struct Device: Equatable, Sendable {
        public let id: UInt32
        public let uid: String
        public let name: String
        public let isBluetooth: Bool
        public init(id: UInt32, uid: String, name: String, isBluetooth: Bool) {
            self.id = id; self.uid = uid; self.name = name; self.isBluetooth = isBluetooth
        }
    }

    public enum Resolution: Equatable, Sendable {
        case system(missingChoice: Bool)
        case device(UInt32)
    }

    public static func resolve(savedUID: String?, available: [Device]) -> Resolution {
        guard let uid = savedUID, !uid.isEmpty else { return .system(missingChoice: false) }
        if let d = available.first(where: { $0.uid == uid }) { return .device(d.id) }
        return .system(missingChoice: true)
    }

    public static func label(_ d: Device) -> String {
        d.isBluetooth ? "\(d.name)（藍牙，收音較差）" : d.name
    }
}
