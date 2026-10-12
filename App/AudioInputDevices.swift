import AppKit
import CoreAudio
import SwiftUI
import NaturalInputCore

enum AudioInputDevices {

    static func all() -> [InputDeviceChoice.Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            let transport = uint32(id, kAudioDevicePropertyTransportType)
            let bt = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
            return InputDeviceChoice.Device(id: id, uid: uid, name: name, isBluetooth: bt)
        }
    }

    static func systemDefaultID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    static func systemDefaultOutputID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        let t = uint32(id, kAudioDevicePropertyTransportType)
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    static var savedUID: String? { UserDefaults.standard.string(forKey: InputDeviceChoice.defaultsKey) }

    static func resolvedDeviceID() -> AudioDeviceID? {
        if case .device(let id) = InputDeviceChoice.resolve(savedUID: savedUID, available: all()) { return id }
        return nil
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr,
              let s = value?.takeRetainedValue() else { return nil }
        return s as String
    }

    private static func uint32(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v)
        return v
    }
}

struct InputDeviceSettingsSection: View {
    @AppStorage(InputDeviceChoice.defaultsKey) private var savedUID = ""
    @State private var devices: [InputDeviceChoice.Device] = AudioInputDevices.all()
    @ObservedObject private var refresh = SettingsRefresh.shared

    var body: some View {
        let systemID = AudioInputDevices.systemDefaultID()
        let systemName = devices.first { $0.id == systemID }.map(InputDeviceChoice.label) ?? "未知"
        let resolution = InputDeviceChoice.resolve(savedUID: savedUID, available: devices)
        Picker("使用的麥克風", selection: $savedUID) {
            Text("跟隨系統設定（目前：\(systemName)）").tag("")
            if !savedUID.isEmpty, !devices.contains(where: { $0.uid == savedUID }) {
                Text("之前選的麥克風（目前不在）").tag(savedUID)
            }
            ForEach(devices, id: \.uid) { d in
                Text(InputDeviceChoice.label(d)).tag(d.uid)
            }
        }
        .onAppear { devices = AudioInputDevices.all() }
        .onChange(of: refresh.generation) { devices = AudioInputDevices.all() }
        if case .system(missingChoice: true) = resolution {
            SettingsHelp(text: "選的麥克風目前不在，暫時用系統設定的那一支。")
        } else {
            SettingsHelp(text: "只影響 Talkiie，不改系統設定。")
        }
    }
}
