import CoreAudio
import Foundation

/// Per-display volume.
///
/// A monitor's speakers reach macOS one of two ways: as a CoreAudio output
/// device carried over HDMI/DisplayPort (the common case, and the one where
/// volume changes are exact), or only through DDC VCP 0x62. Lumen prefers
/// CoreAudio and falls back to DDC.
public final class AudioEngine {
    public static let shared = AudioEngine()

    public struct Device: Equatable {
        public let id: AudioDeviceID
        public let name: String
        public let uid: String
        public let transport: UInt32
        public var isBuiltin: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
        public var isDisplayAttached: Bool {
            transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort
        }
        public var isBluetooth: Bool {
            transport == kAudioDeviceTransportTypeBluetooth
                || transport == kAudioDeviceTransportTypeBluetoothLE
        }
        public var isAirPlay: Bool { transport == kAudioDeviceTransportTypeAirPlay }
        /// Aggregate and multi-output devices, loopback drivers, virtual mixers.
        public var isVirtual: Bool {
            transport == kAudioDeviceTransportTypeVirtual
                || transport == kAudioDeviceTransportTypeAggregate
        }

        /// How to describe this output to the user in one word.
        public var kindLabel: String {
            if isAirPlay { return "AirPlay" }
            if isBluetooth { return L10n.t("蓝牙", "Bluetooth") }
            if isBuiltin { return L10n.t("内建扬声器", "Built-in speakers") }
            if isVirtual { return L10n.t("虚拟设备", "Virtual device") }
            if isDisplayAttached { return L10n.t("显示器", "Display") }
            return L10n.t("外部设备", "External device")
        }
    }

    /// Where the sound is going right now, seen from one display.
    ///
    /// The volume keys must follow this, not the pointer: turning a monitor's
    /// speakers up while the audio is coming out of AirPods moves a slider
    /// nobody can hear.
    public enum OutputRouting: Equatable {
        /// The system output *is* this display's own audio endpoint.
        case thisDisplay(Device)
        /// Something else is playing — built-in speakers, Bluetooth, AirPlay, a DAC.
        case elsewhere(Device)
        case unknown
    }

    // 'vmvc' — the virtual main volume, the same scalar the volume keys move.
    private let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663
    private let muteSelector: AudioObjectPropertySelector = kAudioDevicePropertyMute
    private let volumeScalar: AudioObjectPropertySelector = kAudioDevicePropertyVolumeScalar

    private init() {}

    // MARK: - Enumeration

