#!/usr/bin/env python3
"""Generate the English twins of the Chinese documentation figures.

    ./scripts/docs-en-figures.py

The figures are hand-drawn SVG mockups of the interface, and they were only ever
drawn in Chinese. A page that serves both languages cannot show a Chinese
diagram to an English reader, so each one gets an `-en.svg` twin built from the
same file with the strings swapped.

Why a script rather than two hand-kept files: the drawing is the part that takes
work, and keeping two copies of it in sync by hand is how one of them ends up a
version behind. Here the Chinese file stays the single source of the geometry,
and this script is the only thing that has to know about English.

It fails loudly when a string it expects is no longer in the source — that is
the point. A silently skipped translation would ship a half-Chinese English
diagram.

Where a label also exists in the app, the English here is the app's own string
(`L10n.t(chinese, english)`), so the diagram and the interface never disagree.

One rule when editing the maps: an English line has to fit the box the Chinese
line was laid out in. A CJK glyph is about twice the width of a Latin one at the
same size, so roughly two Latin characters per Chinese character is the budget.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
IMAGES = ROOT / "docs" / "images"

# Labels the interface itself uses, so the mockups cannot drift from the app.
UI = {
    "全部": "All",
    "系统": "System",
    "主屏": "Main",
    "外接": "External",
    "截图": "Capture",
    "熄屏": "Turn off",
    "统一亮度": "Match all",
    "对比度": "Contrast",
    "色温": "Warmth",
    "分辨率": "Resolution",
    "方向": "Orientation",
    "标准": "Standard",
    "软件": "Software",
    "设为主屏": "Make main",
    "全部休眠": "Sleep all",
    "联动": "Link",
    "2 块屏幕": "2 displays",
    "解锁": "Unlock",
    "取消": "Cancel",
    "继续": "Continue",
    "工作": "Work",
    "夜间": "Evening",
    "客厅电视": "Living room TV",
    "退出 PWE Lumen Bar": "Quit PWE Lumen Bar",
}

# `hidpi-explained.svg` is deliberately absent: it was drawn bilingual from the
# start, with the English under each Chinese line, and both pages use it as-is.
FIGURES = {
    "guide-welcome.svg": {
        "第一次运行：欢迎窗口": "First run: the welcome window",
        "只出现一次，之后可从 ⋯ 菜单的「使用提示…」再打开":
            "Shown once; the ⋯ menu's “Tips…” brings it back",
        "欢迎使用 PWE Lumen Bar": "Welcome to PWE Lumen Bar",
        "PWE Lumen Bar 已在菜单栏里": "PWE Lumen Bar is in your menu bar",
        "每块屏单独控制亮度、音量、分辨率和方向。":
            "Per-display brightness, volume, resolution and orientation.",
        "三个不太看得出来的用法": "Three things that are not obvious",
        "在菜单栏图标上滚轮": "Scroll on the menu bar icon",
        "直接调节光标所在那块屏的亮度，不用打开面板。":
            "Changes the brightness of whichever display the pointer is on.",
        "右键图标": "Right-click the icon",
        "直接切换已保存的场景。": "Jumps straight to a saved preset.",
        "面板里的 ⋯ 菜单": "The ⋯ menu on each card",
        "重命名、颜色配置、输入源、截图、锁定配置都在那里。":
            "Renaming, colour profiles, input source, screenshots and locking live there.",
        "两个需要授权的功能，默认关闭": "Two features are off until you ask for them",
        "接管键盘亮度/音量键": "Take over the brightness and volume keys",
        "让 F1/F2 作用于外接屏。需要「辅助功能」权限。":
            "Makes F1/F2 work on an external display. Needs Accessibility permission.",
        "按屏截图": "Per-display screenshots",
        "第一次使用时会请求「屏幕录制」权限。":
            "Asks for Screen Recording permission the first time you use it.",
        "打开设置": "Open Settings",
        "开始使用": "Get started",
        "接管这些按键": "Take these keys over",
        "亮度键作用于光标所在的那块屏；光标在内建屏上时交还":
            "The brightness keys act on the display under the pointer; on the",
        "macOS。需要「辅助功能」权限。":
            "built-in one they go back to macOS. Needs Accessibility.",
        "需要「辅助功能」权限才能接管亮度/音量键。已打开":
            "Taking the brightness and volume keys over needs Accessibility.",
        "系统设置，勾选 PWE Lumen Bar 后再试一次。":
            "System Settings is open — tick PWE Lumen Bar, then try again.",
    },
    "guide-actions-menu.svg": {
        "两个 ⋯ 菜单": "The two ⋯ menus",
        "卡片上的 ⋯ 只管这一块屏；面板底部的 ⋯ 管全局":
            "A card's ⋯ is that display only; the panel's ⋯ is global",
        "卡片右上角的 ⋯": "The ⋯ at the top of a card",
        "面板底部的 ⋯": "The ⋯ at the bottom of the panel",
        "镜像到主屏": "Mirror to main display",
        "颜色配置文件": "Colour profile",
        "位置": "Position",
        "给显示器断电（可能需要物理电源键唤醒）":
            "Cut monitor power (may need its physical button to return)",
        "仅从桌面移除（显示器仍通电）": "Remove from the desktop only (monitor stays powered)",
        "跟随内建屏亮度": "Follow the built-in display's brightness",
        "输入源": "Input source",
        "DDC 通道": "DDC channel",
        "重命名…": "Rename…",
        "锁定分辨率和方向": "Lock resolution and orientation",
        "强制开启 HiDPI…（Pro）": "Force HiDPI on… (Pro)",
        "显示器详情…": "Display details…",
        "诊断": "Diagnostics",
        "亮度：DDC": "Brightness: DDC",
        "音量：音频设备": "Volume: audio device",
        "连接：外接 (transport 8)": "Connection: external (transport 8)",
        "DDC：已连接": "DDC: connected",
        "模式：24 个，其中 HiDPI 9 个": "Modes: 24, of which 9 HiDPI",
        "场景": "Presets",
        "重新检测显示器": "Re-detect displays",
        "截取所有屏幕": "Capture every display",
        "水平排列所有屏幕": "Tile displays horizontally",
        "语言": "Language",
        "记住每块屏的设置": "Remember each display's settings",
        "接外接屏时收起内建屏": "Put the built-in panel away when an external connects",
        "全局快捷键": "Global shortcuts",
        "开机时启动": "Launch at login",
        "使用提示…": "Tips…",
        "设置…": "Settings…",
        "删除": "Delete",
        "把当前状态存为场景…": "Save current state as a preset…",
    },
    "guide-settings.svg": {
        "设置窗口": "The Settings window",
        "⋯ 菜单 › 设置… ，或欢迎窗口里的「打开设置」":
            "⋯ menu › Settings…, or “Open Settings” in the welcome window",
        "PWE Lumen Bar 设置": "PWE Lumen Bar Settings",
        "已解锁": "Unlocked",
        "在这台 Mac 上取消激活": "Deactivate on this Mac",
        "通用": "General",
        "语言": "Language",
        "跟随系统": "System",
        "开机时启动": "Launch at login",
        "显示器信息": "Display information",
        "内建 Retina 显示器": "Built-in Retina Display",
        "刷新": "Refresh",
        "显示器": "Displays",
        "记住每块屏的设置": "Remember each display's settings",
        "重新插拔后自动恢复亮度、色温、分辨率和方向。":
            "Brightness, warmth, resolution and orientation survive a reconnect.",
        "接外接屏时收起内建屏": "Put the built-in panel away when an external connects",
        "键盘亮度/音量键": "The keyboard's brightness and volume keys",
        "接管这些按键": "Take these keys over",
        "全局快捷键": "Global shortcuts",
        "启用": "Enabled",
        "快捷键作用于光标所在的那块屏。":
            "Shortcuts act on whichever display the pointer is on.",
        "调亮": "Brighter",
        "调暗": "Dimmer",
        "音量加": "Volume up",
        "音量减": "Volume down",
        "静音开关": "Toggle mute",
        "截图这块屏": "Capture this display",
        "关闭/唤醒这块屏": "Turn this display off / on",
        "恢复默认快捷键": "Reset shortcuts to defaults",
        "系统": "System",
        "运行环境": "Running on",
        "接口自检": "Interface self-check",
        "全部可用（16 项）": "All available (16 checks)",
        "录制新组合键时": "While recording a new combination",
        "按下组合键…": "Press keys…",
        "这个组合被别的程序占用了，换一个。":
            "Another app already owns that combination — pick a different one.",
    },
    "guide-menubar.svg": {
        "菜单栏图标：三种操作": "The menu bar icon: three gestures",
        "PWE Lumen Bar 不进 Dock，只有菜单栏这一个入口":
            "No Dock icon — the menu bar is the whole entrance",
        "Finder　文件　编辑　显示　窗口　帮助": "Finder　File　Edit　View　Window　Help",
        "左键": "Click",
        "滚轮": "Scroll",
        "右键": "Right-click",
    },
    "guide-menu.svg": {
        "菜单面板：一块屏一张卡片": "The panel: one card per display",
        "面板宽度固定，屏幕多了就在列表里滚动":
            "Fixed width; more displays simply scroll",
        "已把 2 块屏对齐到 27B1U3900 的 60%":
            "Matched 2 displays to the 27B1U3900's 60%",
        "同一张卡片，遇到能力不足的屏幕": "The same card, on a display that cannot do as much",
        "软件调光：背光不变，只是画面变暗":
            "Software dimming — the backlight is untouched",
        "这块屏拒绝了旋转请求": "This display refuses rotation requests",
    },
    "guide-pro.svg": {
        "PWE Lumen Bar Pro：强制开启 HiDPI": "PWE Lumen Bar Pro: forcing HiDPI on",
        "设置 › PWE Lumen Bar Pro，以及卡片 ⋯ 菜单里的那一项":
            "Settings › PWE Lumen Bar Pro, and the item in a card's ⋯ menu",
        "LUMEN PRO（未解锁时）": "LUMEN PRO (before unlocking)",
        "亮度、音量、分辨率、旋转、场景、快捷键、截图 —— 日常要用的全部免":
            "Brightness, volume, resolution, rotation, presets, shortcuts,",
        "费，没有试用期，也不会到期。":
            "screenshots — everything you reach for daily is free.",
        "Pro 只解决一件事，也是最难的一件：": "Pro solves one thing — the hard one:",
        "让外接屏的文字和内建屏一样锐利":
            "Make an external display's text as sharp as the built-in one",
        "你的显示器像素足够多，缺的只是 macOS 愿意用 2 倍渲染的那几档模式。":
            "Your monitor has the pixels. What it lacks are the modes macOS will render at 2× into.",
        "PWE Lumen Bar 把它们补进系统，重启后就多出「看起来像 2560×1440」这样的选":
            "PWE Lumen Bar writes them into the system, and after a restart you get options like",
        "项 —— 和 Retina 屏同一种渲染方式，而不是被拉伸过的近似值。":
            "“looks like 2560×1440” — rendered the way a Retina screen is, not stretched.",
        "需要管理员密码，重启后生效，随时可以移除。内建屏和 Apple 显示器本":
            "Needs an administrator password, takes effect after a restart, and can be",
        "来就有这些模式，用不上。":
            "removed at any time. Built-in and Apple displays already have these modes.",
        "为什么 Mac 接上显示器字会发虚？": "Why does text go blurry when a Mac drives a monitor?",
        "购买时使用的邮箱": "The email you bought with",
        "许可证密钥": "Licence key",
        "点「强制开启 HiDPI…」之后": "After choosing “Force HiDPI on…”",
        "为 Philips 27B1U3900 强制开启 HiDPI？": "Force HiDPI on for the Philips 27B1U3900?",
        "将写入系统显示器覆盖文件，加入这些 HiDPI 档位：":
            "This writes a system display override adding these HiDPI modes:",
        "• 需要管理员密码（由 macOS 自己弹窗，PWE Lumen Bar 不接触密码）":
            "• Needs an administrator password — macOS asks for it, the app never sees it",
        "• 重启后才会生效": "• Takes effect after a restart",
        "• 写入位置：": "• Written to:",
        "• 之后可以在同一个菜单里移除": "• Removable from the same menu afterwards",
        "重启之后，分辨率菜单里多出来的档位":
            "After the restart, the modes the resolution menu gains",
    },
}


# English is wider than the Chinese it replaces, and these figures are drawn with
# absolute coordinates — a pill sized for two characters cannot hold "External".
# These are the geometry edits that go with the translation, applied after it.
LAYOUT = {
    "guide-menu.svg": [
        # The two badges beside the display's name.
        ('<rect x="312" y="193" width="32" height="16" rx="8" fill="#D6E7FF"/>',
         '<rect x="312" y="193" width="52" height="16" rx="8" fill="#D6E7FF"/>'),
        ('<text x="328" y="204" text-anchor="middle" class="badge">External</text>',
         '<text x="338" y="204" text-anchor="middle" class="badge">External</text>'),
        # "Living room TV" is far wider than 客厅电视, so its badge moves too.
        ('<rect x="654" y="193" width="48" height="16" rx="8" fill="#D6E7FF"/>',
         '<rect x="700" y="193" width="48" height="16" rx="8" fill="#D6E7FF"/>'),
        ('<text x="678" y="204" text-anchor="middle" class="badge">AirPlay</text>',
         '<text x="724" y="204" text-anchor="middle" class="badge">AirPlay</text>'),
        ('<text x="809" y="253" class="ts">Make main</text>',
         '<text x="809" y="253" class="ts" style="font-size:9.5px">Make main</text>'),
        # Quick-action labels sit inside fixed-width buttons.
        ('<text x="149" y="253" class="ts">Capture</text>',
         '<text x="149" y="253" class="ts" style="font-size:9.5px">Capture</text>'),
        ('<text x="211" y="253" class="ts">Turn off</text>',
         '<text x="211" y="253" class="ts" style="font-size:9.5px">Turn off</text>'),
        ('<text x="275" y="253" class="ts">Match all</text>',
         '<text x="275" y="253" class="ts" style="font-size:9.5px">Match all</text>'),
        ('<text x="596" y="253" class="ts">Capture</text>',
         '<text x="596" y="253" class="ts" style="font-size:9.5px">Capture</text>'),
        ('<text x="658" y="253" class="ts">Turn off</text>',
         '<text x="658" y="253" class="ts" style="font-size:9.5px">Turn off</text>'),
        ('<text x="722" y="253" class="ts">Match all</text>',
         '<text x="722" y="253" class="ts" style="font-size:9.5px">Match all</text>'),
        # "Resolution" and "Orientation" do not fit beside their controls, and the
        # app itself wraps them onto two lines — so does the figure.
        ('<text x="126" y="410" class="ts">Resolution</text>',
         '<text x="126" y="406" class="ts" style="font-size:9.5px">Reso-</text>'
         '<text x="126" y="416" class="ts" style="font-size:9.5px">lution</text>'),
        ('<text x="126" y="443" class="ts">Orientation</text>',
         '<text x="126" y="439" class="ts" style="font-size:9.5px">Orien-</text>'
         '<text x="126" y="449" class="ts" style="font-size:9.5px">tation</text>'),
        ('<text x="573" y="364" class="ts">Resolution</text>',
         '<text x="573" y="360" class="ts" style="font-size:9.5px">Reso-</text>'
         '<text x="573" y="370" class="ts" style="font-size:9.5px">lution</text>'),
        ('<text x="573" y="395" class="ts">Orientation</text>',
         '<text x="573" y="391" class="ts" style="font-size:9.5px">Orien-</text>'
         '<text x="573" y="401" class="ts" style="font-size:9.5px">tation</text>'),
    ],
    "guide-settings.svg": [
        # A button sized for six Chinese characters.
        ('<rect x="606" y="354" width="120" height="20" rx="5" fill="#FFFFFF" stroke="#C7C7CC"/>',
         '<rect x="590" y="354" width="152" height="20" rx="5" fill="#FFFFFF" stroke="#C7C7CC"/>'),
        ('<text x="666" y="368" text-anchor="middle" class="ts" fill="#1D1D1F">Reset shortcuts to defaults</text>',
         '<text x="666" y="368" text-anchor="middle" class="ts" style="font-size:10px" fill="#1D1D1F">Reset shortcuts to defaults</text>'),
        ('<text x="944" y="481" text-anchor="end" class="ts">All available (16 checks)</text>',
         '<text x="944" y="481" text-anchor="end" class="ts" style="font-size:10px">All available (16 checks)</text>'),
    ],
}


def translate(name: str, mapping: dict) -> pathlib.Path:
    source = IMAGES / name
    text = source.read_text()

    # Longest first: a short label is often a substring of a longer sentence.
    for chinese in sorted({**UI, **mapping}, key=len, reverse=True):
        english = {**UI, **mapping}[chinese]
        if chinese in text:
            text = text.replace(chinese, english)

    for old, new in LAYOUT.get(name, []):
        if old not in text:
            sys.exit(f"{name}: layout patch no longer matches:\n  {old}")
        text = text.replace(old, new)

    missing = re.findall(r">([^<>]*[一-鿿][^<>]*)<", text)
    if missing:
        sys.exit(f"{name}: {len(missing)} string(s) have no English:\n  "
                 + "\n  ".join(repr(m) for m in missing))

    out = IMAGES / name.replace(".svg", "-en.svg")
    out.write_text(text)
    return out


for name, mapping in FIGURES.items():
    print(f"  {translate(name, mapping).name}")
