import LumenBarCore
import SwiftUI

struct DisplayCardView: View {
    let card: DisplayCard
    @EnvironmentObject private var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            titleRow
            quickActions
            if card.canControlBrightness {
                brightnessRow
            } else {
                unavailableRow(label: L10n.t("亮度", "Brightness"),
                               reason: card.info.connection.ddcExplanation)
            }
            if let contrast = card.contrast { contrastRow(contrast) }
            warmthRow
            if card.canControlVolume {
                volumeRow
                if !card.isActiveOutput, let output = card.systemOutputName {
                    outputElsewhereNote(output)
                }
            }
            resolutionRow
            rotationRow
        }
        .padding(13)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
    }

    // MARK: - Header

    private var titleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: card.info.isBuiltin ? "laptopcomputer" : "display")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(card.info.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .layoutPriority(1)
                        .help(card.info.name)
                    if card.info.isMain {
                        badge(L10n.t("主屏", "Main"))
                            .help(L10n.t("菜单栏和 Dock 在这块屏上",
                                         "The menu bar and Dock live on this display"))
                    }
                    if card.info.isMirrored {
                        badge(L10n.t("镜像", "Mirrored"))
                            .help(L10n.t("正在显示另一块屏的画面",
                                         "Showing another display's picture"))
                    }
                    if card.isAsleep { badge(L10n.t("已关闭", "Off")) }
                    if card.isProtected {
                        badge(L10n.t("已锁定", "Locked"))
                            .help(L10n.t("外部对分辨率或方向的改动会被自动还原",
                                         "Outside changes to resolution or orientation are reverted"))
                    }
                    if card.info.connection != .builtIn {
                        badge(card.info.connection.label)
                            .help(card.info.connection.ddcExplanation)
                    }
                }
                Text(card.info.resolutionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            actionsMenu
        }
    }

    /// The two things people reach for most often, one click away.
    private var quickActions: some View {
        HStack(spacing: 8) {
            quickButton(icon: "camera.fill",
                        title: L10n.t("截图", "Capture"),
                        help: L10n.t("截取这块屏并存到桌面。\(shortcutHint("⌃⌥S"))",
                                     "Capture this display to the desktop. \(shortcutHint("⌃⌥S"))")) {
                controller.captureToFile(card)
            }

            quickButton(icon: card.isAsleep ? "power.circle.fill" : "moon.fill",
                        title: card.isAsleep ? L10n.t("点亮", "Turn on") : L10n.t("熄屏", "Turn off"),
                        help: card.isAsleep
                            ? L10n.t("重新点亮这块屏", "Bring this display back")
                            : L10n.t("把这块屏移出桌面，画面熄灭，随时可以点亮回来，其余屏幕不受影响。\(shortcutHint("⌃⌥P"))",
                                     "Takes this display off the desktop so it goes dark — always reversible, and the others are untouched. \(shortcutHint("⌃⌥P"))"),
                        tint: card.isAsleep ? .green : nil) {
                controller.toggleSleep(card)
            }

            if canMatchBrightness {
                quickButton(icon: "equal.circle.fill",
                            title: L10n.t("统一亮度", "Match all"),
                            help: L10n.t("把其他屏幕的亮度都设成这块屏的 \(Int(card.brightness * 100))%",
                                         "Set every other display's brightness to this one's \(Int(card.brightness * 100))%")) {
                    controller.matchBrightnessToAll(from: card)
                }
            }

            if !card.info.isMain {
                // Reads as an instruction, not as a label — a star captioned
                // "Main" next to a badge captioned "Main" told you nothing
                // about which display actually was the main one.
                quickButton(icon: "menubar.arrow.up.rectangle",
                            title: L10n.t("设为主屏", "Make main"),
                            help: L10n.t("把菜单栏和 Dock 移到这块屏",
                                         "Move the menu bar and Dock to this display")) {
                    controller.setAsMain(card)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func quickButton(icon: String, title: String, help: String,
                             tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(tint)
        .help(help)
    }

    /// Pointless with one screen, or when this one has no brightness to copy.
    private var canMatchBrightness: Bool {
        card.canControlBrightness
            && controller.cards.filter(\.canControlBrightness).count > 1
    }

    /// Only advertise a key combination when it is actually registered.
    /// Promising ⌃⌥S while global shortcuts are switched off sends the user
    /// hunting for a bug that is really a preference.
    private func shortcutHint(_ combination: String) -> String {
        controller.shortcutsEnabled
            ? L10n.t("快捷键 \(combination)", "Shortcut \(combination)")
            : L10n.t("在设置里打开全局快捷键后可用 \(combination)",
                     "Turn global shortcuts on in Settings to use \(combination)")
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            // A badge that wraps is worse than one that is slightly too wide:
            // two lines of badge push the whole row apart.
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.18), in: Capsule())
    }

    private var actionsMenu: some View {
        Menu {
            if !card.info.isMain {
                Button(L10n.t("设为主屏", "Make main display")) {
                    controller.setAsMain(card)
                }
            }
            Button(card.info.isMirrored
                   ? L10n.t("停止镜像", "Stop mirroring")
                   : L10n.t("镜像到主屏", "Mirror to main display")) {
                controller.toggleMirror(card)
            }

            Menu(L10n.t("颜色配置文件", "Colour profile")) {
                Section(card.colorProfileName ?? L10n.t("未知", "Unknown")) {
                    ForEach(controller.colorProfiles) { profile in
                        Button {
                            controller.applyColorProfile(profile, to: card)
                        } label: {
                            Text((profile.name == card.colorProfileName ? "✓  " : "     ") + profile.name)
                        }
                    }
                }
                Divider()
                Button(L10n.t("恢复出厂配置", "Reset to factory profile")) {
                    controller.resetColorProfile(card)
                }
            }

            if controller.cards.count > 1 && !card.info.isMain {
                Menu(L10n.t("位置", "Position")) {
                    ForEach(ArrangementEdge.allCases) { edge in
                        Button {
                            controller.place(card, edge)
                        } label: {
                            Label(L10n.t("放到主屏\(edge.label)", "Place \(edge.label.lowercased()) of the main display"),
                                  systemImage: edge.symbol)
                        }
                    }
                }
            }

            Menu(L10n.t("截图", "Screenshot")) {
                Button(L10n.t("保存到桌面", "Save to desktop")) {
                    controller.captureToFile(card)
                }
                Button(L10n.t("拷贝到剪贴板", "Copy to clipboard")) {
                    controller.captureToClipboard(card)
                }
            }

            Divider()

            if card.hasDDC {
                Button(L10n.t("给显示器断电（可能需要物理电源键唤醒）",
                              "Cut monitor power (may need its physical button to return)")) {
                    controller.turnOffBacklight(card)
                }
            }
            Button(L10n.t("仅从桌面移除（显示器仍通电）",
                          "Remove from the desktop only (monitor stays powered)")) {
                controller.softDisconnect(card)
            }
            .disabled(controller.cards.count < 2)

            if !card.info.isBuiltin && card.canControlBrightness {
                Button {
                    controller.toggleFollowBuiltIn(card)
                } label: {
                    Text((card.followsBuiltIn ? "✓  " : "     ")
                         + L10n.t("跟随内建屏亮度", "Follow the built-in display's brightness"))
                }
            }
            if !availableInputs.isEmpty {
                Menu(L10n.t("输入源", "Input source")) {
                    ForEach(availableInputs, id: \.self) { raw in
                        Button {
                            controller.selectInput(rawValue: raw, for: card)
                        } label: {
                            Text((card.inputSourceRaw == raw ? "✓  " : "     ")
                                 + InputEngine.label(forRawValue: raw))
                        }
                    }
                }
            }
            if card.ddcChannelCount > 1 {
                Menu(L10n.t("DDC 通道", "DDC channel")) {
                    ForEach(0 ..< card.ddcChannelCount, id: \.self) { channel in
                        Button {
                            controller.setDDCChannel(channel, for: card)
                        } label: {
                            Text((card.ddcChannel == channel ? "✓  " : "     ")
                                 + L10n.t("通道 \(channel)", "Channel \(channel)"))
                        }
                    }
                }
            }

            Divider()

            Button(L10n.t("重命名…", "Rename…")) {
                controller.renameDisplay(card)
            }
            Button {
                controller.toggleProtection(card)
            } label: {
                Text((card.isProtected ? "✓  " : "     ")
                     + L10n.t("锁定分辨率和方向", "Lock resolution and orientation"))
            }

            if !card.info.isBuiltin {
                if card.hasHiDPIOverride {
                    Button(L10n.t("移除 HiDPI 覆盖…", "Remove the HiDPI override…")) {
                        controller.removeHiDPIOverride(card)
                    }
                } else {
                    Button {
                        controller.forceHiDPI(card)
                    } label: {
                        Label(controller.isPro
                              ? L10n.t("强制开启 HiDPI…（需重启）", "Force HiDPI on… (needs a restart)")
                              : L10n.t("强制开启 HiDPI…（Pro）", "Force HiDPI on… (Pro)"),
                              systemImage: controller.isPro ? "sparkles.rectangle.stack" : "lock")
                    }
                }
            }

            Button(L10n.t("显示器详情…", "Display details…")) {
                controller.dismissPopover?()
                let details = DetailsEngine.details(for: card.info)
                LumenBarWindow.show(id: "details-\(card.id)", title: card.info.name) {
                    DisplayDetailsView(details: details)
                }
            }

            Section(L10n.t("诊断", "Diagnostics")) {
                Text(L10n.t("亮度：\(card.brightnessChannel.label)",
                            "Brightness: \(card.brightnessChannel.label)"))
                Text(L10n.t("音量：\(card.volumeChannel.label)",
                            "Volume: \(card.volumeChannel.label)"))
                Text(L10n.t("连接：\(card.info.connection.diagnosticLabel)",
                            "Connection: \(card.info.connection.diagnosticLabel)"))
                Text(L10n.t("DDC：\(card.hasDDC ? "已连接" : "无")",
                            "DDC: \(card.hasDDC ? "connected" : "none")"))
                Text(modeSummary)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.t("这块屏的更多操作", "More actions for this display"))
    }

    private var modeSummary: String {
        let total = card.allModes.count
        let hidpi = card.allModes.filter(\.isHiDPI).count
        return L10n.t("模式：\(total) 个，其中 HiDPI \(hidpi) 个",
                      "Modes: \(total), of which \(hidpi) HiDPI")
    }

    // MARK: - Sliders

    private var brightnessRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            SliderRow(
                icon: "sun.max.fill",
                value: Binding(get: { card.brightness },
                               set: { controller.setBrightness($0, for: card) }),
                trailing: card.brightnessChannel.label,
                trailingHelp: card.brightnessChannel.explanation,
                iconHelp: L10n.t("亮度", "Brightness"))

            // Software dimming is not real brightness, and pretending otherwise
            // is the kind of thing that makes people think the app is broken.
            if card.brightnessChannel == .gamma {
                Text(L10n.t("软件调光：背光不变，只是画面变暗",
                            "Software dimming: the backlight is unchanged, only the picture darkens"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 26)
            }
        }
    }

    private func contrastRow(_ contrast: Double) -> some View {
        SliderRow(
            icon: "circle.lefthalf.filled",
            value: Binding(get: { contrast },
                           set: { controller.setContrast($0, for: card) }),
            trailing: L10n.t("对比度", "Contrast"),
            trailingHelp: L10n.t("通过 DDC/CI 调节显示器对比度。",
                                 "Adjusts the monitor's contrast over DDC/CI."),
            iconHelp: L10n.t("对比度", "Contrast"))
    }

    /// Colour temperature works on any display, wired or not — it is a gamma
    /// curve, not a hardware control.
    private var warmthRow: some View {
        SliderRow(
            icon: "thermometer.sun.fill",
            value: Binding(get: { card.warmth },
                           set: { controller.setWarmth($0, for: card) }),
            trailing: L10n.t("色温", "Warmth"),
            trailingHelp: L10n.t("向右更暖（减少蓝光）。系统的 Night Shift 是全局的，这里是单块屏的调整；两者会叠加。",
                                 "Right is warmer (less blue). Night Shift is system-wide; this is per display, and the two stack."),
            iconHelp: L10n.t("色温", "Colour temperature"))
    }

    private var volumeRow: some View {
        SliderRow(
            icon: card.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            value: Binding(get: { card.isMuted ? 0 : card.volume },
                           set: { controller.setVolume($0, for: card) }),
            trailing: card.audioDeviceName ?? card.volumeChannel.label,
            trailingHelp: card.volumeChannel.explanation,
            iconHelp: card.isMuted ? L10n.t("取消静音", "Unmute") : L10n.t("静音", "Mute"),
            onIconTap: { controller.toggleMute(card) })
    }

    /// The slider above moves this monitor's own speakers — which are silent
    /// when macOS is playing through something else. Saying so is the whole
    /// point: a volume control that changes nothing you can hear is worse than
    /// no volume control at all.
    private func outputElsewhereNote(_ output: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: card.systemOutputKind == "AirPlay"
                  ? "airplayaudio"
                  : (card.systemOutputKind == L10n.t("蓝牙", "Bluetooth") ? "wave.3.right" : "hifispeaker"))
                .imageScale(.small)
            Text(L10n.t("当前输出：\(output)", "Now playing on \(output)"))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.leading, 26)
        .help(L10n.t("系统声音正走 \(output)，所以这条滑块调的是这台显示器自己的扬声器，你现在听不到它。音量键也会交还 macOS，去调真正在发声的设备。",
                     "System audio is going to \(output), so the slider above moves this display's own speakers, which you cannot hear right now. The volume keys are handed back to macOS too, so they move whatever is actually playing."))
    }

    private func unavailableRow(label: String, reason: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(reason)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Resolution

    private var resolutionRow: some View {
        HStack(spacing: 8) {
            rowLabel(L10n.t("分辨率", "Resolution"))

            Menu {
                // Only the sharp ones up front. A 1x mode on a Retina panel is
                // a downgrade nobody picks by accident, so it moves out of the way.
                ForEach(shortList) { mode in
                    modeButton(mode)
                }
                Divider()
                Menu(L10n.t("全部模式（\(card.allModes.count)）",
                            "All modes (\(card.allModes.count))")) {
                    let hidpi = card.allModes.filter(\.isHiDPI)
                    let standard = card.allModes.filter { !$0.isHiDPI }
                    if !hidpi.isEmpty {
                        Section(L10n.t("HiDPI · 清晰", "HiDPI · sharp")) {
                            ForEach(hidpi) { modeButton($0, detailed: true) }
                        }
                    }
                    if !standard.isEmpty {
                        Section(L10n.t("1x · 在高分屏上会发虚", "1x · soft on a dense panel")) {
                            ForEach(standard) { modeButton($0, detailed: true) }
                        }
                    }
                }
            } label: {
                Text(currentResolutionLabel)
            }
            .menuStyle(.borderlessButton)
            .help(hiDPIHelp)

            if !card.refreshOptions.isEmpty {
                Menu {
                    ForEach(card.refreshOptions) { mode in
                        Button((mode.id == card.currentMode?.id ? "✓  " : "     ") + mode.refreshLabel) {
                            controller.applyMode(mode, for: card)
                        }
                    }
                } label: {
                    Text(card.currentMode?.refreshLabel ?? "—")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.t("刷新率", "Refresh rate"))
            }
        }
    }

    /// What the monitor says it accepts; empty when it says nothing.
    private var availableInputs: [UInt16] {
        if let listed = card.ddcCapabilities?.inputSources, !listed.isEmpty {
            return listed.map(UInt16.init)
        }
        return card.hasDDC ? InputSource.allCases.map(\.rawValue) : []
    }

    /// HiDPI entries, or the plain list when the display offers no HiDPI at all.
    private var shortList: [DisplayMode] {
        card.hidpiModes.isEmpty ? card.recommendedModes : card.hidpiModes
    }

    /// The icon carries the sharp/soft distinction, since menu items cannot be
    /// reliably tinted on macOS.
    private func modeButton(_ mode: DisplayMode, detailed: Bool = false) -> some View {
        Button {
            controller.applyMode(mode, for: card)
        } label: {
            Label {
                Text((mode.id == card.currentMode?.id ? "✓  " : "     ")
                     + (detailed ? mode.describe() : mode.pointsLabel + (mode.isHiDPI ? "  ·  HiDPI" : "  ·  1x")))
            } icon: {
                Image(systemName: mode.isHiDPI ? "sparkles" : "square.dashed")
            }
        }
    }

    private var currentResolutionLabel: String {
        guard let mode = card.currentMode else { return L10n.t("未知", "Unknown") }
        return mode.pointsLabel + (mode.isHiDPI ? "  HiDPI" : "  1x")
    }

    private var hiDPIHelp: String {
        let base = L10n.t(
            "HiDPI 以 2 倍像素渲染再输出，文字锐利；1x 按标注尺寸直接渲染，在高分屏上会发虚。切换后有 15 秒确认，不确认自动还原。",
            "HiDPI renders at 2× and downsamples, keeping text sharp. 1x renders at the labelled size and looks soft on a dense panel. Every switch has a 15-second confirmation and reverts itself if you do nothing.")
        guard card.isLoaded, !card.allModes.contains(where: \.isHiDPI) else { return base }
        return base + "\n\n" + L10n.t(
            "这块屏没有报告任何 HiDPI 模式。",
            "This display reports no HiDPI modes at all.")
    }

    // MARK: - Rotation

    @ViewBuilder
    private var rotationRow: some View {
        if card.rotationSupported {
            HStack(spacing: 8) {
                rowLabel(L10n.t("方向", "Orientation"))
                Picker("", selection: Binding(
                    get: { card.info.rotation },
                    set: { controller.rotate(card, to: $0) })) {
                        ForEach(Rotation.allCases) { rotation in
                            Text(rotation.label).tag(rotation)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help(L10n.t("旋转后有 15 秒确认，不确认自动转回来",
                                 "A rotation has 15 seconds to be confirmed, and turns back on its own if you do nothing"))
            }
        } else {
            unavailableRow(label: L10n.t("方向", "Orientation"), reason: rotationUnavailableReason)
        }
    }

    private var rotationUnavailableReason: String {
        L10n.t("这块屏拒绝了旋转请求", "This display refuses rotation requests")
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .leading)
    }
}

/// Icon + slider + right-hand caption, sized so the captions line up down the card.
struct SliderRow: View {
    let icon: String
    @Binding var value: Double
    var trailing: String
    var trailingHelp: String?
    var iconHelp: String?
    var onIconTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let onIconTap {
                    Button(action: onIconTap) { Image(systemName: icon) }
                        .buttonStyle(.borderless)
                } else {
                    Image(systemName: icon)
                }
            }
            .frame(width: 18)
            .foregroundStyle(.secondary)
            .help(iconHelp ?? "")

            Slider(value: $value, in: 0 ... 1)

            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 34, alignment: .trailing)

            Text(trailing)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 55, alignment: .leading)
                .help(trailingHelp ?? trailing)
        }
    }
}
