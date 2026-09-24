import LumenBarCore
import SwiftUI

public struct MenuRootView: View {
    public init() {}

    @EnvironmentObject private var controller: DisplayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .frame(width: 400)
        // Language changes rewrite every label in the tree.
        .id(controller.languageRevision)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            WingMark(height: 13)
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
        if controller.cards.isEmpty && controller.offRecords.isEmpty {
            // Every Mac has at least one screen, so this state is not "nothing is plugged in" —
            // it is "detection came back empty", which is a fault and not a situation. Naming
            // the fault and stopping is half an empty state: it has to say what to do next, and
            // the thing to do is right there in the header where nobody is looking at that
            // moment. The button repeats it here, where the reader already is.
            VStack(spacing: 8) {
                Image(systemName: "display.trianglebadge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(L10n.t("没有检测到显示器", "No displays detected"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(L10n.t("这台 Mac 至少有一块屏，所以这多半是检测没成功，而不是真的没有。",
                            "Every Mac has at least one screen, so this is more likely a detection that came back empty than a Mac with no display."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                Button(L10n.t("重新检测", "Detect again")) { controller.refresh() }
                    .disabled(controller.isRefreshing)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            ScrollView {
                VStack(spacing: 13) {
                    if controller.cards.filter(\.canControlBrightness).count > 1 {
                        masterBrightnessRow
                    }
                    ForEach(entries) { entry in
                        switch entry {
                        case .card(let card):
                            DisplayCardView(card: card)
                                .transition(collapse)
                        case .off(let record):
                            offRow(record)
                                .transition(collapse)
                        }
                    }
                }
                .padding(13)
                // Critically damped, from wherever the layout is now: the card and the
                // row it becomes are the same object changing size, not two things
                // swapping — no overshoot, because nothing here was thrown.
                .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                        : .spring(response: 0.3, dampingFraction: 1),
                           value: entries.map(\.id))
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

    // MARK: - Cards and the rows that replace them

    private enum Entry: Identifiable {
        case card(DisplayCard)
        case off(OffRecord)
        var id: String {
            switch self {
            case .card(let card): return "card-\(card.info.persistentKey)-\(card.id)"
            case .off(let record): return "off-\(record.id)"
            }
        }
    }

    /// Online cards, with each switched-off display's row put back in the slot
    /// its card left from. Turning a display off should not make something
    /// appear somewhere else in the panel; the way back is where the hand
    /// already is.
    private var entries: [Entry] {
        var list = controller.cards.map(Entry.card)
        for record in controller.offRecords.sorted(by: { $0.slot < $1.slot }) {
            list.insert(.off(record), at: min(max(record.slot, 0), list.count))
        }
        return list
    }

    private var collapse: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    /// A display that was switched off leaves the online list entirely, so its
    /// own card is gone — this row is the only way back.
    private func offRow(_ record: OffRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name).font(.callout)
                    Text(offReason(record))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(controller.turningOff.contains(record.key)
                       ? L10n.t("正在点亮…", "Turning on…")
                       : L10n.t("重新点亮", "Turn back on")) { controller.turnOn(record) }
                    .controlSize(.small)
                    .tint(.green)
                    .disabled(controller.turningOff.contains(record.key))
            }
            if let note = controller.notes[record.key] {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if !PowerEngine.displaysAreAsleep {
                        Button(L10n.t("移除这一行", "Remove this row")) { controller.forget(record) }
                            .controlSize(.small)
                    }
                }
                .padding(.leading, 26)
            }
            if record.key == "builtin", controller.offersAutoCollapse {
                offer(L10n.t("以后接上外接屏时，自动这样做？", "Do this by itself whenever an external display connects?"),
                      accept: L10n.t("自动收起", "Do it automatically"),
                      onAccept: controller.acceptAutoCollapse,
                      onDismiss: controller.declineAutoCollapse)
            } else if record.key == "builtin", controller.offersLoginItem {
                offer(L10n.t("已开启。它只在本应用运行时生效 —— 顺便让它开机时启动？",
                             "On. It only works while the app is running — start it at login too?"),
                      accept: L10n.t("开机时启动", "Launch at login"),
                      onAccept: {
                          controller.enableLoginItemFromOffer()
                          launchesAtLogin = LoginItem.isEnabled
                      },
                      onDismiss: controller.dismissLoginItemOffer)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(record.name), \(offReason(record))")
    }

    private func offReason(_ record: OffRecord) -> String {
        switch record.reason {
        case .automatic:
            return L10n.t("已收起 —— 接着外接屏时自动熄灭，拔掉后自己亮回来",
                          "Put away — off while an external display is connected, back when it is not")
        case .commandLine:
            return L10n.t("已用命令行熄灭，显示器本身仍然通电",
                          "Switched off from the command line — the monitor itself is still powered")
        case .manual:
            return L10n.t("已熄灭并移出桌面，显示器本身仍然通电",
                          "Off and removed from the desktop — the monitor itself is still powered")
        }
    }

    /// A one-time suggestion: a sentence, one button that does it, one that
    /// makes it go away for good. No animation of its own.
    private func offer(_ text: String, accept: String,
                       onAccept: @escaping () -> Void, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(accept, action: onAccept)
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(L10n.t("不用了", "No thanks"))
            .accessibilityLabel(L10n.t("不用了", "No thanks"))
        }
        .padding(.leading, 26)
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
                Button(L10n.t("显示器设置…", "Displays Settings…")) { controller.openDisplaySettings() }
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
                // Only ever shown when there is something to say. A permanently-present
                // "Check for Updates" that usually reports nothing trains people to ignore it;
                // a line that appears means a line worth reading.
                if let release = controller.updates.available {
                    Button(L10n.t("下载 \(release.version) 版…", "Download version \(release.version)…")) {
                        NSWorkspace.shared.open(UpdateCheck.downloadPage)
                    }
                }
                Button(L10n.t("使用提示…", "Tips…")) { controller.showWelcome() }
                Button(L10n.t("设置…", "Settings…")) { controller.openSettings() }
                Button(controller.quitTitle) { NSApplication.shared.terminate(nil) }
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
