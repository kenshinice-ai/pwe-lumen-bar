import AppKit
import Foundation
import LumenBarCore

// A thin harness over LumenBarCore so every engine can be exercised without the
// menu bar UI — which is also how the risky paths (rotation, disconnect) get
// tested with an escape hatch.

var arguments = Array(CommandLine.arguments.dropFirst())

// Engine tracing is opt-in. It is useful when diagnosing a display, and noise
// the rest of the time.
if let index = arguments.firstIndex(where: { $0 == "--verbose" || $0 == "-v" }) {
    Log.echoToStderr = true
    arguments.remove(at: index)
}

// --lang overrides the display language for this invocation only; it must not
// write the user defaults the app reads.
if let index = arguments.firstIndex(of: "--lang"), arguments.count > index + 1 {
    L10n.transientOverride = Language(rawValue: arguments[index + 1]) ?? .system
    arguments.removeSubrange(index ... index + 1)
}

let registry = DisplayRegistry.shared

func displays() -> [DisplayInfo] { registry.onlineDisplays() }

func display(matching token: String) -> DisplayInfo? {
    let all = displays()
    if let id = UInt32(token), let match = all.first(where: { $0.id == id }) { return match }
    if let index = Int(token), index < all.count, token.count <= 2 { return all[index] }
    return all.first { $0.name.localizedCaseInsensitiveContains(token) }
}

func requireDisplay(_ token: String?) -> DisplayInfo {
    guard let token, let display = display(matching: token) else {
        print(L10n.t("找不到显示器：\(token ?? "(未指定)")",
                     "No such display: \(token ?? "(not specified)")"))
        print(L10n.t("可用：", "Available: ")
              + displays().map { "\($0.id)=\($0.name)" }.joined(separator: ", "))
        exit(1)
    }
    return display
}

/// Fail loudly and with the right exit code. Every operation failure ends here,
/// so that scripting `pwelumenctl` is possible at all.
func fail(_ message: String) -> Never {
    print(message)
    exit(1)
}

/// A 0–100 argument, rejected rather than silently clamped or misread. Without
/// this, `brightness 1 -20` reported "-20%" while setting 0, and
/// `brightness 1 abc` fell through to the read branch and looked successful.
func percentArgument(_ raw: String, label: String) -> Double {
    guard let value = Double(raw) else {
        fail(L10n.t("\(label)需要一个 0-100 的数字，收到「\(raw)」",
                    "\(label) needs a number from 0 to 100, got \u{201C}\(raw)\u{201D}"))
    }
    guard value >= 0, value <= 100 else {
        fail(L10n.t("\(label)必须在 0 到 100 之间，收到 \(Int(value))",
                    "\(label) must be between 0 and 100, got \(Int(value))"))
    }
    return value / 100
}

func percent(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.0f%%", value * 100)
}

func usage() {
    print(L10n.t("""
    pwelumenctl — PWE Lumen Bar 引擎的命令行入口

      list                          列出显示器
      warmth <屏> [0-100]           读取/设置色温
      diag                          能力诊断（每块屏能走哪条通道）
      modes <屏> [--all]            列出分辨率（默认只列推荐项）
      set-mode <屏> <modeID>        切换分辨率（可加 --revert <秒> 自动回滚）
      brightness <屏> [0-100]       读取/设置亮度
      contrast <屏> [0-100]         读取/设置对比度（仅 DDC）
      volume <屏> [0-100]           读取/设置音量
      mute <屏> on|off              静音
      input <屏> [名称]             读取/切换输入源（仅 DDC）
      rotate <屏> <0|90|180|270>    旋转（15 秒内不确认自动回滚）
      rotate-probe <屏>             只探测旋转通道，不真的转
      power <屏> on|off|standby     DDC 电源（外接屏）
      off <屏> / on [屏]            关闭 / 重新点亮单块屏
      disconnect <屏> / connect <屏> 软断开 / 重新接入
      main <屏>                     设为主屏
      capture <屏> [目录]           截取指定屏幕（默认存到桌面）
      color <屏> [配置名]           查看/切换颜色配置文件
      name <屏> [新名字|-]          查看 / 修改显示器名称
      follow <屏> [on|off]          外接屏跟随内建屏亮度
      protect <屏> [on|off]         锁定分辨率和方向
      log [行数]                    查看诊断日志（app 与命令行共用）
      details <屏>                  显示器详情（含 EDID 可用性）
      edid <屏> [文件]              查看 / 导出 EDID
      hidpi <屏> [show|install|remove]  强制开启 HiDPI（Pro，需重启）
      license show|activate <邮箱> <密钥>|deactivate   Pro 授权
      preset list|save|apply|delete <名称>   场景
      arrange <屏> left|right|above|below  |  arrange tile   屏幕排列
      remember on|off|show|clear    每块屏的设置记忆
      audio                         列出音频输出设备（并说明音量键归谁）
      compat                        系统兼容性自检（私有接口是否都在）
      sleep                         让所有显示器休眠

    <屏> 可以是显示器 ID、序号，或名字的一部分。
      caps <屏>                     显示器自报的 DDC capabilities
      vcp <屏> <十六进制码>          直接读取一个 VCP 值

    加 --lang zh|en 切换输出语言，加 --verbose 打开引擎调试输出。
    """, """
    pwelumenctl — command line access to the PWE Lumen Bar engines

      list                          list displays
      warmth <disp> [0-100]         read / set colour temperature
      diag                          capability report (which channel each display uses)
      modes <disp> [--all]          list resolutions (recommended ones by default)
      set-mode <disp> <modeID>      switch resolution (add --revert <seconds> to auto-revert)
      brightness <disp> [0-100]     read / set brightness
      contrast <disp> [0-100]       read / set contrast (DDC only)
      volume <disp> [0-100]         read / set volume
      mute <disp> on|off            mute
      input <disp> [name]           read / switch input source (DDC only)
      rotate <disp> <0|90|180|270>  rotate (reverts unless confirmed within 15s)
      rotate-probe <disp>           probe the rotation channel without rotating
      power <disp> on|off|standby   DDC power (external displays)
      off <disp> / on [disp]        turn one display off / back on
      disconnect <disp> / connect <disp>   soft disconnect / reattach
      main <disp>                   make this the main display
      capture <disp> [dir]          capture one display (saves to the desktop by default)
      color <disp> [name]           show / switch the colour profile
      name <disp> [new|-]           show / change the display's name
      follow <disp> [on|off]        external display follows the built-in brightness
      protect <disp> [on|off]       lock resolution and orientation
      log [lines]                   read the diagnostic log (shared by app and CLI)
      details <disp>                full report for one display
      edid <disp> [file]            show / export the EDID block
      hidpi <disp> [show|install|remove]  force HiDPI on (Pro, needs a restart)
      license show|activate <email> <key>|deactivate   Pro licence
      preset list|save|apply|delete <name>   presets
      arrange <disp> left|right|above|below  |  arrange tile   display arrangement
      remember on|off|show|clear    per-display settings memory
      audio                         list audio output devices (and who owns the volume keys)
      compat                        system compatibility self-check (are the private entry points there)
      sleep                         put all displays to sleep

    <disp> can be a display ID, an index, or part of the name.
      caps <disp>                   the monitor's own DDC capabilities string
      vcp <disp> <hex code>         read one VCP value directly

    Add --lang zh|en to switch the language, --verbose for engine tracing.
    """))
}

