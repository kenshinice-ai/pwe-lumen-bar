import AppKit
import Carbon.HIToolbox
import LumenCore
import SwiftUI

/// One place for the settings that do not belong in a transient popover.
struct SettingsView: View {
    @ObservedObject var controller: DisplayController

    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var shortcutsEnabled = HotKeyCenter.isEnabledInDefaults
    @State private var mediaKeysEnabled = MediaKeyTap.isEnabledInDefaults
    @State private var recording: HotKeyCenter.Action?
    @State private var bindingLabels: [UInt32: String] = [:]
    @State private var monitor: Any?
    @State private var conflictWarning: String?
    @State private var licenseEmail = ""
    @State private var licenseKey = ""
    @State private var licenseMessage: String?

    var body: some View {
        Form {
            Section("Lumen Pro") {
                if controller.isPro {
                    Label(L10n.t("已解锁", "Unlocked"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    if let email = LicenseStore.shared.licensedEmail {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    }
                    Button(L10n.t("在这台 Mac 上取消激活", "Deactivate on this Mac")) {
                        controller.deactivateLicense()
                        licenseMessage = nil
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t("亮度、音量、分辨率、旋转、场景、快捷键、截图 —— 日常要用的全部免费，没有试用期，也不会到期。",
                                    "Brightness, volume, resolution, rotation, presets, shortcuts, screenshots — everything you reach for daily is free, with no trial period and no expiry."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.t("Pro 只解决一件事，也是最难的一件：",
                                    "Pro solves one thing — the hard one:"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 2)

                    ForEach(LicenseStore.ProFeature.allCases, id: \.self) { feature in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(feature.title, systemImage: "sparkles.rectangle.stack")
                                .font(.callout.weight(.medium))
                            Text(feature.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(L10n.t("需要管理员密码，重启后生效，随时可以移除。内建屏和 Apple 显示器本来就有这些模式，用不上。",
                                        "Needs an administrator password, takes effect after a restart, and can be removed at any time. Built-in panels and Apple displays already have these modes and do not need it."))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HiDPIExplainer()
                    TextField(L10n.t("购买时使用的邮箱", "The email you bought with"), text: $licenseEmail)
                    TextField(L10n.t("许可证密钥", "Licence key"), text: $licenseKey, axis: .vertical)
                        .lineLimit(2 ... 4)
                        .font(.system(.caption, design: .monospaced))
                    HStack {
                        Button(L10n.t("解锁", "Unlock")) {
                            let result = controller.activateLicense(email: licenseEmail, key: licenseKey)
                            licenseMessage = result.message
                            if case .activated = result { licenseKey = "" }
                        }
                        .disabled(licenseEmail.isEmpty || licenseKey.isEmpty)
                        Spacer()
                    }
                }
                if let licenseMessage {
                    Text(licenseMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(L10n.t("通用", "General")) {
                // Bound straight to the stored preference. A local @State copy
                // could survive a window rebuild holding a stale value and then
                // write it back — which is how the interface silently reverted
                // from Chinese to the system language.
                Picker(L10n.t("语言", "Language"), selection: Binding(
                    get: { L10n.override },
                    set: { controller.setLanguage($0) })) {
                    ForEach(Language.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }

                Toggle(L10n.t("开机时启动", "Launch at login"), isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                        launchesAtLogin = LoginItem.isEnabled
                    }
            }

            Section(L10n.t("显示器信息", "Display information")) {
                if controller.cards.isEmpty {
                    Text(L10n.t("没有检测到显示器", "No displays detected"))
                        .foregroundStyle(.secondary)
                }
                ForEach(controller.cards) { card in
                    DisplayInfoRow(card: card)
                }
                Button(L10n.t("刷新", "Refresh")) { controller.refresh() }
            }

            Section(L10n.t("显示器", "Displays")) {
                Toggle(L10n.t("记住每块屏的设置", "Remember each display's settings"),
                       isOn: Binding(get: { controller.rememberEnabled },
                                     set: { controller.setRememberEnabled($0) }))
                Text(L10n.t("重新插拔后自动恢复亮度、色温、分辨率和方向。",
                            "Restores brightness, warmth, resolution and orientation after a reconnect."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("接外接屏时收起内建屏", "Put the built-in panel away when an external display connects"),
                       isOn: Binding(get: { controller.autoDisconnectBuiltIn },
                                     set: { controller.setAutoDisconnectBuiltIn($0) }))
            }

            Section(L10n.t("键盘亮度/音量键", "Keyboard brightness & volume keys")) {
                Toggle(L10n.t("接管这些按键", "Take these keys over"), isOn: $mediaKeysEnabled)
                    .onChange(of: mediaKeysEnabled) { _, newValue in
                        let ok = controller.applyMediaKeySetting(newValue)
                        if !ok { mediaKeysEnabled = false }
                    }
                Text(L10n.t("亮度键作用于光标所在的那块屏；光标在内建屏上时交还 macOS。需要「辅助功能」权限。",
                            "The brightness keys act on the display under the pointer; on the built-in panel they are left to macOS. Requires Accessibility permission."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.t("音量键跟的是声音，不是光标：只有当系统输出正是某台外接显示器的扬声器时才接管 —— 这种情况下 DisplayPort 音频常常根本没有音量控制，而 DDC 有。走蓝牙、AirPlay、内建扬声器或外置声卡时，按键原样交还 macOS，去调真正在发声的那台设备。",
                            "The volume keys follow the sound, not the pointer: Lumen takes them over only when the system output is an external display's own speakers — the case where DisplayPort audio often exposes no volume control at all and DDC does. Playing through Bluetooth, AirPlay, the built-in speakers or an external DAC, the keys are handed back to macOS so they move whatever is actually playing."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.t("全局快捷键", "Global shortcuts")) {
                Toggle(L10n.t("启用", "Enabled"), isOn: $shortcutsEnabled)
                    .onChange(of: shortcutsEnabled) { _, newValue in
                        controller.applyShortcutSetting(newValue)
                    }

                Text(L10n.t("快捷键作用于光标所在的那块屏。",
                            "Shortcuts act on whichever display the pointer is on."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(HotKeyCenter.Action.allCases, id: \.self) { action in
                    HStack {
                        Text(action.describe)
                        Spacer()
                        Button(recording == action
                               ? L10n.t("按下组合键…", "Press keys…")
                               : (bindingLabels[action.rawValue] ?? action.shortcutLabel)) {
                            beginRecording(action)
                        }
                        .frame(minWidth: 110)
                        .disabled(!shortcutsEnabled)
                    }
                }

                if let conflictWarning {
                    Label(conflictWarning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button(L10n.t("恢复默认快捷键", "Reset shortcuts to defaults")) {
                    for action in HotKeyCenter.Action.allCases {
                        HotKeyCenter.shared.rebind(action, to: nil)
                    }
                    refreshLabels()
                    conflictWarning = nil
                }
            }

            systemSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, idealWidth: 460, minHeight: 520, idealHeight: 620)
        .onAppear(perform: refreshLabels)
        .onDisappear { stopRecording() }
    }

    // MARK: - System

    /// Lumen stands on private interfaces that Apple can rename between
    /// releases. Rather than claim a version range and hope, it checks the
    /// interfaces themselves and says what it found — the same report
    /// `lumenctl compat` prints.
    private var systemSection: some View {
        Section(L10n.t("系统", "System")) {
            LabeledContent(L10n.t("运行环境", "Running on")) {
                Text("macOS \(Platform.osVersionString) · \(Platform.chipName)")
                    .foregroundStyle(.secondary)
            }

            let checks = Platform.compatibilityReport()
            let failures = checks.filter { !$0.ok }
            LabeledContent(L10n.t("接口自检", "Interface self-check")) {
                Label(failures.isEmpty
                      ? L10n.t("全部可用（\(checks.count) 项）", "All available (\(checks.count) checks)")
                      : L10n.t("\(failures.count) 项不可用", "\(failures.count) unavailable"),
                      systemImage: failures.isEmpty ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(failures.isEmpty ? Color.secondary : Color.orange)
            }

            if !failures.isEmpty {
                ForEach(failures, id: \.name) { check in
                    Text("· \(check.name) — \(check.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(L10n.t("对应功能会自动降级，不会崩溃。命令行里 `lumenctl compat` 可以拿到同一份报告。",
                            "The matching features degrade rather than crash. `lumenctl compat` prints the same report."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !Platform.isSupportedOS {
                Text(L10n.t("Lumen 支持 macOS \(Platform.minimumMajor) 及以上。更早的系统没有验证过，上面的自检就是真实情况。",
                            "Lumen supports macOS \(Platform.minimumMajor) and later. Older systems are unverified — the self-check above is the real answer."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Recording

    private func refreshLabels() {
        var labels: [UInt32: String] = [:]
        for action in HotKeyCenter.Action.allCases {
            labels[action.rawValue] = action.shortcutLabel
        }
        bindingLabels = labels
    }

    /// Captures the next key press. A bare key would swallow ordinary typing
    /// system-wide, so at least one of ⌃ ⌥ ⌘ is required.
    private func beginRecording(_ action: HotKeyCenter.Action) {
        stopRecording()
        recording = action
        conflictWarning = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command) else {
                conflictWarning = L10n.t("请至少带一个 ⌃ ⌥ ⌘ 修饰键。",
                                         "Use at least one of ⌃ ⌥ ⌘.")
                return nil
            }
            let binding = KeyBinding(keyCode: UInt32(event.keyCode),
                                     modifiers: carbonModifiers(flags),
                                     label: describe(event, flags: flags))
            let ok = HotKeyCenter.shared.rebind(action, to: binding)
            if !ok {
                conflictWarning = L10n.t("这个组合被别的程序占用了，换一个。",
                                         "Another app already owns that combination — try a different one.")
            }
            stopRecording()
            refreshLabels()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }

    private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private func describe(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> String {
        var label = ""
        if flags.contains(.control) { label += "⌃" }
        if flags.contains(.option) { label += "⌥" }
        if flags.contains(.shift) { label += "⇧" }
        if flags.contains(.command) { label += "⌘" }
        return label + keyName(for: event)
    }

    private func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        default:
            return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}


/// One display's colour, dynamic range and signal facts, collapsed by default.
///
/// Reading these costs an IORegistry walk, so the detail is built only when a
/// row is actually opened.
private struct DisplayInfoRow: View {
    let card: DisplayCard
    @State private var expanded = false
    @State private var details: DisplayDetails?

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if let details {
                Text(details.plainText())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                HStack {
                    Button(L10n.t("拷贝", "Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(details.plainText(), forType: .string)
                    }
                    .controlSize(.small)
                    Spacer()
                }
            } else {
                ProgressView().controlSize(.small)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: card.info.isBuiltin ? "laptopcomputer" : "display")
                    .foregroundStyle(.tint)
                Text(card.info.name)
                Spacer()
                Text(card.info.resolutionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: expanded) { _, isOpen in
            guard isOpen, details == nil else { return }
            let info = card.info
            DispatchQueue.global(qos: .userInitiated).async {
                let built = DetailsEngine.details(for: info)
                DispatchQueue.main.async { details = built }
            }
        }
    }
}


/// Why a Mac's text goes soft on an external monitor.
///
/// Most people meet this problem as "my expensive monitor looks worse than my
/// laptop" without ever learning why, so the explanation is the honest way to
/// describe what the Pro feature is for — it says what macOS does and what the
/// override changes, and stops there.
private struct HiDPIExplainer: View {
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                paragraph(
                    L10n.t("macOS 只有 1 倍和 2 倍两种渲染方式",
                           "macOS renders at 1× or 2×, and nothing in between"),
                    L10n.t("它没有 Windows 那种任意比例缩放。要让文字锐利，macOS 得先按 2 倍渲染，再缩到显示器的实际分辨率输出 —— 这就是 Retina 屏字好看的原因。",
                           "There is no arbitrary scaling the way Windows has it. To keep text sharp, macOS renders at twice the layout size and downsamples to the panel's real resolution. That is what makes a Retina screen look the way it does."))

                paragraph(
                    L10n.t("4K 显示器恰好卡在中间",
                           "A 4K monitor lands awkwardly in the middle"),
                    L10n.t("27 吋 4K 约 163 PPI。1 倍跑 3840×2160，界面小到费眼；2 倍跑 1920×1080，界面又大得浪费屏幕。真正合适的是「看起来像 2560×1440」，但那需要显示器报告对应的 HiDPI 模式。",
                           "A 27-inch 4K panel is about 163 PPI. At 1× you get 3840×2160 and everything is too small to read comfortably; at 2× you get 1920×1080 and everything is too big. What you actually want is \u{201C}looks like 2560×1440\u{201D} — and that needs the monitor to advertise the matching HiDPI mode."))

                paragraph(
                    L10n.t("不报告，字就发虚",
                           "If it does not advertise them, text goes soft"),
                    L10n.t("很多显示器不报告这些模式。macOS 于是只能把一个非原生分辨率直接拉伸到面板上，每个像素都经过一次重采样 —— 看起来就是「字有点糊」，而显示器本身完全没有问题。",
                           "Many monitors do not report them. macOS then stretches a non-native resolution across the panel, resampling every pixel on the way. That is the slight blur people notice — and the monitor itself is fine."))

                paragraph(
                    L10n.t("强制开启 HiDPI 做了什么",
                           "What forcing HiDPI does"),
                    L10n.t("往系统的显示器覆盖文件里补上缺失的 2 倍模式。之后 macOS 会以 5120×2880 渲染、缩到 3840×2160 输出，文字锐利，界面大小也合适。需要管理员密码，重启后生效，随时可以在同一个菜单里移除。",
                           "It writes the missing 2× modes into the system's display override file. macOS then renders at 5120×2880 and outputs 3840×2160 — sharp text at a size you can actually work at. It needs an administrator password, takes effect after a restart, and can be removed again from the same menu."))

            }
            .padding(.top, 6)
        } label: {
            Label(L10n.t("为什么 Mac 接上显示器字会发虚？",
                         "Why does text go blurry when a Mac drives a monitor?"),
                  systemImage: "questionmark.circle")
                .font(.callout)
        }
    }

    private func paragraph(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold))
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
