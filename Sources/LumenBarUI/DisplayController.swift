import AppKit
import Combine
import CoreGraphics
import Foundation
import LumenBarCore
import SwiftUI

/// Everything the UI knows about one display.
public struct DisplayCard: Identifiable {
    public var info: DisplayInfo
    public var id: CGDirectDisplayID { info.id }

    var brightness: Double = 1
    var brightnessChannel: BrightnessChannel = .none
    var softwareDim: Double = 1
    var warmth: Double = 0

    var volume: Double = 0
    var volumeChannel: VolumeChannel = .none
    var isMuted = false
    var audioDeviceName: String?
    /// True when this display's own speakers are the system's current output.
    /// When it is false the slider still works, but nothing audible comes out
    /// of this display — the sound is going to `systemOutputName` instead.
    var isActiveOutput = false
    /// What is actually playing right now: "AirPods Pro", "MacBook Pro 扬声器"…
    var systemOutputName: String?
    var systemOutputKind: String?

    var currentMode: DisplayMode?
    var recommendedModes: [DisplayMode] = []
    var allModes: [DisplayMode] = []
    var refreshOptions: [DisplayMode] = []

    var colorProfileName: String?
    var contrast: Double?
    var inputSourceRaw: UInt16?
    var ddcCapabilities: DDCCapabilities?
    var hidpiModes: [DisplayMode] = []
    var rotationSupported = false
    var hasDDC = false
    var followsBuiltIn = false
    var isAsleep = false
    var isProtected = false
    var hasHiDPIOverride = false
    var ddcChannel: Int?
    var ddcChannelCount = 0
    var isLoaded = false

    var canControlBrightness: Bool { brightnessChannel != .none }
    var canControlVolume: Bool { volumeChannel != .none }
}

/// A display PWE Lumen Bar switched off, and how — the route decides how it comes back.
public struct OffDisplay: Identifiable {
    public let info: DisplayInfo
    public let method: PowerEngine.SleepMethod
    public var id: CGDirectDisplayID { info.id }
}

@MainActor
public final class DisplayController: ObservableObject {
    @Published public private(set) var cards: [DisplayCard] = []
    @Published var status: String?
    /// Installed ICC profiles are system-wide, so they are enumerated once
    /// rather than per display card.
    @Published private(set) var colorProfiles: [ColorProfile] = []
    @Published private(set) var presets: [Preset] = PresetStore.shared.presets
    @Published private(set) var languageRevision = 0
    @Published private(set) var shortcutsEnabled = HotKeyCenter.isEnabledInDefaults
    @Published private(set) var mediaKeysEnabled = MediaKeyTap.isEnabledInDefaults
    @Published private(set) var isPro = LicenseStore.shared.isPro
    /// Set by the status item. A popover sits at a higher window level than an
    /// ordinary window, so anything PWE Lumen Bar opens has to close it first or it
    /// opens underneath and looks like nothing happened.
    var dismissPopover: (() -> Void)?
    @Published private(set) var rememberEnabled = DisplaySettingsStore.shared.isEnabled
    @Published private(set) var autoDisconnectBuiltIn =
        Defaults.shared.bool(forKey: "autoDisconnectBuiltIn")
    /// Only the panel this feature put away, so manual disconnects are left alone.
    private var autoDisconnectedBuiltIn: DisplayInfo?
    /// Routes the keyboard's own brightness and volume keys to the display the
    /// pointer is on. Keys aimed at the built-in panel are declined so macOS
    /// keeps handling them natively.
    private lazy var mediaKeys = MediaKeyTap { [weak self] key, isRepeat in
        guard let self else { return false }
        let step = isRepeat ? HotKeyCenter.step / 2 : HotKeyCenter.step
        switch key {
        // Brightness belongs to the display the eyes are on.
        case .brightnessUp, .brightnessDown:
            guard let card = self.cardUnderCursor(), !card.info.isBuiltin else { return false }
            self.nudgeBrightness(by: key == .brightnessUp ? step : -step)
            return true
        // Volume belongs to whatever is playing, wherever the pointer happens
        // to be. See `takeOverVolumeKey`.
        case .volumeUp, .volumeDown, .mute:
            return self.takeOverVolumeKey(key, step: step)
        }
    }

    /// Route a volume key, or decline it.
    ///
    /// The volume keys are the one place where "the display under the pointer"
    /// is the wrong answer: volume is a property of the *output device*, not of
    /// a panel. If the sound is coming out of AirPods, an AirPlay speaker, a
    /// USB DAC or the Mac's own speakers, moving a monitor's volume would be a
    /// slider the user cannot hear — an OSD that lies. So PWE Lumen Bar takes the key
    /// only when the current system output is an external display's own
    /// speakers, and hands it back to macOS otherwise, which moves the right
    /// device and shows its native HUD.
    ///
    /// The case this wins is real: a DisplayPort audio endpoint often exposes
    /// no volume control at all (the Philips 27B1U3900 here does not), so the
    /// system keys do nothing while DDC works fine.
    private func takeOverVolumeKey(_ key: MediaKeyTap.Key, step: Double) -> Bool {
        guard let owner = AudioEngine.shared.displayOwningOutput(among: cards.map(\.info)),
              let card = cards.first(where: { $0.id == owner.display.id }),
              card.canControlVolume
        else { return false }

        // The HUD goes where the eyes are, but it is captioned with the display
        // whose speakers actually moved, so the two can never be confused.
        let hudDisplay = cardUnderCursor()?.id ?? card.id
        switch key {
        case .mute:
            toggleMute(card)
            OSDWindow.shared.show(value: card.isMuted ? card.volume : 0,
                                  symbol: "speaker.wave.2.fill",
                                  caption: card.info.name,
                                  muted: !card.isMuted, on: hudDisplay)
        default:
            let value = min(max(card.volume + (key == .volumeUp ? step : -step), 0), 1)
            setVolume(value, for: card)
            OSDWindow.shared.show(value: value, symbol: "speaker.wave.2.fill",
                                  caption: card.info.name, on: hudDisplay)
            playVolumeFeedback()
        }
        return true
    }

    /// macOS clicks on every volume key press when "Play feedback when volume
    /// is changed" is on. Consuming the key silences that click, so PWE Lumen Bar plays
    /// the same system sound itself — it goes to the output device being
    /// changed, which is the one we just established is playing.
    private func playVolumeFeedback() {
        guard Defaults.system.object(forKey: "com.apple.sound.beep.feedback") == nil
                || Defaults.system.bool(forKey: "com.apple.sound.beep.feedback") else { return }
        Self.feedbackSound?.stop()
        Self.feedbackSound?.play()
    }

