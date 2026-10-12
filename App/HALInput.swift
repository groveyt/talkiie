import AudioToolbox
import CoreAudio
import Foundation
import NaturalInputCore

final class HALInput: @unchecked Sendable {
    typealias BlockHandler = @Sendable ([Float], Double, UInt64) -> Void

    enum DeviceChange { case gone, formatChanged }

    struct Failure: Error { let status: OSStatus }

    let device: AudioDeviceID
    let sampleRate: Double
    let channels: UInt32
    var onDeviceChange: ((DeviceChange) -> Void)?

    private var unit: AudioUnit?
    private let onBlock: BlockHandler
    private let maxFrames: UInt32
    private let abl: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>]
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(device: AudioDeviceID, onBlock: @escaping BlockHandler) throws(Failure) {
        self.device = device
        self.onBlock = onBlock
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                             componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { throw Failure(status: -1) }
        var u: AudioUnit?
        var st = AudioComponentInstanceNew(comp, &u)
        guard st == noErr, let u else { throw Failure(status: st) }
        func check(_ s: OSStatus) throws(Failure) {
            if s != noErr { AudioComponentInstanceDispose(u); throw Failure(status: s) }
        }
        let u32 = UInt32(MemoryLayout<UInt32>.size)
        var one: UInt32 = 1, zero: UInt32 = 0
        try check(AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, u32))
        try check(AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &zero, u32))
        var dev = device
        try check(AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                       &dev, UInt32(MemoryLayout<AudioDeviceID>.size)))
        var current = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioUnitGetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size))
        if current != device { AudioComponentInstanceDispose(u); throw Failure(status: -2) }

        var hw = AudioStreamBasicDescription()
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hw, &size))
        guard hw.mSampleRate > 0, hw.mChannelsPerFrame > 0 else { AudioComponentInstanceDispose(u); throw Failure(status: -3) }
        var client = AudioStreamBasicDescription(
            mSampleRate: hw.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: hw.mChannelsPerFrame, mBitsPerChannel: 32, mReserved: 0)
        try check(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                       &client, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
        var frames: UInt32 = 0
        size = u32
        st = AudioUnitGetProperty(u, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &frames, &size)
        let cap = st == noErr && frames > 0 ? frames : 4096
        maxFrames = cap
        sampleRate = hw.mSampleRate
        channels = hw.mChannelsPerFrame

        abl = AudioBufferList.allocate(maximumBuffers: Int(hw.mChannelsPerFrame))
        storage = (0..<Int(hw.mChannelsPerFrame)).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: Int(cap)) }
        unit = u

        var cb = AURenderCallbackStruct(inputProc: halInputProc, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        let cbSt = AudioUnitSetProperty(u, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                        &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        if cbSt != noErr { dispose(); throw Failure(status: cbSt) }
        let initSt = AudioUnitInitialize(u)
        if initSt != noErr { dispose(); throw Failure(status: initSt) }
        listen(kAudioDevicePropertyDeviceIsAlive) { [weak self] in
            guard let self else { return }
            if !self.isAlive { self.onDeviceChange?(.gone) }
        }
        listen(kAudioDevicePropertyNominalSampleRate) { [weak self] in self?.onDeviceChange?(.formatChanged) }
    }

    func start() throws(Failure) {
        guard let unit else { throw Failure(status: -4) }
        let st = AudioOutputUnitStart(unit)
        if st != noErr { throw Failure(status: st) }
    }

    func dispose() {
        for (addr, block) in listeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(device, &a, DispatchQueue.main, block)
        }
        listeners = []
        onDeviceChange = nil
        guard let u = unit else { return }
        AudioOutputUnitStop(u)
        unit = nil
        AudioUnitUninitialize(u)
        AudioComponentInstanceDispose(u)
        for p in storage { p.deallocate() }
        storage = []
        abl.unsafeMutablePointer.deallocate()
    }

    deinit { dispose() }

    private var isAlive: Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &alive) == noErr && alive != 0
    }

    private func listen(_ selector: AudioObjectPropertySelector, _ handler: @escaping () -> Void) {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main, block) == noErr {
            listeners.append((addr, block))
        }
    }

    fileprivate func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            _ ts: UnsafePointer<AudioTimeStamp>, _ frames: UInt32) -> OSStatus {
        guard let unit, frames > 0, frames <= maxFrames else { return noErr }
        for c in 0..<Int(channels) {
            abl[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: UnsafeMutableRawPointer(storage[c]))
        }
        let st = AudioUnitRender(unit, flags, ts, 1, frames, abl.unsafeMutablePointer)
        guard st == noErr else { return st }
        let n = Int(frames)
        let chans = (0..<Int(channels)).map { Array(UnsafeBufferPointer(start: storage[$0], count: n)) }
        let mono = AudioPipeline.downmix(chans)
        let t = ts.pointee
        let capturedAt = t.mFlags.contains(.hostTimeValid)
            ? AudioConvertHostTimeToNanos(t.mHostTime)
            : DispatchTime.now().uptimeNanoseconds
        onBlock(mono, sampleRate, capturedAt)
        return noErr
    }
}

private let halInputProc: AURenderCallback = { refCon, flags, ts, _, frames, _ in
    Unmanaged<HALInput>.fromOpaque(refCon).takeUnretainedValue().render(flags, ts, frames)
}