    public func outputDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutputStreams(id) else { return nil }
            return Device(id: id,
                          name: stringProperty(id, kAudioObjectPropertyName) ?? L10n.t("未知设备", "Unknown device"),
                          uid: stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "",
                          transport: numericProperty(id, kAudioDevicePropertyTransportType) ?? 0)
        }
    }

    private func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return false }
        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).contains { $0.mNumberChannels > 0 }
    }

    private func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String?
    }

    private func numericProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    // MARK: - Display pairing

    /// Best-effort match from a display to the audio device it carries.
    ///
    /// Transport is a weak signal and must not gate the name match: an Apple
    /// Studio Display carries its audio over USB, not over the video link, so
    /// requiring HDMI/DisplayPort here used to reject a device literally named
    /// after the monitor.
    public func device(for display: DisplayInfo) -> Device? {
        device(for: display, in: outputDevices())
    }

    /// Enumerating CoreAudio is not free, and a key press wants to pair every
    /// display at once — so the device list can be passed in.
    public func device(for display: DisplayInfo, in devices: [Device]) -> Device? {
        if display.isBuiltin {
            return devices.first { $0.isBuiltin }
        }

        // The built-in speakers must never be offered as an external display's
        // output, whatever the name similarity.
        let candidates = devices.filter { !$0.isBuiltin }

        if let exact = candidates.first(where: {
            $0.name.caseInsensitiveCompare(display.name) == .orderedSame
        }) { return exact }

        if let byName = candidates.first(where: {
            $0.name.localizedCaseInsensitiveContains(display.name)
                || display.name.localizedCaseInsensitiveContains($0.name)
        }) { return byName }

        // Last resort: a lone device on the video link itself.
        let onVideoLink = candidates.filter(\.isDisplayAttached)
        return onVideoLink.count == 1 ? onVideoLink[0] : nil
    }

    // MARK: - The device that is actually playing

    /// The system's current output device — what the volume keys move natively.
    public func defaultOutputDevice() -> Device? {
        defaultOutputDevice(in: outputDevices())
    }

    public func defaultOutputDevice(in devices: [Device]) -> Device? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return devices.first { $0.id == id }
    }

    /// Is this display's own audio endpoint the one the system is playing through?
    public func routing(for display: DisplayInfo) -> OutputRouting {
        routing(for: display, in: outputDevices())
    }

    public func routing(for display: DisplayInfo, in devices: [Device]) -> OutputRouting {
        guard let current = defaultOutputDevice(in: devices) else { return .unknown }
        // The built-in speakers belong to the Mac, not to its panel. Treating
        // them as the built-in display's output would hand Lumen every volume
        // key on a laptop with nothing plugged in — macOS already does that
        // job perfectly, HUD and feedback click included.
        if display.isBuiltin { return .elsewhere(current) }
        if let paired = device(for: display, in: devices), paired.id == current.id {
            return .thisDisplay(paired)
        }
        return .elsewhere(current)
    }

    /// The external display whose speakers are the current system output, if any.
    ///
    /// This is the whole test for whether Lumen may take the volume keys over:
    /// when it returns nil the sound is coming from somewhere Lumen has no
    /// business touching — AirPods, an AirPlay speaker, a USB DAC, the Mac's
    /// own speakers — and the keys belong to macOS.
    public func displayOwningOutput(among displays: [DisplayInfo]) -> (display: DisplayInfo, device: Device)? {
        let devices = outputDevices()
        guard let current = defaultOutputDevice(in: devices) else { return nil }
        for display in displays where !display.isBuiltin {
            if let paired = device(for: display, in: devices), paired.id == current.id {
                return (display, current)
            }
        }
        return nil
    }

    /// Fires when the user switches output — plugging in AirPods, picking an
    /// AirPlay speaker in Control Centre — so the menu can stop claiming a
    /// monitor's slider is what you are hearing.
    public static let defaultOutputDidChange = Notification.Name("LumenDefaultOutputDidChange")

    private var outputListener: AudioObjectPropertyListenerBlock?

    public func startWatchingDefaultOutput() {
        guard outputListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            NotificationCenter.default.post(name: AudioEngine.defaultOutputDidChange, object: nil)
        }
        guard AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                                  &address, DispatchQueue.main, listener) == noErr else {
            Log.debug("audio: could not observe the default output device")
            return
        }
        outputListener = listener
    }

    public func channel(for display: DisplayInfo) -> VolumeChannel {
        // Having a device is not enough — a DisplayPort audio endpoint often
        // exposes no volume at all, in which case DDC is the real channel.
        if let device = device(for: display), volume(of: device) != nil { return .coreAudio }
        if let ddc = DDCRegistry.shared.service(for: display), ddc.read(.volume) != nil { return .ddc }
        return .none
    }

    // MARK: - Volume

    public func volume(of display: DisplayInfo) -> Double? {
        if let device = device(for: display), let level = volume(of: device) { return level }
        return DDCRegistry.shared.service(for: display)?.read(.volume)?.percent
    }

    public func volume(of device: Device) -> Double? {
        var address = AudioObjectPropertyAddress(mSelector: virtualMainVolume,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Float32>.size)
        var value: Float32 = 0
        if AudioObjectHasProperty(device.id, &address),
           AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &value) == noErr {
            return Double(value)
        }
        // Devices without a main volume still expose per-channel scalars.
        address.mSelector = volumeScalar
        for element in UInt32(1) ... UInt32(2) {
            address.mElement = element
            size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(device.id, &address),
               AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &value) == noErr {
                return Double(value)
            }
        }
        return nil
    }

    @discardableResult
    public func setVolume(_ level: Double, for display: DisplayInfo) -> Bool {
        let clamped = min(max(level, 0), 1)
        if let device = device(for: display), volume(of: device) != nil,
           setVolume(clamped, for: device) { return true }
        guard let ddc = DDCRegistry.shared.service(for: display) else { return false }
        let maximum = ddc.read(.volume)?.maximum ?? 100
        return ddc.write(.volume, value: UInt16((clamped * Double(maximum)).rounded()))
    }

    @discardableResult
    public func setVolume(_ level: Double, for device: Device) -> Bool {
        var value = Float32(min(max(level, 0), 1))
        var address = AudioObjectPropertyAddress(mSelector: virtualMainVolume,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        let size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(device.id, &address),
           AudioObjectSetPropertyData(device.id, &address, 0, nil, size, &value) == noErr {
            return true
        }
        address.mSelector = volumeScalar
        var wrote = false
        for element in UInt32(1) ... UInt32(2) {
            address.mElement = element
            if AudioObjectHasProperty(device.id, &address),
               AudioObjectSetPropertyData(device.id, &address, 0, nil, size, &value) == noErr {
                wrote = true
            }
        }
        return wrote
    }

    // MARK: - Mute

    public func isMuted(_ display: DisplayInfo) -> Bool? {
        guard let device = device(for: display) else {
            guard let reading = DDCRegistry.shared.service(for: display)?.read(.mute) else { return nil }
            return reading.current == 1
        }
        var address = AudioObjectPropertyAddress(mSelector: muteSelector,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        guard AudioObjectHasProperty(device.id, &address),
              AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value == 1
    }

    @discardableResult
    public func setMuted(_ muted: Bool, for display: DisplayInfo) -> Bool {
        guard let device = device(for: display) else {
            // DDC audio mute: 1 mutes, 2 restores.
            return DDCRegistry.shared.service(for: display)?
                .write(.mute, value: muted ? 1 : 2) ?? false
        }
        var value: UInt32 = muted ? 1 : 0
        var address = AudioObjectPropertyAddress(mSelector: muteSelector,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device.id, &address) else { return false }
        return AudioObjectSetPropertyData(device.id, &address, 0, nil,
                                          UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