    private static let feedbackSound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Media Keys.aif"
        return FileManager.default.fileExists(atPath: path) ? NSSound(contentsOfFile: path, byReference: true) : nil
    }()

    private lazy var ambientSync = AmbientSync { [weak self] display, value in
        guard let self else { return }
        HardwareQueue.shared.coalesce(key: "ambient-\(display.id)", value: value) { latest in
            BrightnessEngine.shared.setBrightness(latest, for: display)
        }
        self.update(display.id) { $0.brightness = value }
    }
    @Published private(set) var isRefreshing = false

    /// Displays PWE Lumen Bar has switched off, with the route used — a display taken
    /// off the desktop vanishes from the online list, so without this record
    /// there would be nothing left to switch it back on with.
    @Published private(set) var offDisplays: [OffDisplay] = []

    private var cancellables = Set<AnyCancellable>()
    /// Identities seen in a previous refresh — anything else just arrived.
    private var seenKeys: Set<String> = []
    /// Guards against a restore triggering a reconfiguration that restores again.
    private var restoringKeys: Set<String> = []
    /// Displays with a PWE Lumen Bar-initiated change waiting on its confirmation.
    /// Protection must not fight a change the user just asked for: the
    /// reconfiguration notification arrives long before they answer the dialog.
    private var awaitingConfirmation: Set<String> = []

    /// Renders a fixed set of cards and talks to no hardware — used by the
    /// screenshot renderer to show layouts the attached hardware cannot produce.
    public init(previewCards: [DisplayCard]) {
        self.cards = previewCards
    }

    /// Wire the global shortcuts to act on whichever display the pointer is on.
    func applyShortcutSetting(_ enabled: Bool) {
        shortcutsEnabled = enabled
        HotKeyCenter.shared.setEnabled(enabled) { [weak self] action in
            guard let self else { return }
            switch action {
            case .brightnessUp: self.nudgeBrightness(by: HotKeyCenter.step)
            case .brightnessDown: self.nudgeBrightness(by: -HotKeyCenter.step)
            case .volumeUp: self.nudgeVolume(by: HotKeyCenter.step)
            case .volumeDown: self.nudgeVolume(by: -HotKeyCenter.step)
            case .muteToggle: self.toggleMuteUnderCursor()
            case .capture: self.captureUnderCursor()
            case .sleepDisplay: self.sleepUnderCursor()
            }
        }
    }

    public init() {
        DisplayRegistry.shared.startWatching()
        NotificationCenter.default.publisher(for: DisplayRegistry.didChange)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.handleReconfiguration() }
            .store(in: &cancellables)
        // Switching to AirPods mid-session must not leave the menu claiming a
        // monitor's slider is what you are hearing.
        AudioEngine.shared.startWatchingDefaultOutput()
        NotificationCenter.default.publisher(for: AudioEngine.defaultOutputDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAudioRouting() }
            .store(in: &cancellables)
        refresh()
        colorProfiles = ColorEngine.installedDisplayProfiles()
        if HotKeyCenter.isEnabledInDefaults { applyShortcutSetting(true) }
        // Without this the Settings toggle reads ON after a relaunch while no
        // tap is installed, so the keys quietly do nothing until it is
        // switched off and on again.
        if MediaKeyTap.isEnabledInDefaults { applyMediaKeySetting(true) }
    }

    // MARK: - Loading

    public func refresh() {
        let displays = DisplayRegistry.shared.onlineDisplays()
        // Show the skeleton at once — DDC reads can take a moment and the menu
        // should never feel like it is hanging.
        let known = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        cards = displays.map { info in
            guard var existing = known[info.id] else { return DisplayCard(info: info) }
            existing.info = info
            return existing
        }

        isRefreshing = true
        Task.detached(priority: .userInitiated) {
            let loaded = displays.map { Self.load($0) }
            await MainActor.run {
                self.cards = loaded
                self.isRefreshing = false
                self.restoreNewArrivals(among: displays)
                self.applyAutoDisconnect(among: displays)
                self.refreshAmbientSync()
            }
        }
    }

    private nonisolated static func load(_ info: DisplayInfo) -> DisplayCard {
        var card = DisplayCard(info: info)
        let brightness = BrightnessEngine.shared
        card.brightnessChannel = brightness.channel(for: info)
        card.brightness = brightness.brightness(of: info) ?? 1
        card.softwareDim = brightness.softwareDim(of: info)
        card.warmth = brightness.warmth(of: info)

        let audio = AudioEngine.shared
        card.volumeChannel = audio.channel(for: info)
        card.volume = audio.volume(of: info) ?? 0
        card.isMuted = audio.isMuted(info) ?? false
        let audioDevices = audio.outputDevices()
        card.audioDeviceName = audio.device(for: info, in: audioDevices)?.name
        switch audio.routing(for: info, in: audioDevices) {
        case .thisDisplay:
            card.isActiveOutput = true
            card.systemOutputName = card.audioDeviceName
            card.systemOutputKind = nil
        case .elsewhere(let device):
            card.isActiveOutput = false
            card.systemOutputName = device.name
            card.systemOutputKind = device.kindLabel
        case .unknown:
            card.isActiveOutput = false
            card.systemOutputName = nil
            card.systemOutputKind = nil
        }

        card.colorProfileName = ColorEngine.currentProfileName(for: info.id)
        card.currentMode = ModeEngine.currentMode(for: info.id)
        card.allModes = ModeEngine.allModes(for: info.id)
        card.recommendedModes = ModeEngine.recommendedModes(for: info.id, includeLowRes: true)
        // The short list is HiDPI only — everything else lives under "all modes",
        // because a 1x mode on a Retina panel is almost never what someone wants.
        card.hidpiModes = ModeEngine.curatedModes(for: info.id)
        if let current = card.currentMode {
            let rates = ModeEngine.refreshRates(for: info.id, matching: current)
            card.refreshOptions = rates.count > 1 ? rates : []
        }
        card.rotationSupported = RotationEngine.isSupported(for: info)
        card.isAsleep = PowerEngine.sleepStates[info.persistentKey] != nil
        card.isProtected = DisplaySettingsStore.shared.isProtected(info.persistentKey)
        card.hasHiDPIOverride = !info.isBuiltin && HiDPIOverride.isInstalled(for: info)
        // "Has DDC" must mean the display answers, not that a service exists.
        card.hasDDC = DDCRegistry.shared.isResponsive(info)
        if card.hasDDC {
            // All DDC round trips, so only ask displays that answered.
            card.ddcCapabilities = DDCRegistry.shared.capabilities(for: info)
            let capabilities = card.ddcCapabilities
            if capabilities?.supports(.contrast) ?? true {
                card.contrast = BrightnessEngine.shared.contrast(of: info)
            }
            if capabilities?.supports(.inputSource) ?? true {
                card.inputSourceRaw = InputEngine.currentRawValue(for: info)
            }
        }
        if !info.isBuiltin {
            card.followsBuiltIn =
                DisplaySettingsStore.shared.preferences(for: info.persistentKey)?.followsBuiltIn == true
            card.ddcChannelCount = DDCRegistry.shared.availableChannelCount()
            card.ddcChannel = DDCRegistry.shared.channel(forKey: info.persistentKey)
        }
        card.isLoaded = true
        return card
    }

    /// Put remembered settings back on displays that were not here a moment ago.
    ///
    /// Undocking and redocking a laptop reassigns display IDs and often resets
    /// an external monitor to its default mode; this is what makes the desk
    /// look the same afterwards.
    private func restoreNewArrivals(among displays: [DisplayInfo]) {
        guard DisplaySettingsStore.shared.isEnabled else {
            seenKeys = Set(displays.map(\.persistentKey))
            return
        }
        let arrivals = displays.filter {
            !seenKeys.contains($0.persistentKey) && !restoringKeys.contains($0.persistentKey)
        }
        seenKeys = Set(displays.map(\.persistentKey))
        guard !arrivals.isEmpty else { return }

        for display in arrivals { restoringKeys.insert(display.persistentKey) }
        HardwareQueue.shared.run {
            var summary: [String: [String]] = [:]
            for display in arrivals {
                let restored = DisplaySettingsStore.shared.restore(to: display)
                if !restored.isEmpty { summary[display.name] = restored }
            }
            DispatchQueue.main.async {
                for display in arrivals { self.restoringKeys.remove(display.persistentKey) }
                guard !summary.isEmpty else { return }
                let parts = summary.map { "\($0.key): \($0.value.joined(separator: "、"))" }
                self.status = L10n.t("已恢复 \(parts.joined(separator: "；"))",
                                     "Restored \(parts.joined(separator: "; "))")
                self.refresh()
            }
        }
    }

    /// Undo outside changes to any display the user has locked.
    private func enforceProtection() {
        let displays = DisplayRegistry.shared.onlineDisplays()
            .filter { !awaitingConfirmation.contains($0.persistentKey) }
        guard displays.contains(where: { DisplaySettingsStore.shared.isProtected($0.persistentKey) })
        else { return }
        HardwareQueue.shared.run {
            var corrected: [String] = []
            for display in displays {
                let items = DisplaySettingsStore.shared.enforceProtection(on: display)
                if !items.isEmpty { corrected.append(display.name) }
            }
            guard !corrected.isEmpty else { return }
            DispatchQueue.main.async {
                self.status = L10n.t("已还原被改动的配置：\(corrected.joined(separator: "、"))",
                                     "Reverted an outside change on \(corrected.joined(separator: ", "))")
            }
        }
    }

    func setRememberEnabled(_ enabled: Bool) {
        DisplaySettingsStore.shared.isEnabled = enabled
        rememberEnabled = enabled
        guard enabled else { return }
        // Capture what is on screen right now as the baseline to restore to.
        for card in cards { recordAll(card) }
    }

    private func recordAll(_ card: DisplayCard) {
        DisplaySettingsStore.shared.update(card.info.persistentKey) { preferences in
            if card.canControlBrightness { preferences.brightness = card.brightness }
            if let contrast = card.contrast { preferences.contrast = contrast }
            if card.canControlVolume { preferences.volume = card.volume }
            preferences.modeID = card.currentMode?.id
            preferences.rotation = card.info.rotation.rawValue
        }
    }

    /// Clamshell-style behaviour: when an external display shows up, take the
    /// built-in panel off the desktop, and put it back when the external one
    /// leaves. Opt-in, and it only ever undoes what it itself did.
    private func applyAutoDisconnect(among displays: [DisplayInfo]) {
        guard autoDisconnectBuiltIn else { return }
        let externals = displays.filter { !$0.isBuiltin }
        let builtIn = displays.first(where: \.isBuiltin)

        if !externals.isEmpty, let builtIn, autoDisconnectedBuiltIn == nil {
            let result = PowerEngine.setEnabled(false, display: builtIn)
            if case .ok = result {
                autoDisconnectedBuiltIn = builtIn
                PowerEngine.sleepStates[builtIn.persistentKey] = .softDisconnect
                offDisplays.append(OffDisplay(info: builtIn, method: .softDisconnect))
                status = L10n.t("检测到外接屏，已收起内建屏",
                                "External display detected — the built-in panel was put away")
            }
        } else if externals.isEmpty, let remembered = autoDisconnectedBuiltIn {
            _ = PowerEngine.setEnabled(true, display: remembered)
            PowerEngine.sleepStates.removeValue(forKey: remembered.persistentKey)
            offDisplays.removeAll { $0.id == remembered.id }
            autoDisconnectedBuiltIn = nil
        }
    }

    func setAutoDisconnectBuiltIn(_ enabled: Bool) {
        Defaults.shared.set(enabled, forKey: "autoDisconnectBuiltIn")
        autoDisconnectBuiltIn = enabled
        if !enabled, let remembered = autoDisconnectedBuiltIn {
            _ = PowerEngine.setEnabled(true, display: remembered)
            PowerEngine.sleepStates.removeValue(forKey: remembered.persistentKey)
            offDisplays.removeAll { $0.id == remembered.id }
            autoDisconnectedBuiltIn = nil
            refresh()
        } else {
            refresh()
        }
    }

    private func handleReconfiguration() {
        enforceProtection()
        DDCRegistry.shared.invalidate()
        BrightnessEngine.shared.invalidate()
        // Gamma tables are wiped by any mode change; put software dimming back.
        HardwareQueue.shared.run { BrightnessEngine.shared.reapplySoftwareDimming() }
        refresh()
    }

    /// Re-resolve a card against the live registry before acting on it.
    ///
    /// A card holds the `DisplayInfo` captured when the menu was drawn, and
    /// CoreGraphics reassigns display IDs on any reconfiguration — mirroring,
    /// a mode change, a reconnect. Acting on the stale ID quietly does nothing,
    /// which is exactly how a rotation issued moments after un-mirroring
    /// vanished without an error. Identity survives; the ID does not.
    private func live(_ card: DisplayCard) -> DisplayInfo? {
        DisplayRegistry.shared.onlineDisplays()
            .first { $0.persistentKey == card.info.persistentKey }
    }

    private func update(_ id: CGDirectDisplayID, _ mutate: (inout DisplayCard) -> Void) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        mutate(&cards[index])
    }

    // MARK: - Brightness

    func setBrightness(_ value: Double, for card: DisplayCard) {
        update(card.id) { $0.brightness = value }
        propagateLinkedBrightness(from: card, movedTo: value)
        let info = card.info
        HardwareQueue.shared.coalesce(key: "brightness-\(card.id)", value: value) { latest in
            let ok = BrightnessEngine.shared.setBrightness(latest, for: info)
            if ok { DisplaySettingsStore.shared.update(info.persistentKey) { $0.brightness = latest } }
            self.reportIfFailed(ok, info, L10n.t("亮度", "Brightness"))
        }
    }

    /// A control that moves in the UI and not on the hardware is worse than one
    /// that refuses: the user blames the display. Failures come back with the
    /// slider restored to what the hardware actually reports.
    private nonisolated func reportIfFailed(_ ok: Bool, _ info: DisplayInfo, _ what: String) {
        guard !ok else { return }
        DispatchQueue.main.async {
            self.status = L10n.t("\(info.name) 不接受\(what)调节",
                                 "\(info.name) did not accept the \(what.lowercased()) change")
            self.refresh()
        }
    }

    func setSoftwareDim(_ value: Double, for card: DisplayCard) {
        update(card.id) { $0.softwareDim = value }
        let info = card.info
        HardwareQueue.shared.coalesce(key: "dim-\(card.id)", value: value) { latest in
            BrightnessEngine.shared.setSoftwareDim(latest, for: info)
        }
    }

    func setContrast(_ value: Double, for card: DisplayCard) {
        update(card.id) { $0.contrast = value }
        let info = card.info
        HardwareQueue.shared.coalesce(key: "contrast-\(card.id)", value: value) { latest in
            let ok = BrightnessEngine.shared.setContrast(latest, for: info)
            if ok { DisplaySettingsStore.shared.update(info.persistentKey) { $0.contrast = latest } }
            self.reportIfFailed(ok, info, L10n.t("对比度", "Contrast"))
        }
    }

    /// Move every display that has a working brightness channel at once.
    func setBrightnessForAll(_ value: Double) {
        let targets = cards.filter(\.canControlBrightness)
        for card in targets { update(card.id) { $0.brightness = value } }
        let infos = targets.map(\.info)
        HardwareQueue.shared.coalesce(key: "brightness-all", value: value) { latest in
            for info in infos { BrightnessEngine.shared.setBrightness(latest, for: info) }
        }
    }

    // MARK: - Linked brightness

    /// Move every display together, keeping the differences between them.
    ///
    /// Two panels at the same percentage rarely match by eye, so people settle
    /// on a set of values that look right together and then want the *whole
    /// set* to go up or down. Linking captures the ratios at the moment it is
    /// switched on and preserves them from then on — unlike "match all", which
    /// flattens every display to one number.
    @Published private(set) var brightnessLinked = Defaults.shared.bool(forKey: "brightnessLinked")

    /// Each display's brightness as a multiple of the reference display's.
    private var linkRatios: [String: Double] = [:]

    func setBrightnessLinked(_ linked: Bool) {
        brightnessLinked = linked
        Defaults.shared.set(linked, forKey: "brightnessLinked")
        guard linked else { linkRatios.removeAll(); return }
        captureLinkRatios()
        status = linkRatios.count > 1
            ? L10n.t("已按当前比例联动 \(linkRatios.count) 块屏",
                     "\(linkRatios.count) displays linked at their current ratios")
            : nil
    }

    private func captureLinkRatios() {
        linkRatios.removeAll()
        let controllable = cards.filter(\.canControlBrightness)
        guard let reference = controllable.first(where: { $0.info.isMain }) ?? controllable.first,
              reference.brightness > 0.01 else { return }
        for card in controllable {
            linkRatios[card.info.persistentKey] = card.brightness / reference.brightness
        }
    }

    /// Apply a change made on one display to the rest of the linked set.
    private func propagateLinkedBrightness(from card: DisplayCard, movedTo value: Double) {
        guard brightnessLinked else { return }
        if linkRatios.isEmpty { captureLinkRatios() }
        guard let ownRatio = linkRatios[card.info.persistentKey], ownRatio > 0.01 else { return }

        // What the reference display would have to be for this one to sit here.
        let referenceValue = value / ownRatio
        for other in cards where other.id != card.id && other.canControlBrightness {
            guard let ratio = linkRatios[other.info.persistentKey] else { continue }
            let target = min(max(referenceValue * ratio, 0), 1)
            update(other.id) { $0.brightness = target }
            let info = other.info
            HardwareQueue.shared.coalesce(key: "brightness-\(other.id)", value: target) { latest in
                _ = BrightnessEngine.shared.setBrightness(latest, for: info)
            }
        }
    }

    /// Bring every other display to this one's brightness.
    ///
    /// Two panels at "the same" percentage rarely look the same, so people pick
    /// a reference screen by eye and match the rest to it. That is the gesture
    /// this button is: not an average, but "make them all look like this one".
    func matchBrightnessToAll(from card: DisplayCard) {
        // Ask the hardware for the reference value rather than trusting the
        // card: an action fired from a URL can arrive before the first refresh
        // has finished reading the displays, and a stale 100% would drag every
        // screen to full brightness.
        guard let reference = live(card),
              let value = BrightnessEngine.shared.brightness(of: reference) else {
            status = L10n.t("读不到这块屏的亮度", "Cannot read that display's brightness")
            return
        }
        let others = DisplayRegistry.shared.onlineDisplays()
            .filter { $0.persistentKey != reference.persistentKey }
        let targets = others.filter { BrightnessEngine.shared.channel(for: $0) != .none }
        guard !targets.isEmpty else {
            status = L10n.t("没有其他可调节亮度的屏幕", "No other display has a brightness control")
            return
        }

        for info in targets {
            update(info.id) { $0.brightness = value }
            HardwareQueue.shared.coalesce(key: "brightness-\(info.id)", value: value) { latest in
                let ok = BrightnessEngine.shared.setBrightness(latest, for: info)
                if ok { DisplaySettingsStore.shared.update(info.persistentKey) { $0.brightness = latest } }
                self.reportIfFailed(ok, info, L10n.t("亮度", "Brightness"))
            }
        }
        status = L10n.t("已把 \(targets.count) 块屏对齐到 \(reference.name) 的 \(Int(value * 100))%",
                        "Matched \(targets.count) display(s) to \(reference.name) at \(Int(value * 100))%")
        refresh()
    }

    /// The average of what the sliders currently show — the master slider's
    /// resting position when displays disagree.
    var averageBrightness: Double {
        let values = cards.filter(\.canControlBrightness).map(\.brightness)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Switching a monitor to another input takes it away from this Mac, and
    /// the only way back is the monitor's own buttons — the same trap as
    /// cutting its power. Worth one confirmation.
    func selectInput(rawValue: UInt16, for card: DisplayCard) {
        let info = card.info
        guard Prompt.confirm(
            title: L10n.t("把 \(info.name) 切到 \(InputEngine.label(forRawValue: rawValue))？",
                          "Switch \(info.name) to \(InputEngine.label(forRawValue: rawValue))?"),
            message: L10n.t("这块屏会离开这台 Mac，显示另一路输入。切回来只能用显示器自己的按键。",
                            "The display will leave this Mac and show the other input. Only the monitor's own buttons can bring it back."))
        else { return }
        HardwareQueue.shared.run {
            let ok = InputEngine.select(rawValue: rawValue, for: info)
            DispatchQueue.main.async {
                if ok {
                    self.update(info.id) { $0.inputSourceRaw = rawValue }
                } else {
                    self.status = L10n.t("切换输入源失败", "Could not switch input source")
                }
            }
        }
    }

    /// The display the pointer is on — how one global shortcut serves every
    /// screen without asking which one it meant.
    func cardUnderCursor() -> DisplayCard? {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
                ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return cards.first }
        let id = CGDirectDisplayID(number.uint32Value)
        return cards.first { $0.id == id } ?? cards.first
    }

    func nudgeBrightness(by delta: Double) {
        guard let card = cardUnderCursor(), card.canControlBrightness else { return }
        let value = min(max(card.brightness + delta, 0), 1)
        setBrightness(value, for: card)
        OSDWindow.shared.show(value: value, symbol: "sun.max.fill",
                              caption: card.info.name, on: card.id)
    }

    func nudgeVolume(by delta: Double) {
        guard let card = cardUnderCursor(), card.canControlVolume else { return }
        let value = min(max(card.volume + delta, 0), 1)
        setVolume(value, for: card)
        OSDWindow.shared.show(value: value, symbol: "speaker.wave.2.fill",
                              caption: volumeCaption(for: card), on: card.id)
    }

    func toggleMuteUnderCursor() {
        guard let card = cardUnderCursor(), card.canControlVolume else { return }
        toggleMute(card)
        OSDWindow.shared.show(value: card.isMuted ? card.volume : 0,
                              symbol: "speaker.wave.2.fill",
                              caption: volumeCaption(for: card),
                              muted: !card.isMuted, on: card.id)
    }

    /// PWE Lumen Bar's own shortcuts stay per-display on purpose — that is what a
    /// binding called "volume up on the display under the pointer" means, and
    /// pre-setting a monitor's speakers before switching to them is a real
    /// thing to want. But the HUD must not imply you will hear it: when the
    /// sound is going somewhere else, the caption says so.
    private func volumeCaption(for card: DisplayCard) -> String {
        guard !card.isActiveOutput, let output = card.systemOutputName else { return card.info.name }
        return card.info.name + "\n" + L10n.t("↳ 声音在 \(output)", "↳ sound is on \(output)")
    }

    /// Per-display colour temperature. macOS's own Night Shift is global; an
    /// external panel is usually colder than the built-in one and wants its own
    /// correction.
    func setWarmth(_ value: Double, for card: DisplayCard) {
        update(card.id) { $0.warmth = value }
        let info = card.info
        HardwareQueue.shared.coalesce(key: "warmth-\(card.id)", value: value) { latest in
            let ok = BrightnessEngine.shared.setWarmth(latest, for: info)
            if ok { DisplaySettingsStore.shared.update(info.persistentKey) { $0.warmth = latest } }
            self.reportIfFailed(ok, info, L10n.t("色温", "Warmth"))
        }
    }

    // MARK: - Volume

    /// Re-read which device is playing, without touching the hardware.
    ///
    /// A full `refresh()` would re-run every DDC probe; the output device
    /// changing says nothing about the displays themselves.
    private func refreshAudioRouting() {
        let audio = AudioEngine.shared
        let devices = audio.outputDevices()
        for index in cards.indices {
            let info = cards[index].info
            switch audio.routing(for: info, in: devices) {
            case .thisDisplay:
                cards[index].isActiveOutput = true
                cards[index].systemOutputName = cards[index].audioDeviceName
                cards[index].systemOutputKind = nil
            case .elsewhere(let device):
                cards[index].isActiveOutput = false
                cards[index].systemOutputName = device.name
                cards[index].systemOutputKind = device.kindLabel
            case .unknown:
                cards[index].isActiveOutput = false
                cards[index].systemOutputName = nil
                cards[index].systemOutputKind = nil
            }
        }
    }

    func setVolume(_ value: Double, for card: DisplayCard) {
        update(card.id) { $0.volume = value; $0.isMuted = false }
        let info = card.info
        HardwareQueue.shared.coalesce(key: "volume-\(card.id)", value: value) { latest in
            let ok = AudioEngine.shared.setVolume(latest, for: info)
            if ok { DisplaySettingsStore.shared.update(info.persistentKey) { $0.volume = latest } }
            self.reportIfFailed(ok, info, L10n.t("音量", "Volume"))
        }
    }

    func toggleMute(_ card: DisplayCard) {
        let muted = !card.isMuted
        update(card.id) { $0.isMuted = muted }
        let info = card.info
        HardwareQueue.shared.run {
            let ok = AudioEngine.shared.setMuted(muted, for: info)
            self.reportIfFailed(ok, info, L10n.t("静音", "Mute"))
        }
    }

    // MARK: - Resolution

    /// Apply a mode behind a confirmation that reverts itself.
    ///
    /// A mode that produces no picture would otherwise be unrecoverable from a
    /// menu bar app — the menu lives on the screen that just went dark.
    func applyMode(_ mode: DisplayMode, for card: DisplayCard) {
        guard let previous = card.currentMode else { return }
        guard let info = live(card) else {
            status = L10n.t("这块屏已经不在线了", "That display is no longer attached")
            return
        }
        HardwareQueue.shared.run {
            let ok = ModeEngine.apply(mode, to: info.id)
            DispatchQueue.main.async {
                guard ok else {
                    self.status = L10n.t("切换失败：\(mode.pointsLabel)", "Could not switch to \(mode.pointsLabel)")
                    return
                }
                self.awaitingConfirmation.insert(info.persistentKey)
                self.refresh()
                ConfirmRevertPanel.present(
                    title: L10n.t("保留这个分辨率？", "Keep this resolution?"),
                    message: L10n.t("\(info.name) 已切换到 \(mode.describe())",
                                  "\(info.name) switched to \(mode.describe())"),
                    onKeep: {
                        self.status = nil
                        self.awaitingConfirmation.remove(info.persistentKey)
                        // A locked display now holds the newly confirmed mode.
                        DisplaySettingsStore.shared.writeAlways(info.persistentKey) {
                            $0.modeID = mode.id
                        }
                    },
                    onRevert: {
                        HardwareQueue.shared.run {
                            ModeEngine.apply(previous, to: info.id)
                            DispatchQueue.main.async {
                                self.awaitingConfirmation.remove(info.persistentKey)
                                self.refresh()
                            }
                        }
                    })
            }
        }
    }

    // MARK: - Rotation

    func rotate(_ card: DisplayCard, to rotation: Rotation) {
        guard let info = live(card) else {
            status = L10n.t("这块屏已经不在线了", "That display is no longer attached")
            return
        }
        let previous = info.rotation
        HardwareQueue.shared.run {
            let ok = RotationEngine.rotate(info, to: rotation)
            DispatchQueue.main.async {
                guard ok else {
                    self.status = L10n.t("\(info.name) 不接受旋转请求", "\(info.name) refuses rotation requests")
                    return
                }
                self.awaitingConfirmation.insert(info.persistentKey)
                self.refresh()
                ConfirmRevertPanel.present(
                    title: L10n.t("保留这个方向？", "Keep this orientation?"),
                    message: L10n.t("\(info.name) 已旋转到 \(rotation.label)",
                                  "\(info.name) rotated to \(rotation.label)"),
                    onKeep: {
                        self.status = nil
                        self.awaitingConfirmation.remove(info.persistentKey)
                        DisplaySettingsStore.shared.writeAlways(info.persistentKey) {
                            $0.rotation = rotation.rawValue
                        }
                    },
                    onRevert: {
                        HardwareQueue.shared.run {
                            RotationEngine.rotate(info, to: previous)
                            DispatchQueue.main.async {
                                self.awaitingConfirmation.remove(info.persistentKey)
                                self.refresh()
                            }
                        }
                    })
            }
        }
    }

    func activateLicense(email: String, key: String) -> LicenseStore.ActivationResult {
        let result = LicenseStore.shared.activate(email: email, key: key)
        isPro = LicenseStore.shared.isPro
        return result
    }

    func deactivateLicense() {
        LicenseStore.shared.deactivate()
        isPro = false
    }

    func showWelcome() {
        dismissPopover?()
        LumenBarWindow.show(id: "welcome",
                         title: L10n.t("欢迎使用 PWE Lumen Bar", "Welcome to PWE Lumen Bar"),
                         size: NSSize(width: 460, height: 540)) {
            WelcomeView(controller: self) {
                LumenBarWindow.close(id: "welcome")
            }
        }
    }

    public func showWelcomeIfFirstRun() {
        guard WelcomeView.shouldShow else { return }
        // Give the status item a moment to exist before a window steals focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.showWelcome() }
    }

    /// Opening the settings window from one place, so the menu and the URL
    /// scheme cannot drift apart.
    func openSettings() {
        LumenBarWindow.show(id: "settings",
                         title: L10n.t("PWE Lumen Bar 设置", "PWE Lumen Bar Settings"),
                         size: NSSize(width: 460, height: 620)) {
            SettingsView(controller: self)
        }
    }

    // MARK: - Naming and protection

    /// Two identical monitors report identical names; this is the only way to
    /// tell them apart in the menu.
    func renameDisplay(_ card: DisplayCard) {
        let current = card.info.name
        guard let name = Prompt.text(
            title: L10n.t("重命名显示器", "Rename display"),
            message: L10n.t("只影响 PWE Lumen Bar 里的显示，按显示器身份记住，重新插拔也还在。留空则恢复系统名称。",
                            "Affects only how PWE Lumen Bar labels it. Stored against the display's identity, so it survives reconnects. Leave empty to restore the system name."),
            defaultValue: current)
        else { return }
        DisplayNameStore.shared.setName(name == current ? nil : name,
                                        forKey: card.info.persistentKey)
        refresh()
    }

    func toggleProtection(_ card: DisplayCard) {
        let enabling = !card.isProtected
        DisplaySettingsStore.shared.setProtected(enabling, for: card.info)
        update(card.id) { $0.isProtected = enabling }
        status = enabling
            ? L10n.t("\(card.info.name) 的分辨率和方向已锁定",
                     "\(card.info.name)'s resolution and orientation are locked")
            : nil
    }

    // MARK: - Forced HiDPI

    /// Install a display override so a monitor that advertises no HiDPI modes
    /// gets them. Needs admin rights and a restart, so both are stated plainly
    /// before anything is written.
    func forceHiDPI(_ card: DisplayCard) {
        guard LicenseStore.shared.isUnlocked(.forcedHiDPI) else {
            status = L10n.t("强制 HiDPI 属于 PWE Lumen Bar Pro，在设置里解锁。",
                            "Forced HiDPI is part of PWE Lumen Bar Pro — unlock it in Settings.")
            openSettings()
            return
        }
        guard let plan = HiDPIOverride.plan(for: card.info) else {
            status = L10n.t("无法为这块屏生成覆盖文件", "Could not build an override for this display")
            return
        }
        let sizes = plan.logicalSizes
            .map { "\(Int($0.width))×\(Int($0.height))" }
            .joined(separator: ", ")

        guard Prompt.confirm(
            title: L10n.t("为 \(plan.displayName) 强制开启 HiDPI？", "Force HiDPI on \(plan.displayName)?"),
            message: L10n.t("""
                将写入系统显示器覆盖文件，加入这些 HiDPI 档位：
                \(sizes)

                • 需要管理员密码（由 macOS 自己弹窗，PWE Lumen Bar 不接触密码）
                • 重启后才会生效
                • 写入位置：\(plan.installPath)
                • 之后可以在同一个菜单里移除
                """, """
                This writes a system display override adding these HiDPI sizes:
                \(sizes)

                • Needs an administrator password — macOS asks for it directly, PWE Lumen Bar never sees it
                • Takes effect only after a restart
                • Written to: \(plan.installPath)
                • Removable from the same menu afterwards
                """))
        else { return }

        HardwareQueue.shared.run {
            let result = HiDPIOverride.install(plan)
            DispatchQueue.main.async {
                switch result {
                case .installed:
                    self.status = L10n.t("已写入，重启后生效", "Written — restart to take effect")
                case .cancelled:
                    self.status = nil
                case .failed(let reason):
                    self.status = L10n.t("写入失败：\(reason)", "Could not write it: \(reason)")
                }
                self.refresh()
            }
        }
    }

    func removeHiDPIOverride(_ card: DisplayCard) {
        guard let plan = HiDPIOverride.plan(for: card.info) else { return }
        HardwareQueue.shared.run {
            let result = HiDPIOverride.remove(plan)
            DispatchQueue.main.async {
                switch result {
                case .installed:
                    self.status = L10n.t("已移除，重启后恢复", "Removed — restart to take effect")
                case .cancelled:
                    self.status = nil
                case .failed(let reason):
                    self.status = L10n.t("移除失败：\(reason)", "Could not remove it: \(reason)")
                }
                self.refresh()
            }
        }
    }

    // MARK: - Per-display sleep

    /// Turn one display off. The route is chosen per display — DDC power for
    /// monitors that speak it, taken off the desktop for the ones that do not.
    func sleepDisplay(_ card: DisplayCard) {
        guard let info = live(card) else {
            status = L10n.t("这块屏已经不在线了", "That display is no longer attached")
            return
        }
        HardwareQueue.shared.run {
            let outcome = PowerEngine.sleepDisplay(info)
            DispatchQueue.main.async {
                if case .slept(let method) = outcome {
                    PowerEngine.sleepStates[info.persistentKey] = method
                    // A DDC-powered-off monitor stays online, so its card
                    // remains; one taken off the desktop does not, and only
                    // this record can bring it back.
                    if method == .softDisconnect {
                        self.offDisplays.append(OffDisplay(info: info, method: method))
                    } else {
                        self.update(info.id) { $0.isAsleep = true }
                    }
                }
                self.status = outcome.message
                self.refresh()
            }
        }
    }

    func wake(_ info: DisplayInfo) {
        let method = PowerEngine.sleepStates[info.persistentKey] ?? .softDisconnect
        HardwareQueue.shared.run {
            let ok = PowerEngine.wakeDisplay(info, method: method)
            DispatchQueue.main.async {
                if ok {
                    PowerEngine.sleepStates.removeValue(forKey: info.persistentKey)
                    self.offDisplays.removeAll { $0.info.persistentKey == info.persistentKey }
                    self.update(info.id) { $0.isAsleep = false }
                } else {
                    self.status = L10n.t("唤醒失败", "Could not bring that display back")
                }
                self.refresh()
            }
        }
    }

    func toggleSleep(_ card: DisplayCard) {
        card.isAsleep ? wake(card.info) : sleepDisplay(card)
    }

    func sleepUnderCursor() {
        guard let card = cardUnderCursor() else { return }
        toggleSleep(card)
    }

    // MARK: - Ambient follow

    /// Tie an external display's brightness to the built-in panel's, which
    /// macOS keeps adjusted from the ambient light sensor.
    func toggleFollowBuiltIn(_ card: DisplayCard) {
        let enabling = !card.followsBuiltIn
        let builtInValue = cards.first(where: { $0.info.isBuiltin })?.brightness

        // Capture the ratio as it stands, so a screen the user keeps dimmer
        // stays proportionally dimmer rather than snapping to match.
        let ratio: Double? = {
            guard enabling, let builtInValue, builtInValue > 0.01 else { return nil }
            return card.brightness / builtInValue
        }()

        // Written unconditionally, but without switching on "remember every
        // display's settings" — that is a separate preference with its own
        // toggle, and turning it on behind the user's back is not this
        // feature's business.
        DisplaySettingsStore.shared.writeAlways(card.info.persistentKey) { preferences in
            preferences.followsBuiltIn = enabling
            if let ratio { preferences.followRatio = ratio }
        }
        update(card.id) { $0.followsBuiltIn = enabling }
        refreshAmbientSync()

        status = enabling
            ? L10n.t("\(card.info.name) 将跟随内建屏亮度", "\(card.info.name) now follows the built-in display")
            : nil
    }

    @discardableResult
    func applyMediaKeySetting(_ enabled: Bool) -> Bool {
        let ok = mediaKeys.setEnabled(enabled)
        mediaKeysEnabled = enabled && ok
        if enabled && !ok {
            status = L10n.t("需要「辅助功能」权限才能接管亮度/音量键。已打开系统设置，勾选 PWE Lumen Bar 后再试一次。",
                            "Taking over the brightness and volume keys needs Accessibility permission. System Settings is open — tick PWE Lumen Bar, then try again.")
        }
        return ok
    }

    private func refreshAmbientSync() {
        ambientSync.update(hasFollowers: cards.contains { $0.followsBuiltIn })
    }

    // MARK: - Presets

    @discardableResult
    func savePreset(named name: String) -> Preset {
        let preset = PresetStore.shared.capture(name: name)
        presets = PresetStore.shared.presets
        status = L10n.t("已保存场景「\(name)」", "Saved preset \u{201C}\(name)\u{201D}")
        return preset
    }

    func applyPreset(_ preset: Preset) {
        HardwareQueue.shared.run {
            let applied = PresetStore.shared.apply(preset)
            DispatchQueue.main.async {
                self.status = applied.isEmpty
                    ? L10n.t("场景「\(preset.name)」里的显示器都不在线",
                             "None of the displays in \u{201C}\(preset.name)\u{201D} are attached")
                    : L10n.t("已应用场景「\(preset.name)」到 \(applied.count) 块屏",
                             "Applied \u{201C}\(preset.name)\u{201D} to \(applied.count) display(s)")
                self.refresh()
            }
        }
    }

    func deletePreset(_ preset: Preset) {
        PresetStore.shared.delete(preset.id)
        presets = PresetStore.shared.presets
    }

    // MARK: - Colour management

    func applyColorProfile(_ profile: ColorProfile, to card: DisplayCard) {
        let info = card.info
        HardwareQueue.shared.run {
            let ok = ColorEngine.apply(profile, to: info.id)
            DispatchQueue.main.async {
                self.status = ok
                    ? L10n.t("\(info.name) 已切换到 \(profile.name)",
                             "\(info.name) switched to \(profile.name)")
                    : L10n.t("颜色配置切换失败", "Could not switch the colour profile")
                self.refresh()
            }
        }
    }

    func resetColorProfile(_ card: DisplayCard) {
        let info = card.info
        HardwareQueue.shared.run {
            _ = ColorEngine.resetToFactory(displayID: info.id)
            DispatchQueue.main.async { self.refresh() }
        }
    }

    // MARK: - Arrangement

    func place(_ card: DisplayCard, _ edge: ArrangementEdge) {
        let online = DisplayRegistry.shared.onlineDisplays()
        guard let info = online.first(where: { $0.persistentKey == card.info.persistentKey }),
              let anchor = online.first(where: { $0.isMain && $0.id != info.id })
                ?? online.first(where: { $0.id != info.id }) else {
            status = L10n.t("只有一块屏，无法排列", "Only one display — nothing to arrange against")
            return
        }
        let ok = ArrangementEngine.place(info, edge, relativeTo: anchor)
        status = ok ? nil : L10n.t("排列失败", "Could not rearrange")
        refresh()
    }

    func tileHorizontally() {
        _ = ArrangementEngine.tileHorizontally(cards.map(\.info))
        refresh()
    }

    // MARK: - Screen capture

    /// Capture one display at its full framebuffer resolution.
    ///
    /// The first run raises the Screen Recording prompt; until it is granted
    /// the capture throws rather than silently producing a black image, which
    /// is what the deprecated CoreGraphics path used to do.
    func captureToFile(_ card: DisplayCard) {
        let info = card.info
        Task {
            do {
                let image = try await CaptureEngine.capture(info)
                let url = try CaptureEngine.save(image, display: info)
                self.status = L10n.t("已保存到桌面：\(url.lastPathComponent)",
                                     "Saved to the desktop: \(url.lastPathComponent)")
            } catch {
                self.status = error.localizedDescription
            }
        }
    }

    func captureToClipboard(_ card: DisplayCard) {
        let info = card.info
        Task {
            do {
                let image = try await CaptureEngine.capture(info)
                let ok = CaptureEngine.copyToPasteboard(image)
                self.status = ok
                    ? L10n.t("\(info.name) 已拷贝到剪贴板", "\(info.name) copied to the clipboard")
                    : L10n.t("拷贝失败", "Could not copy to the clipboard")
            } catch {
                self.status = error.localizedDescription
            }
        }
    }

    /// Every display, one file each — the case macOS handles but never labels.
    func captureAllToFiles() {
        let infos = cards.map(\.info)
        Task {
            var saved: [String] = []
            for info in infos {
                do {
                    let image = try await CaptureEngine.capture(info)
                    let url = try CaptureEngine.save(image, display: info)
                    saved.append(url.lastPathComponent)
                } catch {
                    self.status = error.localizedDescription
                    return
                }
            }
            self.status = L10n.t("已保存 \(saved.count) 张到桌面",
                                 "Saved \(saved.count) screenshot(s) to the desktop")
        }
    }

    func captureUnderCursor() {
        guard let card = cardUnderCursor() else { return }
        captureToFile(card)
    }

    // MARK: - Power and arrangement

    func setAsMain(_ card: DisplayCard) {
        guard let info = live(card) else {
            status = L10n.t("这块屏已经不在线了", "That display is no longer attached")
            return
        }
        HardwareQueue.shared.run {
            let ok = PowerEngine.setAsMain(info)
            DispatchQueue.main.async {
                self.status = ok ? nil : L10n.t("设为主屏失败", "Could not set the main display")
                self.refresh()
            }
        }
    }

    /// Cutting a monitor's power over DDC can take its I2C pipe down with it,
    /// leaving no way back except the monitor's own button — so this asks first.
    func turnOffBacklight(_ card: DisplayCard) {
        let info = card.info
        guard Prompt.confirm(
            title: L10n.t("给 \(info.name) 断电？", "Cut power to \(info.name)?"),
            message: L10n.t("有些显示器断电后会连同 DDC 通道一起从系统里消失，届时只能按显示器上的物理电源键才能开回来。\n\n想要可逆的关闭，请用卡片上的「熄屏」按钮。",
                            "On some monitors this takes the DDC channel down with the power, and only the monitor's own power button will bring it back.\n\nFor a reversible blackout, use the card's Turn off button instead."))
        else { return }
        HardwareQueue.shared.run {
            let ok = PowerEngine.setDDCPower(.off, display: info)
            DispatchQueue.main.async {
                self.status = ok
                    ? L10n.t("\(info.name) 已关闭背光，动一下鼠标或按任意键唤醒",
                             "\(info.name) backlight off — move the mouse or press a key to wake it")
                    : L10n.t("这块屏不支持通过 DDC 关闭背光",
                             "This display does not support turning the backlight off over DDC")
            }
        }
    }

    func softDisconnect(_ card: DisplayCard) {
        let info = card.info
        let result = PowerEngine.setEnabled(false, display: info)
        switch result {
        case .ok:
            PowerEngine.sleepStates[info.persistentKey] = .softDisconnect
            offDisplays.append(OffDisplay(info: info, method: .softDisconnect))
            status = L10n.t("\(info.name) 已从桌面移除", "\(info.name) removed from the desktop")
            refresh()
        default:
            status = result.message
        }
    }

    func toggleMirror(_ card: DisplayCard) {
        guard let liveInfo = live(card) else {
            status = L10n.t("这块屏已经不在线了", "That display is no longer attached")
            return
        }
        let target: CGDirectDisplayID? = liveInfo.isMirrored
            ? nil
            : cards.first { $0.info.isMain && $0.id != card.id }?.id
        guard card.info.isMirrored || target != nil else {
            status = L10n.t("没有可镜像的目标屏幕", "No display available to mirror to")
            return
        }
        HardwareQueue.shared.run {
            PowerEngine.setMirror(liveInfo, to: target)
            DispatchQueue.main.async { self.refresh() }
        }
    }

    /// Switching language re-renders every label; the views observe this
    /// controller, so bumping a counter is what makes the change visible.
    func setLanguage(_ language: Language) {
        L10n.override = language
        languageRevision += 1
    }

    /// Re-pair a monitor with a different DDC channel.
    ///
    /// Channels are matched positionally because macOS exposes nothing tying an
    /// I2C pipe to a display ID; with two identical monitors the guess can land
    /// on the wrong one, and this is the correction.
    func setDDCChannel(_ channel: Int, for card: DisplayCard) {
        DDCRegistry.shared.setChannel(channel, forKey: card.info.persistentKey)
        BrightnessEngine.shared.invalidate()
        refresh()
    }

    func sleepAll() {
        PowerEngine.sleepAllDisplays()
    }
}
