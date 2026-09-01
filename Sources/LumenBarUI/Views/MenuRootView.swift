import LumenBarCore
import SwiftUI

public struct MenuRootView: View {
    public init() {}

    @EnvironmentObject private var controller: DisplayController
    @State private var launchesAtLogin = LoginItem.isEnabled

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            displayList
            statusBar
            Divider()
            footer
        }
        .frame(width: 377)
        // Language changes rewrite every label in the tree.
        .id(controller.languageRevision)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "display")
                .foregroundStyle(.tint)
            Text("PWE Lumen Bar").font(.headline)
            if controller.isRefreshing {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }
            Spacer()
            Text(displayCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                controller.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("重新检测显示器和它们支持的功能",
                         "Re-detect displays and the controls each one supports"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var displayCountLabel: String {
        let count = controller.cards.count
        return L10n.isChinese
            ? "\(count) 块屏幕"
            : (count == 1 ? "1 display" : "\(count) displays")
    }

    // MARK: - Displays

    @ViewBuilder
    private var displayList: some View {
        if controller.cards.isEmpty && controller.offDisplays.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "display.trianglebadge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(L10n.t("没有检测到显示器", "No displays detected"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            ScrollView {
                VStack(spacing: 13) {
                    if controller.cards.filter(\.canControlBrightness).count > 1 {
                        masterBrightnessRow
                    }
                    ForEach(controller.cards) { card in
                        DisplayCardView(card: card)
                    }
                    ForEach(controller.offDisplays) { entry in
                        offDisplayRow(entry)
                    }
                }
                .padding(13)
            }
            .frame(maxHeight: 610)
        }
    }

    /// One slider that moves every display at once, for the common case of
    /// "the room got darker".
    private var masterBrightnessRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.circle.fill")
                .foregroundStyle(.tint)
                .frame(width: 18)
            Text(L10n.t("全部", "All"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { controller.averageBrightness },
                                  set: { controller.setBrightnessForAll($0) }), in: 0 ... 1)
            Text("\(Int((controller.averageBrightness * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .help(L10n.t("同时调节所有支持亮度控制的屏幕",
                     "Move every display that has a working brightness channel"))
    }

    /// A display that was switched off leaves the online list entirely, so its
    /// own card is gone — this row is the only way back.
    private func offDisplayRow(_ entry: OffDisplay) -> some View {
        HStack {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.info.name).font(.callout)
                Text(entry.method == .ddc
                     ? L10n.t("显示器已断电", "The monitor is powered down")
                     : L10n.t("已关闭并移出桌面，显示器本身仍然通电",
                              "Off and removed from the desktop — the monitor itself is still powered"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(L10n.t("重新点亮", "Turn back on")) { controller.wake(entry.info) }
                .controlSize(.small)
                .tint(.green)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Status

    @ViewBuilder
    private var statusBar: some View {
        if let status = controller.status {
            Divider()
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                Text(status).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    controller.status = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                controller.sleepAll()
            } label: {
                Label(L10n.t("全部休眠", "Sleep all"), systemImage: "moon.fill")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("让所有显示器立刻进入休眠，动一下鼠标即可唤醒",
                         "Put every display to sleep now — any input wakes them"))

            if controller.cards.filter(\.canControlBrightness).count > 1 {
                Button {
                    controller.setBrightnessLinked(!controller.brightnessLinked)
                } label: {
                    Label(L10n.t("联动", "Link"),
                          systemImage: controller.brightnessLinked ? "link.circle.fill" : "link.circle")
                }
                .buttonStyle(.borderless)
                .tint(controller.brightnessLinked ? .accentColor : nil)
                .help(L10n.t("开启后，拖动任意一块屏的亮度，其余屏幕按开启那一刻的比例一起动。和「统一亮度」不同 —— 联动保留各屏之间的差异，统一则把它们拉成同一个值。",
                             "With this on, dragging any display's brightness moves the others by the ratio they had when you switched it on. Unlike Match brightness, linking preserves the differences between screens instead of flattening them."))
            }

            if let reference = matchReference {
                Button {
                    controller.matchBrightnessToAll(from: reference)
                } label: {
                    Label(L10n.t("统一亮度", "Match brightness"), systemImage: "equal.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(L10n.t("把所有屏幕的亮度对齐到主屏（\(reference.info.name)，\(Int(reference.brightness * 100))%）。每张卡片上也有同样的按钮，可以改用那块屏做基准。",
                             "Bring every display to the main one's brightness (\(reference.info.name), \(Int(reference.brightness * 100))%). Each card has the same button if you would rather match to that display instead."))
            }

            Spacer()

            Menu {
                Menu(L10n.t("场景", "Presets")) {
                    if controller.presets.isEmpty {
                        Text(L10n.t("还没有场景", "No presets yet"))
                    } else {
                        ForEach(controller.presets) { preset in
                            Button(preset.name) { controller.applyPreset(preset) }
                        }
                        Divider()
                        Menu(L10n.t("删除", "Delete")) {
                            ForEach(controller.presets) { preset in
                                Button(preset.name) { controller.deletePreset(preset) }
                            }
                        }
                    }
                    Divider()
                    Button(L10n.t("把当前状态存为场景…", "Save current state as a preset…")) {
                        guard let name = Prompt.text(
                            title: L10n.t("存为场景", "Save preset"),
                            message: L10n.t("会记录每块屏的亮度、色温、音量、分辨率、方向、位置和颜色配置。",
                                            "Records each display's brightness, warmth, volume, resolution, orientation, position and colour profile."))
                        else { return }
                        controller.savePreset(named: name)
                    }
                }
                Divider()
                Button(L10n.t("重新检测显示器", "Re-detect displays")) { controller.refresh() }
                Button(L10n.t("截取所有屏幕", "Capture every display")) {
                    controller.captureAllToFiles()
                }
                if controller.cards.count > 1 {
                    Button(L10n.t("水平排列所有屏幕", "Tile displays horizontally")) {
                        controller.tileHorizontally()
                    }
                }

                Menu(L10n.t("语言", "Language")) {
                    ForEach(Language.allCases, id: \.self) { language in
                        Button {
                            controller.setLanguage(language)
                        } label: {
                            Text(checkmark(L10n.override == language) + language.displayName)
                        }
                    }
                }

                Button {
                    controller.setRememberEnabled(!controller.rememberEnabled)
                } label: {
                    Text(checkmark(controller.rememberEnabled)
                         + L10n.t("记住每块屏的设置", "Remember each display's settings"))
                }

                Button {
                    controller.setAutoDisconnectBuiltIn(!controller.autoDisconnectBuiltIn)
                } label: {
                    Text(checkmark(controller.autoDisconnectBuiltIn)
                         + L10n.t("接外接屏时收起内建屏", "Put the built-in panel away when an external display connects"))
                }

                Menu(L10n.t("全局快捷键", "Global shortcuts")) {
                    Button {
                        controller.applyShortcutSetting(!controller.shortcutsEnabled)
                    } label: {
                        Text(checkmark(controller.shortcutsEnabled)
                             + L10n.t("启用", "Enabled"))
                    }
                    Divider()
                    Section(L10n.t("作用于光标所在的屏幕", "Acts on the display under the pointer")) {
                        ForEach(HotKeyCenter.Action.allCases, id: \.self) { action in
                            Text("\(action.shortcutLabel)    \(action.describe)")
                        }
                    }
                }

                Button {
                    LoginItem.setEnabled(!launchesAtLogin)
                    launchesAtLogin = LoginItem.isEnabled
                } label: {
                    Text(checkmark(launchesAtLogin) + L10n.t("开机时启动", "Launch at login"))
                }

                Divider()
                Button(L10n.t("使用提示…", "Tips…")) { controller.showWelcome() }
                Button(L10n.t("设置…", "Settings…")) { controller.openSettings() }
                Button(L10n.t("退出 PWE Lumen Bar", "Quit PWE Lumen Bar")) { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// The main display is the sensible default reference; the per-card
    /// buttons cover the case where another screen is the one you trust.
    private var matchReference: DisplayCard? {
        let controllable = controller.cards.filter(\.canControlBrightness)
        guard controllable.count > 1 else { return nil }
        return controllable.first(where: { $0.info.isMain }) ?? controllable.first
    }

    /// SwiftUI menus give no checked state for plain buttons, so the mark is
    /// part of the title — with matching width when unchecked so nothing shifts.
    private func checkmark(_ on: Bool) -> String { on ? "✓  " : "     " }
}

#Preview {
    MenuRootView()
        .environmentObject(DisplayController(previewCards: PreviewData.sampleCards()))
}