switch arguments.first {
case "list":
    for display in displays() {
        let flags = [display.connection.label,
                     display.isMain ? L10n.t("主屏", "main") : nil,
                     display.isMirrored ? L10n.t("镜像中", "mirrored") : nil].compactMap { $0 }
        print("[\(display.id)] \(display.name)  (\(flags.joined(separator: "/")))")
        print("      \(display.resolutionSummary)   "
              + L10n.t("旋转 \(display.rotation.label)   缩放 \(display.backingScale)x",
                       "rotation \(display.rotation.label)   scale \(display.backingScale)x"))
        if let mode = display.currentMode {
            print("      " + L10n.t("当前模式", "current mode") + " #\(mode.id): \(mode.describe())")
        }
    }

case "diag":
    print(L10n.t("DDC 支持: \(DDCService.isSupported ? "是" : "否")   外接 DDC 通道数: \(DDCRegistry.shared.availableChannelCount())",
                 "DDC available: \(DDCService.isSupported ? "yes" : "no")   external DDC channels: \(DDCRegistry.shared.availableChannelCount())"))
    print(L10n.t("软断开支持: \(PowerEngine.supportsSoftDisconnect ? "是" : "否")",
                 "Soft disconnect: \(PowerEngine.supportsSoftDisconnect ? "supported" : "unsupported")"))
    print("")
    for display in displays() {
        print("[\(display.id)] \(display.name)  key=\(display.persistentKey)")
        print("    " + L10n.t("连接   : ", "Connection : ") + display.connection.diagnosticLabel)
        let brightnessChannel = BrightnessEngine.shared.channel(for: display)
        print("    " + L10n.t("亮度   : ", "Brightness : ")
              + "\(brightnessChannel.label)  \(percent(BrightnessEngine.shared.brightness(of: display)))")
        let volumeChannel = AudioEngine.shared.channel(for: display)
        let device = AudioEngine.shared.device(for: display)
        print("    " + L10n.t("音量   : ", "Volume     : ")
              + "\(volumeChannel.label)  \(device?.name ?? "—")  \(percent(AudioEngine.shared.volume(of: display)))")
        print("    " + L10n.t("旋转   : ", "Rotation   : ")
              + (RotationEngine.isSupported(for: display)
                 ? L10n.t("可用", "supported") : L10n.t("不可用", "unsupported"))
              + "  \(display.rotation.label)")
        if display.connection.canCarryDDC {
            let input = InputEngine.currentRawValue(for: display)
            print("    " + L10n.t("输入源 : ", "Input      : ")
                  + (input.map { InputSource(rawValue: $0)?.label ?? "0x\(String($0, radix: 16))" } ?? "—"))
        }
        let modes = ModeEngine.allModes(for: display.id)
        let hidpi = modes.filter { $0.isHiDPI && $0.usableForDesktop }
        print("    " + L10n.t("分辨率 : 共 \(modes.count) 个模式，其中 HiDPI \(hidpi.count) 个",
                              "Modes      : \(modes.count) total, \(hidpi.count) HiDPI"))
    }

case "modes":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    let showAll = arguments.contains("--all")
    let modes = showAll ? ModeEngine.allModes(for: display.id)
                        : ModeEngine.curatedModes(for: display.id)
    print("\(display.name) — " + L10n.t("\(modes.count) 个模式\(showAll ? "（全部）" : "（推荐）")",
                                        "\(modes.count) modes\(showAll ? " (all)" : " (recommended)")"))
    let currentID = display.currentMode?.id
    for mode in modes {
        let marker = mode.id == currentID ? "→" : " "
        let usable = mode.usableForDesktop ? "" : L10n.t("  [非桌面]", "  [not for desktop]")
        print(" \(marker) #\(mode.id)  \(mode.describe())\(usable)")
    }

case "set-mode":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    guard arguments.count > 2,
          let mode = ModeEngine.allModes(for: display.id).first(where: { $0.id == arguments[2] }) else {
        print(L10n.t("用法: pwelumenctl set-mode <屏> <modeID>   (modeID 形如 cgs:3)",
                     "Usage: pwelumenctl set-mode <disp> <modeID>   (modeID looks like cgs:3)"))
        exit(1)
    }
    let previous = ModeEngine.currentMode(for: display.id)
    guard ModeEngine.apply(mode, to: display.id) else {
        print(L10n.t("切换失败", "Switch failed")); exit(1)
    }
    DisplaySettingsStore.shared.update(display.persistentKey) { $0.modeID = mode.id }
    print(L10n.t("已切换到 \(mode.describe())", "Switched to \(mode.describe())"))
    // --revert N: apply, verify it landed, then put it back. The app uses the
    // same shape as a confirmation dialog so a bad mode cannot strand anyone.
    if let flag = arguments.firstIndex(of: "--revert"), arguments.count > flag + 1,
       let seconds = Double(arguments[flag + 1]), let previous {
        usleep(1_500_000)
        let landed = ModeEngine.currentMode(for: display.id)
        print(L10n.t("生效验证: 当前 = \(landed?.describe() ?? "?")  \(landed?.id == mode.id ? "✓ 匹配" : "✗ 不匹配")",
                     "Verified: now \(landed?.describe() ?? "?")  \(landed?.id == mode.id ? "✓ match" : "✗ mismatch")"))
        usleep(useconds_t(max(0, seconds - 1.5) * 1_000_000))
        print(ModeEngine.apply(previous, to: display.id)
              ? L10n.t("已回滚到 \(previous.describe())", "Reverted to \(previous.describe())")
              : L10n.t("回滚失败！", "Revert failed!"))
    }

case "brightness":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    let channel = BrightnessEngine.shared.channel(for: display)
    if arguments.count > 2 {
        let value = percentArgument(arguments[2], label: L10n.t("亮度", "Brightness"))
        guard BrightnessEngine.shared.setBrightness(value, for: display) else {
            fail(L10n.t("\(display.name) 不接受亮度调节", "\(display.name) did not accept it"))
        }
        DisplaySettingsStore.shared.update(display.persistentKey) { $0.brightness = value }
        print("\(display.name)  " + L10n.t("亮度 → \(Int(value * 100))%  via \(channel.label)",
                                            "brightness → \(Int(value * 100))%  via \(channel.label)"))
    } else {
        print("\(display.name)  "
              + L10n.t("亮度 \(percent(BrightnessEngine.shared.brightness(of: display)))  via \(channel.label)",
                       "brightness \(percent(BrightnessEngine.shared.brightness(of: display)))  via \(channel.label)"))
    }

case "contrast":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    // Contrast is DDC-only; say so rather than printing an empty value.
    guard DDCRegistry.shared.isResponsive(display) else {
        fail("\(display.name)  " + L10n.t("没有 DDC 通道，无法调节对比度。\(display.connection.ddcExplanation)",
                                           "has no DDC channel, so contrast is unavailable. \(display.connection.ddcExplanation)"))
    }
    if arguments.count > 2 {
        let value = percentArgument(arguments[2], label: L10n.t("对比度", "Contrast"))
        guard BrightnessEngine.shared.setContrast(value, for: display) else {
            fail(L10n.t("设置失败", "Failed"))
        }
        DisplaySettingsStore.shared.update(display.persistentKey) { $0.contrast = value }
        print("\(display.name)  " + L10n.t("对比度 → \(Int(value * 100))%  via DDC",
                                            "contrast → \(Int(value * 100))%  via DDC"))
    } else {
        print("\(display.name)  " + L10n.t("对比度 \(percent(BrightnessEngine.shared.contrast(of: display)))  via DDC",
                                            "contrast \(percent(BrightnessEngine.shared.contrast(of: display)))  via DDC"))
    }

case "volume":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    let volumeChannel = AudioEngine.shared.channel(for: display)
    if arguments.count > 2 {
        let value = percentArgument(arguments[2], label: L10n.t("音量", "Volume"))
        guard AudioEngine.shared.setVolume(value, for: display) else {
            fail(L10n.t("\(display.name) 不接受音量调节", "\(display.name) did not accept it"))
        }
        DisplaySettingsStore.shared.update(display.persistentKey) { $0.volume = value }
        print("\(display.name)  " + L10n.t("音量 → \(Int(value * 100))%  via \(volumeChannel.label)",
                                            "volume → \(Int(value * 100))%  via \(volumeChannel.label)"))
    } else {
        print("\(display.name)  "
              + L10n.t("音量 \(percent(AudioEngine.shared.volume(of: display)))  via \(volumeChannel.label)",
                       "volume \(percent(AudioEngine.shared.volume(of: display)))  via \(volumeChannel.label)"))
    }

case "warmth":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    if arguments.count > 2 {
        let value = percentArgument(arguments[2], label: L10n.t("色温", "Warmth"))
        guard BrightnessEngine.shared.setWarmth(value, for: display) else {
            fail(L10n.t("设置失败", "Failed"))
        }
        DisplaySettingsStore.shared.update(display.persistentKey) { $0.warmth = value }
        print("\(display.name)  " + L10n.t("色温 → \(Int(value * 100))%", "warmth → \(Int(value * 100))%"))
    } else {
        print("\(display.name)  " + L10n.t("色温 \(percent(BrightnessEngine.shared.warmth(of: display)))",
                                            "warmth \(percent(BrightnessEngine.shared.warmth(of: display)))"))
    }

case "mute":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    guard arguments.count > 2, ["on", "off"].contains(arguments[2]) else {
        fail(L10n.t("用法: pwelumenctl mute <屏> on|off", "Usage: pwelumenctl mute <disp> on|off"))
    }
    let muted = arguments[2] == "on"
    guard AudioEngine.shared.setMuted(muted, for: display) else {
        fail(L10n.t("\(display.name) 不支持静音控制", "\(display.name) does not support mute control"))
    }
    print("\(display.name)  " + L10n.t("静音 → \(muted ? "开" : "关")", "mute → \(muted ? "on" : "off")"))

case "input":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    let capabilities = DDCRegistry.shared.capabilities(for: display)
    if arguments.count > 2 {
        let wanted = arguments[2].lowercased()
        let raw = InputSource.allCases.first {
            $0.label.lowercased().replacingOccurrences(of: " ", with: "") == wanted
        }?.rawValue ?? UInt16(wanted.replacingOccurrences(of: "0x", with: ""), radix: 16)
        guard let raw else {
            print(L10n.t("未知输入源。这台显示器支持：", "Unknown input. This monitor supports: ")
                  + (capabilities?.inputSources.map { InputEngine.label(forRawValue: UInt16($0)) }
                     .joined(separator: ", ") ?? "—"))
            exit(1)
        }
        print(InputEngine.select(rawValue: raw, for: display)
              ? L10n.t("输入源 → \(InputEngine.label(forRawValue: raw))",
                       "Input → \(InputEngine.label(forRawValue: raw))")
              : L10n.t("切换失败（需要 DDC）", "Failed (requires DDC)"))
    } else {
        let raw = InputEngine.currentRawValue(for: display)
        print(L10n.t("当前输入源：", "Current input: ")
              + (raw.map { InputEngine.label(forRawValue: $0) } ?? "—"))
        if let listed = capabilities?.inputSources, !listed.isEmpty {
            print(L10n.t("显示器支持：", "Monitor supports: ")
                  + listed.map { InputEngine.label(forRawValue: UInt16($0)) }.joined(separator: ", "))
        }
    }

case "rotate-probe":
    // Ask the framebuffer to rotate to the angle it is already at: a no-op the
    // driver either accepts or rejects, so the transport can be verified
    // without actually turning anyone's screen sideways.
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    // Ask the same path the app uses. This used to probe the retired IOKit
    // transform, which refuses on every display here and reported that refusal
    // as if it were the display's answer.
    let accepted = RotationEngine.isSupported(for: display)
    print(L10n.t("旋转通道 \(accepted ? "可用（驱动接受了请求）" : "不可用（驱动拒绝）")  当前 \(display.rotation.label)",
                 "Rotation channel \(accepted ? "available (driver accepted)" : "unavailable (driver refused)")  now \(display.rotation.label)"))

case "rotate":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    guard arguments.count > 2, let degrees = Int(arguments[2]),
          let rotation = Rotation(rawValue: degrees) else {
        print(L10n.t("用法: pwelumenctl rotate <屏> <0|90|180|270>",
                     "Usage: pwelumenctl rotate <disp> <0|90|180|270>"))
        exit(1)
    }
    let previous = display.rotation
    print(L10n.t("旋转 \(display.name) → \(rotation.label) …",
                 "Rotating \(display.name) → \(rotation.label) …"))
    if RotationEngine.rotate(display, to: rotation) {
        print(L10n.t("成功。15 秒内按 Enter 保留，否则回滚到 \(previous.label)。",
                     "Done. Press Enter within 15s to keep, otherwise it reverts to \(previous.label)."))
        let deadline = Date().addingTimeInterval(15)
        var keep = false
        DispatchQueue(label: "stdin").async { _ = readLine(); keep = true }
        while Date() < deadline && !keep { usleep(100_000) }
        if keep {
            DisplaySettingsStore.shared.update(display.persistentKey) { $0.rotation = rotation.rawValue }
            print(L10n.t("已保留。", "Kept."))
        } else {
            print(L10n.t("超时，回滚。", "Timed out, reverting."))
            _ = RotationEngine.rotate(display, to: previous)
        }
    } else {
        print(L10n.t("失败：这块屏不接受旋转请求。",
                     "Failed: this display refuses rotation requests."))
    }

case "power":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    let modes: [String: PowerEngine.PowerMode] = ["on": .on, "off": .off, "standby": .standby]
    guard arguments.count > 2, let mode = modes[arguments[2]] else {
        print(L10n.t("用法: pwelumenctl power <屏> on|off|standby",
                     "Usage: pwelumenctl power <disp> on|off|standby"))
        exit(1)
    }
    print(PowerEngine.setDDCPower(mode, display: display)
          ? L10n.t("已发送 DDC 电源指令", "DDC power command sent")
          : L10n.t("失败（需要外接屏且支持 DDC）", "Failed (needs an external display with DDC)"))

case "off":
    // Turns one display off by whichever route it supports, and remembers the
    // route so `on` can undo exactly that.
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    let outcome = PowerEngine.sleepDisplay(display)
    if case .slept(let method) = outcome {
        PowerEngine.sleepStates[display.persistentKey] = method
        var stored = Defaults.shared.dictionary(forKey: "cliSleepStates") as? [String: String] ?? [:]
        stored[display.persistentKey] = method.rawValue
        Defaults.shared.set(stored, forKey: "cliSleepStates")
    }
    print(outcome.message)

case "on":
    let all = displays()
    let token = arguments.count > 1 ? arguments[1] : nil
    var stored = Defaults.shared.dictionary(forKey: "cliSleepStates") as? [String: String] ?? [:]
    // A display taken off the desktop is no longer in the online list, so it
    // has to be woken by the identity recorded when it was switched off.
    if let token, let display = all.first(where: { $0.name.localizedCaseInsensitiveContains(token) || String($0.id) == token }) {
        let method = stored[display.persistentKey].flatMap { PowerEngine.SleepMethod(rawValue: $0) } ?? .softDisconnect
        print(PowerEngine.wakeDisplay(display, method: method)
              ? L10n.t("已重新点亮", "Turned back on") : L10n.t("唤醒失败", "Could not turn it back on"))
        stored.removeValue(forKey: display.persistentKey)
    } else {
        // Nothing matched online: re-enable every display we switched off.
        var enabled = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(32, &ids, &count)
        for key in stored.keys {
            for candidate in DisplayRegistry.shared.onlineDisplays() where candidate.persistentKey == key {
                _ = PowerEngine.wakeDisplay(candidate, method: .softDisconnect)
                enabled += 1
            }
        }
        // Soft-disconnected displays are invisible, so ask CoreGraphics to
        // re-enable by ID across the full hardware list.
        if enabled == 0 {
            for id in 1 ... 8 {
                var config: CGDisplayConfigRef?
                guard CGBeginDisplayConfiguration(&config) == .success, let config else { continue }
                if let fn = Dyn.symbol("CGSConfigureDisplayEnabled",
                                       as: (@convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> CGError).self) {
                    _ = fn(config, CGDirectDisplayID(id), true)
                }
                _ = CGCompleteDisplayConfiguration(config, .permanently)
            }
            print(L10n.t("已尝试重新点亮所有被关闭的屏", "Attempted to turn every switched-off display back on"))
        } else {
            print(L10n.t("已重新点亮 \(enabled) 块屏", "Turned \(enabled) display(s) back on"))
        }
        stored.removeAll()
    }
    Defaults.shared.set(stored, forKey: "cliSleepStates")

case "disconnect", "connect":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    print(PowerEngine.setEnabled(arguments[0] == "connect", display: display).message)

case "main":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    print(PowerEngine.setAsMain(display)
          ? L10n.t("\(display.name) 已设为主屏", "\(display.name) is now the main display")
          : L10n.t("设置失败", "Failed"))

case "license":
    let store = LicenseStore.shared
    switch arguments.count > 1 ? arguments[1] : "show" {
    case "activate":
        guard arguments.count > 3 else {
            print(L10n.t("用法: pwelumenctl license activate <邮箱> <密钥>",
                         "Usage: pwelumenctl license activate <email> <key>")); exit(1)
        }
        print(store.activate(email: arguments[2], key: arguments[3]).message)
    case "deactivate":
        store.deactivate()
        print(L10n.t("已取消激活", "Deactivated"))
    default:
        print(L10n.t("Pro 状态：\(store.isPro ? "已解锁" : "未解锁")",
                     "Pro: \(store.isPro ? "unlocked" : "locked")"))
        if let email = store.licensedEmail { print("  \(email)") }
        for feature in LicenseStore.ProFeature.allCases {
            print("  \(feature.title): \(store.isUnlocked(feature) ? "✓" : "🔒")")
        }
    }

case "hidpi":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    guard let plan = HiDPIOverride.plan(for: display) else {
        print(L10n.t("无法生成覆盖文件", "Could not build an override")); exit(1)
    }
    switch arguments.count > 2 ? arguments[2] : "show" {
    case "install":
        print(L10n.t("将写入 \(plan.installPath)，需要管理员密码，重启后生效。",
                     "Writing \(plan.installPath) — needs an admin password, effective after a restart."))
        switch HiDPIOverride.install(plan) {
        case .installed: print(L10n.t("已写入", "Written"))
        case .cancelled: print(L10n.t("已取消", "Cancelled"))
        case .failed(let reason): print(L10n.t("失败：\(reason)", "Failed: \(reason)"))
        }
    case "remove":
        switch HiDPIOverride.remove(plan) {
        case .installed: print(L10n.t("已移除", "Removed"))
        case .cancelled: print(L10n.t("已取消", "Cancelled"))
        case .failed(let reason): print(L10n.t("失败：\(reason)", "Failed: \(reason)"))
        }
    default:
        print(L10n.t("目标：\(plan.displayName)", "Target: \(plan.displayName)"))
        print(L10n.t("路径：\(plan.installPath)", "Path: \(plan.installPath)"))
        print(L10n.t("已安装：\(HiDPIOverride.isInstalled(for: display) ? "是" : "否")",
                     "Installed: \(HiDPIOverride.isInstalled(for: display) ? "yes" : "no")"))
        print(L10n.t("将加入的 HiDPI 档位：", "HiDPI sizes it would add:"))
        for size in plan.logicalSizes {
            print("  \(Int(size.width)) × \(Int(size.height))"
                  + "   (\(Int(size.width) * 2) × \(Int(size.height) * 2) " + L10n.t("像素", "pixels") + ")")
        }
        print("")
        print(String(decoding: plan.plist, as: UTF8.self))
    }

case "edid":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    guard let block = DetailsEngine.rawEDID(for: display) else {
        print(L10n.t("这块屏没有提供 EDID", "This display exposes no EDID")); exit(1)
    }
    if arguments.count > 2 {
        let url = URL(fileURLWithPath: (arguments[2] as NSString).expandingTildeInPath)
        try? block.write(to: url)
        print(L10n.t("已写入 \(url.path)（\(block.count) 字节）",
                     "Wrote \(url.path) (\(block.count) bytes)"))
    } else if let summary = EDIDSummary(block: block) {
        print("\(summary.manufacturer) \(summary.modelName ?? "") "
              + "· 0x\(String(format: "%04x", summary.productCode)) "
              + "· \(summary.year)/\(summary.week) · EDID \(summary.version) "
              + "· \(block.count) bytes")
        print(block.map { String(format: "%02x", $0) }
            .enumerated()
            .reduce(into: [String]()) { rows, item in
                if item.offset % 16 == 0 { rows.append("") }
                rows[rows.count - 1] += item.element + " "
            }.joined(separator: "\n"))
    }

case "caps":
    // Raw capabilities string, straight from the monitor.
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    guard let service = DDCRegistry.shared.service(for: display) else {
        print(L10n.t("这块屏没有 DDC 通道", "No DDC channel for this display")); exit(1)
    }
    if let caps = service.capabilities() {
        print(caps)
    } else {
        print(L10n.t("显示器没有返回 capabilities", "The monitor returned no capabilities string"))
    }

case "vcp":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    guard let service = DDCRegistry.shared.service(for: display), arguments.count > 2,
          let code = UInt8(arguments[2].replacingOccurrences(of: "0x", with: ""), radix: 16) else {
        print(L10n.t("用法: pwelumenctl vcp <屏> <十六进制码>", "Usage: pwelumenctl vcp <disp> <hex code>")); exit(1)
    }
    guard let vcp = VCP(rawValue: code) else {
        print(L10n.t("不在已知 VCP 列表中", "Not a VCP code PWE Lumen Bar knows")); exit(1)
    }
    if let reading = service.read(vcp) {
        print(String(format: "VCP 0x%02X: current=%d max=%d (%.0f%%)",
                     code, reading.current, reading.maximum, reading.percent * 100))
    } else {
        print(L10n.t("读取失败（显示器可能不支持这个功能）",
                     "Read failed — the monitor may not support this feature"))
    }

case "name":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    if arguments.count > 2 {
        let wanted = arguments[2]
        DisplayNameStore.shared.setName(wanted == "-" ? nil : wanted,
                                        forKey: display.persistentKey)
        print(wanted == "-"
              ? L10n.t("已恢复系统名称", "System name restored")
              : L10n.t("已重命名为「\(wanted)」", "Renamed to \u{201C}\(wanted)\u{201D}"))
    } else {
        print("\(display.name)  [\(display.persistentKey)]")
        if let override = DisplayNameStore.shared.name(forKey: display.persistentKey) {
            print(L10n.t("自定义名称：\(override)（用 - 恢复系统名称）",
                         "Custom name: \(override) (pass - to restore the system name)"))
        }
    }

case "follow":
    // Ties an external display's brightness to the built-in panel's, which
    // macOS keeps adjusted from the ambient light sensor.
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    guard !display.isBuiltin else {
        fail(L10n.t("内建屏就是被跟随的那一块", "The built-in panel is the one being followed"))
    }
    switch arguments.count > 2 ? arguments[2] : "show" {
    case "on":
        let builtIn = displays().first(where: \.isBuiltin)
        let reference = builtIn.flatMap { BrightnessEngine.shared.brightness(of: $0) } ?? 1
        let mine = BrightnessEngine.shared.brightness(of: display) ?? 1
        DisplaySettingsStore.shared.writeAlways(display.persistentKey) {
            $0.followsBuiltIn = true
            $0.followRatio = reference > 0.01 ? mine / reference : 1
        }
        print(L10n.t("\(display.name) 将按当前比例跟随内建屏",
                     "\(display.name) will follow the built-in display at the current ratio"))
    case "off":
        DisplaySettingsStore.shared.writeAlways(display.persistentKey) { $0.followsBuiltIn = false }
        print(L10n.t("已关闭跟随", "Following off"))
    default:
        let preferences = DisplaySettingsStore.shared.preferences(for: display.persistentKey)
        let on = preferences?.followsBuiltIn == true
        print(L10n.t("\(display.name)：\(on ? "跟随中" : "未跟随")",
                     "\(display.name): \(on ? "following" : "not following")")
              + (on ? String(format: "  ratio %.2f", preferences?.followRatio ?? 1) : ""))
    }

case "protect":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    switch arguments.count > 2 ? arguments[2] : "show" {
    case "on":
        DisplaySettingsStore.shared.setProtected(true, for: display)
        print(L10n.t("已锁定 \(display.name) 的分辨率和方向", "Locked \(display.name)'s resolution and orientation"))
    case "off":
        DisplaySettingsStore.shared.setProtected(false, for: display)
        print(L10n.t("已解锁", "Unlocked"))
    default:
        print(L10n.t("\(display.name)：\(DisplaySettingsStore.shared.isProtected(display.persistentKey) ? "已锁定" : "未锁定")",
                     "\(display.name): \(DisplaySettingsStore.shared.isProtected(display.persistentKey) ? "locked" : "unlocked")"))
    }

case "log":
    // The app writes here too, so this is the same view of both processes.
    let count = arguments.count > 1 ? (Int(arguments[1]) ?? 40) : 40
    guard let contents = try? String(contentsOf: Log.fileURL, encoding: .utf8) else {
        print(L10n.t("还没有日志：\(Log.fileURL.path)", "No log yet: \(Log.fileURL.path)")); exit(0)
    }
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
    print(lines.suffix(count).joined(separator: "\n"))
    print("— \(Log.fileURL.path)")

case "details":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    print(DetailsEngine.details(for: display).plainText())

case "preset":
    let store = PresetStore.shared
    switch arguments.count > 1 ? arguments[1] : "list" {
    case "save":
        guard arguments.count > 2 else {
            print(L10n.t("用法: pwelumenctl preset save <名称>", "Usage: pwelumenctl preset save <name>"))
            exit(1)
        }
        let preset = store.capture(name: arguments[2])
        print(L10n.t("已保存场景「\(preset.name)」，含 \(preset.displays.count) 块屏",
                     "Saved preset \u{201C}\(preset.name)\u{201D} with \(preset.displays.count) display(s)"))
    case "apply":
        guard arguments.count > 2, let preset = store.preset(named: arguments[2]) else {
            print(L10n.t("找不到这个场景", "No preset by that name")); exit(1)
        }
        let applied = store.apply(preset)
        print(L10n.t("已应用到 \(applied.count) 块屏：\(applied.joined(separator: ", "))",
                     "Applied to \(applied.count) display(s): \(applied.joined(separator: ", "))"))
    case "delete":
        guard arguments.count > 2, let preset = store.preset(named: arguments[2]) else {
            print(L10n.t("找不到这个场景", "No preset by that name")); exit(1)
        }
        store.delete(preset.id)
        print(L10n.t("已删除", "Deleted"))
    default:
        let presets = store.presets
        print(L10n.t("共 \(presets.count) 个场景", "\(presets.count) preset(s)"))
        for preset in presets {
            print("  \(preset.name)  —  " + L10n.t("\(preset.displays.count) 块屏", "\(preset.displays.count) display(s)"))
            for snapshot in preset.displays {
                print("      \(snapshot.displayName): "
                      + L10n.t("亮度 ", "brightness ") + percent(snapshot.brightness)
                      + "  " + L10n.t("模式 ", "mode ") + (snapshot.modeID ?? "—")
                      + "  " + L10n.t("位置 ", "origin ")
                      + "(\(Int(snapshot.originX ?? 0)), \(Int(snapshot.originY ?? 0)))")
            }
        }
    }

case "color":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    let profiles = ColorEngine.installedDisplayProfiles()
    if arguments.count > 2 {
        let query = arguments[2].lowercased()
        guard let profile = profiles.first(where: { $0.name.lowercased().contains(query) }) else {
            print(L10n.t("没有匹配的配置文件", "No matching profile"))
            exit(1)
        }
        print(ColorEngine.apply(profile, to: display.id)
              ? L10n.t("已应用：\(profile.name)", "Applied: \(profile.name)")
              : L10n.t("应用失败", "Failed to apply"))
    } else {
        print(L10n.t("当前：", "Current: ")
              + (ColorEngine.currentProfileName(for: display.id) ?? "—"))
        print(L10n.t("已安装的显示器配置文件（\(profiles.count)）：",
                     "Installed display profiles (\(profiles.count)):"))
        for profile in profiles { print("  \(profile.name)") }
    }

case "arrange":
    // `tile` takes no further arguments; only the edge form needs three.
    guard arguments.count > 1, arguments[1] == "tile" || arguments.count > 2 else {
        print(L10n.t("用法: pwelumenctl arrange <屏> left|right|above|below [参照屏]   或   pwelumenctl arrange tile",
                     "Usage: pwelumenctl arrange <disp> left|right|above|below [anchor]   or   pwelumenctl arrange tile"))
        exit(1)
    }
    if arguments[1] == "tile" {
        print(ArrangementEngine.tileHorizontally(displays())
              ? L10n.t("已水平排列", "Tiled horizontally")
              : L10n.t("排列失败", "Failed"))
    } else {
        let display = requireDisplay(arguments[1])
        guard let edge = ArrangementEdge(rawValue: arguments[2]) else {
            print(L10n.t("方向只能是 left|right|above|below",
                         "Edge must be left|right|above|below"))
            exit(1)
        }
        let anchor = arguments.count > 3
            ? requireDisplay(arguments[3])
            : (displays().first(where: \.isMain) ?? display)
        print(ArrangementEngine.place(display, edge, relativeTo: anchor)
              ? L10n.t("\(display.name) 已放到 \(anchor.name) 的\(edge.label)",
                       "\(display.name) placed to the \(edge.label.lowercased()) of \(anchor.name)")
              : L10n.t("排列失败", "Failed"))
    }

case "capture":
    let display = requireDisplay(arguments.count > 1 ? arguments[1] : nil)
    guard CaptureEngine.hasPermission else {
        print(L10n.t("需要「屏幕录制」权限：系统设置 → 隐私与安全性 → 屏幕录制，勾选调用它的程序。",
                     "Screen Recording permission required: System Settings → Privacy & Security → Screen Recording."))
        CaptureEngine.requestPermission()
        exit(1)
    }
    // A CLI has no run loop, so drive the async capture to completion here.
    let semaphore = DispatchSemaphore(value: 0)
    var outcome = ""
    Task {
        do {
            let image = try await CaptureEngine.capture(display)
            let directory = arguments.count > 2
                ? URL(fileURLWithPath: (arguments[2] as NSString).expandingTildeInPath)
                : nil
            let url = try CaptureEngine.save(image, display: display, to: directory)
            outcome = L10n.t("已保存：\(url.path)", "Saved: \(url.path)")
        } catch {
            outcome = error.localizedDescription
        }
        semaphore.signal()
    }
    semaphore.wait()
    print(outcome)

case "remember":
    let store = DisplaySettingsStore.shared
    switch arguments.count > 1 ? arguments[1] : "show" {
    case "on":
        store.isEnabled = true
        for display in displays() {
            store.update(display.persistentKey) { preferences in
                preferences.brightness = BrightnessEngine.shared.brightness(of: display)
                preferences.volume = AudioEngine.shared.volume(of: display)
                preferences.modeID = display.currentMode?.id
                preferences.rotation = display.rotation.rawValue
            }
        }
        print(L10n.t("已开启，并记下了当前 \(displays().count) 块屏的设置",
                     "Enabled, and recorded the current settings of \(displays().count) display(s)"))
    case "off":
        store.isEnabled = false
        print(L10n.t("已关闭（已记住的设置仍保留）", "Disabled (saved settings are kept)"))
    case "clear":
        store.forgetAll()
        print(L10n.t("已清空", "Cleared"))
    default:
        print(L10n.t("状态：\(store.isEnabled ? "开启" : "关闭")   已记住 \(store.rememberedCount) 块屏",
                     "State: \(store.isEnabled ? "on" : "off")   remembered displays: \(store.rememberedCount)"))
        for display in displays() {
            guard let preferences = store.preferences(for: display.persistentKey) else { continue }
            print("  \(display.name) [\(display.persistentKey)]")
            print("    " + L10n.t("亮度 ", "brightness ") + percent(preferences.brightness)
                  + L10n.t("  音量 ", "  volume ") + percent(preferences.volume)
                  + "  " + L10n.t("模式 ", "mode ") + (preferences.modeID ?? "—")
                  + "  " + L10n.t("方向 ", "rotation ") + (preferences.rotation.map { "\($0)°" } ?? "—"))
        }
    }

case "audio":
    let audio = AudioEngine.shared
    let devices = audio.outputDevices()
    let current = audio.defaultOutputDevice(in: devices)
    for device in devices {
        let transport = withUnsafeBytes(of: device.transport.bigEndian) {
            String(bytes: $0, encoding: .ascii) ?? "????"
        }
        let marker = device.id == current?.id ? "  <- " + L10n.t("当前输出", "current output") : ""
        print("[\(device.id)] \(device.name)  transport=\(transport)  "
              + "\(device.kindLabel)  \(percent(audio.volume(of: device)))\(marker)")
    }
    print("")
    // Which display, if any, owns the sound right now — the single fact that
    // decides whether the volume keys are PWE Lumen Bar's to take.
    if let owner = audio.displayOwningOutput(among: displays()) {
        print(L10n.t("音量键：接管（当前输出是 \(owner.display.name) 的扬声器）",
                     "Volume keys: taken over (the current output is \(owner.display.name)'s speakers)"))
    } else if let current {
        print(L10n.t("音量键：交还 macOS（当前输出是 \(current.name)，\(current.kindLabel)）",
                     "Volume keys: handed back to macOS (current output is \(current.name), \(current.kindLabel))"))
    } else {
        print(L10n.t("音量键：交还 macOS（没有可识别的输出设备）",
                     "Volume keys: handed back to macOS (no output device could be identified)"))
    }

case "compat":
    // The one command to run on a macOS release this code has never been
    // executed on: it answers "does the private surface PWE Lumen Bar depends on still
    // exist here" without changing a single setting.
    var failures = 0
    for check in Platform.compatibilityReport() {
        if !check.ok { failures += 1 }
        let name = check.name.padding(toLength: max(40, check.name.count + 2), withPad: " ", startingAt: 0)
        print("\(check.ok ? "✅" : "❌")  \(name)\(check.detail)")
    }
    print("")
    if failures == 0 {
        print(L10n.t("全部通过 —— 这台机器上 PWE Lumen Bar 的所有通道都可用。",
                     "All clear — every channel PWE Lumen Bar depends on is available on this machine."))
    } else {
        print(L10n.t("\(failures) 项不可用。对应功能会自动降级，不会崩溃；把这份输出贴进 issue 即可。",
                     "\(failures) unavailable. The matching features degrade rather than crash — paste this output into an issue."))
    }

case "sleep":
    PowerEngine.sleepAllDisplays()
    print(L10n.t("已让显示器休眠", "Displays put to sleep"))

case nil, "help", "--help", "-h":
    usage()

default:
    print(L10n.t("未知命令：\(arguments[0])", "Unknown command: \(arguments[0])"))
    print("")
    usage()
    exit(1)
}
