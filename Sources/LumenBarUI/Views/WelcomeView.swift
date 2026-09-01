import AppKit
import LumenBarCore
import SwiftUI

/// Shown once, the first time PWE Lumen Bar runs.
///
/// Two of the best things here are invisible: scrolling on the menu bar icon,
/// and the right-click menu. And two features stay switched off until asked
/// for, because they need a system permission. Without this window a new user
/// meets none of that — they see one panel and assume that is the whole app.
struct WelcomeView: View {
    let controller: DisplayController
    var onDismiss: () -> Void

    private static let seenKey = "hasSeenWelcome"

    static var shouldShow: Bool {
        !Defaults.shared.bool(forKey: seenKey)
    }

    static func markSeen() {
        Defaults.shared.set(true, forKey: seenKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("PWE Lumen Bar 已在菜单栏里", "PWE Lumen Bar is in your menu bar"))
                        .font(.title3.weight(.semibold))
                    Text(L10n.t("每块屏单独控制亮度、音量、分辨率和方向。",
                                "Per-display brightness, volume, resolution and orientation."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 18)

            Text(L10n.t("三个不太看得出来的用法", "Three things that are not obvious"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            tip("cursorarrow.click.2",
                L10n.t("在菜单栏图标上滚轮", "Scroll on the menu bar icon"),
                L10n.t("直接调节光标所在那块屏的亮度，不用打开面板。",
                       "Changes the brightness of whichever display the pointer is on, without opening anything."))
            tip("contextualmenu.and.cursorarrow",
                L10n.t("右键图标", "Right-click the icon"),
                L10n.t("直接切换已保存的场景。", "Jumps straight to a saved preset."))
            tip("slider.horizontal.3",
                L10n.t("面板里的 ⋯ 菜单", "The ⋯ menu on each card"),
                L10n.t("重命名、颜色配置、输入源、截图、锁定配置都在那里。",
                       "Renaming, colour profiles, input source, screenshots and config locking all live there."))

            Divider().padding(.vertical, 14)

            Text(L10n.t("两个需要授权的功能，默认关闭", "Two features are off until you ask for them"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            tip("keyboard",
                L10n.t("接管键盘亮度/音量键", "Take over the brightness and volume keys"),
                L10n.t("让 F1/F2 作用于外接屏。需要「辅助功能」权限。",
                       "Makes F1/F2 work on an external display. Needs Accessibility permission."))
            tip("camera",
                L10n.t("按屏截图", "Per-display screenshots"),
                L10n.t("第一次使用时会请求「屏幕录制」权限。",
                       "Asks for Screen Recording permission the first time you use it."))

            Spacer(minLength: 16)

            HStack {
                Button(L10n.t("打开设置", "Open Settings")) {
                    controller.openSettings()
                    finish()
                }
                Spacer()
                Button(L10n.t("开始使用", "Get started")) { finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460, height: 540)
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
    }

    private func finish() {
        Self.markSeen()
        onDismiss()
    }
}
