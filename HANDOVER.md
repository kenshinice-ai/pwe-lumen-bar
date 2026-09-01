# PWE Lumen Bar — 交接文档 / Handover

> 最后更新：2026-09-01 · 约 8600 行 Swift · 已安装于 `/Applications/PWE Lumen Bar.app`
> Last updated 1 Sep 2026 · ~8,600 lines of Swift · installed at `/Applications/PWE Lumen Bar.app`

---

## 一、这是什么 / What this is

macOS 菜单栏显示器控制器，**仅支持 Apple Silicon（M 系列）+ macOS 27**。Intel 路径已从代码中移除。

A macOS menu bar display controller. **Apple Silicon (M-series) on macOS 27 only** — the Intel code paths have been removed, not just disabled.

```bash
./scripts/build-app.sh                                   # → build/PWE Lumen Bar.app
cp -R build/PWE Lumen Bar.app /Applications/ && open /Applications/PWE Lumen Bar.app
.build/debug/pwelumenctl                                    # 命令行，与 app 共用引擎和设置
```

---

## 二、已在真机验证过的硬件 / Hardware actually tested

| 显示器 | 通道 | 结论 |
|---|---|---|
| MacBook Air M1 内建屏 | `DisplayServices` | 亮度、旋转、8 个模式（5 个 HiDPI） |
| Apple Studio Display 5K | `DisplayServices` | **完全不响应 DDC** —— Apple 屏用自有协议 |
| Philips 27B1U3900 4K | DDC/CI | 亮度 `0x10`、对比度 `0x12`、音量 `0x62`、capabilities `0xF3`、EDID 全部通过 |

两套协议并存的架构成立：能力按屏运行时探测，探不到就在界面上灰掉并说明原因。

Both protocol families coexist: capabilities are probed per display at run time, and anything unavailable is greyed out with the reason stated rather than silently doing nothing.

---

## 三、必须知道的 API 陷阱 / API traps you must know

这些是踩出来的，不是查文档查到的。改动相关代码前请先读。

Learned the hard way, not from documentation. Read before touching the related code.

1. **旋转必须用 SkyLight** — `SLSSetDisplayRotation(displayID, degrees)`，不带 connection id。
   IOKit 的 `IOServiceRequestProbe(kIOFBSetTransform)` 是 Intel 时代的路径，在 M1 上对**每一块屏**都返回 `kIOReturnUnsupported`，曾让我得出「内建屏不能旋转」的错误结论 —— **内建屏其实可以转**，macOS 只是把选项藏了。

2. **HiDPI 模式只在私有 CGS 表里** — 公开的 `CGDisplayCopyAllDisplayModes` 对内建屏只返回 3 个模式，连当前正在用的那个都不在里面。`kCGDisplayShowDuplicateLowResolutionModes` 在这版系统上**完全无效**。结构体偏移见 `CGSModeTable.swift`，偏移 184 处是自述长度 212，可作版本护栏。

3. **EDID 走 I2C `0x50`**，不是 DDC 的 `0x37`。Apple Silicon 的 IORegistry 里根本没有 EDID 块。

4. **`kCGDisplaySupportsRotation` 会虚报 `true`**；**`CGVirtualDisplayCreate` 不存在**。

5. **`.clear` 混合模式在 PDF 上下文里不生效**，会退化成用当前颜色实心涂满（画图标时踩过，改用奇偶填充和反向裁剪）。

6. **DDC 断电不可逆** — Philips 27B1U3900 上 `VCP 0xD6 = 0x05` 会让显示器连同它的 `DCPAVServiceProxy` 一起从系统消失，没有任何软件途径唤醒，只能按物理电源键。**所以「熄屏」一律走软断开**，DDC 断电和输入源切换都必须带确认弹窗。

---

## 四、架构 / Architecture

```
LumenBarCore/    引擎，无 UI，可被命令行完整驱动
  Dyn             私有符号一律 dlsym；取不到就降级，绝不在启动时崩
  Defaults        app 与 CLI 的共享设置域（见下方「已修的系统性问题」）
  CGSModeTable    私有模式表 + 布局版本护栏
  ConnectionType  连接方式识别，决定 DDC 闸门
  DDC / DDCCapabilities   I2C 通道与显示器自报能力
  SignalInfo      HDR / EDR / 色彩空间 / 位深 / 信号编码
  ModeEngine BrightnessEngine AudioEngine RotationEngine
  PowerEngine InputEngine CaptureEngine ColorEngine
  ArrangementEngine PresetEngine DisplayDetails HiDPIOverride
  SettingsStore DisplayNameStore LicenseStore
LumenBarUI/      菜单、控制器、快捷键、媒体键、OSD、设置窗、URL 命令
PWE Lumen Bar/        应用外壳（纯 AppKit，自管 NSStatusItem —— MenuBarExtra 收不到滚轮事件）
pwelumenctl/     命令行
```

---

## 五、两个曾经的系统性缺陷 / Two systemic defects, now fixed

这两个值得单独记，因为它们**不表现为报错，只表现为「功能好像没生效」**。

Worth calling out because neither produced an error — both just made features quietly not work.

- **app 与 CLI 曾经用不同的设置存储**。CLI 是裸二进制，`UserDefaults.standard` 落在它自己的域里。在菜单里存的场景，命令行读不到；命令行锁定的显示器，运行中的 app 永远不会执行。现已统一到 `com.pwegroup.pwelumenbar.settings`（`Defaults.shared`）。**任何新增设置都必须走它，不要用 `UserDefaults.standard`。**

- **设置存储曾在启动时读入内存后不再重读**，跨进程写入完全看不见。现在全部读写直连存储。

- **卡片持有的 `DisplayInfo` 会过期**。CoreGraphics 在任何重配置后重新分配显示器 ID，用旧 ID 操作是静默失败。所有会动硬件的操作都必须先经 `live(_:)` 按 EDID 身份重新解析。

---

## 六、Pro 授权机制 / Pro licensing

- 密钥 = 用 Ed25519 私钥对**买家邮箱**的签名，离线验证，无账号、无回连。
- 公钥内嵌在 `LicenseStore.swift`；**私钥在仓库根目录 `.license-signing-key`，已被 .gitignore 排除**。丢了就再也签不出新密钥，泄露则任何人都能签。
- 签发：`swift scripts/make-license.swift buyer@example.com`
- 目前只锁一个功能：强制开启 HiDPI。
- **离线密钥无法限制机器数**（BetterDisplay 用 Paddle 的激活服务器做到 2 台）。要限制就需要一个授权服务器，代价是失去离线可用性。
- **上不了 Mac App Store**：私有 API、不能沙盒、辅助功能事件拦截、向 `/Library` 写管理员文件 —— 每条都是拒绝项。只能直接分发 + 许可证密钥。定价与支付方案**用户已明确搁置**。

---

## 七、当前未决 / Open items

1. **签名**：目前是 ad-hoc 签名。macOS 的辅助功能授权绑定代码签名哈希，**每次重新构建都会让已授予的权限失效** —— 这正是「权限给了但媒体键还是不工作」的原因。用户表示会用自己的开发者账号处理。对外分发还需要 Developer ID + 公证。
2. **媒体键接管尚未在真机验证**。死锁 bug 已修（回调本就在主线程，却又 `DispatchQueue.main.sync` 等自己），但修复本身还没被真正按下 F1 验证过。授权稳定后按一次 F1 即可确认。
3. **DDC 多通道配对未测** —— 需要同时接两台第三方显示器。
4. **`Colorimetry` / `PixelEncoding` 枚举含义未知**。IORegistry 以裸整数暴露，无公开文档。当前只报告能确定的（RGB=0、位深、动态范围），其余按原始值展示 —— **不要凭猜测给它们贴标签**。

---

## 八、诊断 / Diagnostics

app 与 CLI 共写 `~/Library/Logs/PWE Lumen Bar/pwelumenbar.log`（统一日志对 ad-hoc 签名的菜单栏应用不可靠，这是备用通道）。

```bash
pwelumenctl log 50          # 最近 50 行，两个进程共用
pwelumenctl diag            # 每块屏走哪条通道
pwelumenctl details 2       # 完整信息：物理尺寸、PPI、HDR、色彩空间、EDID
pwelumenctl caps 2          # 显示器自报的 DDC capabilities
pwelumenctl hidpi 2 show    # 预览强制 HiDPI 会写什么（不安装）
```

---

## 九、安全约定 / Safety rules to preserve

改动时请守住这几条，它们都是事故换来的：

- 改分辨率、改方向 → **必须走 15 秒确认回滚**；被新操作顶掉时要**回滚**，不能静默丢弃。
- 会让显示器脱离系统的操作（DDC 断电、切换输入源）→ **必须先确认**，并说明只能靠物理按键恢复。
- 「熄屏」→ 走软断开，永远可逆；被关闭的屏必须单独记录，否则它离开在线列表后就再也开不回来。
- 软件调光下限 0.08，**硬件通道不设下限**（0 是面板最低背光，仍可读）。
- 退出时必须 `restoreAllGamma()` —— gamma 修改是进程外生效的。

---

## 音量键：为什么它不看光标 / Volume keys follow the audio, not the pointer

亮度是显示器的属性，音量是**输出设备**的属性。按「调光标所在那块屏」处理音量键，会在戴 AirPods、用 AirPlay、或声音走内建扬声器时，去调一台你根本听不到的显示器扬声器 —— HUD 动了，声音没变。

规则（`AudioEngine.displayOwningOutput` 是唯一判据）：

- 当前系统输出 **正是某台外接显示器自己的音频端点** → PWE Lumen Bar 接管音量/静音键。
- 其余一切（蓝牙、AirPlay、内建扬声器、USB 声卡、聚合设备）→ **原样交还 macOS**，让系统去调真正在发声的设备，保留原生 HUD 与反馈音。
- 亮度键不受影响，仍然跟光标走。

接管那一支不是锦上添花：DisplayPort 音频端点常常**不暴露任何音量控制**（Philips 27B1U3900 实测 `vmvc`/`VolumeScalar`/`Mute` 全部不存在），系统音量键按下毫无反应，而 DDC VCP `0x62` 可用。所以接管的正是系统做不到的那一档；按键被吃掉后系统不会再播反馈音，`playVolumeFeedback()` 自己补上（尊重 `com.apple.sound.beep.feedback`）。

PWE Lumen Bar 自己的 `⌃⌥←→` 保持按光标走 —— 那是它字面的含义，预设一台显示器的音量再切过去是真实需求 —— 但 OSD 第二行会写出声音实际在哪里，不假装你听得到。菜单卡片同理。

`AudioEngine.startWatchingDefaultOutput()` 监听默认输出变化，切到 AirPods 时刷新的是路由，**不重跑 DDC 探测**。

**实测**：把系统输出切到 Philips → `pwelumenctl audio` 报「接管」；切回内建扬声器 → 报「交还 macOS」。真实按键仍未验证（辅助功能授权受 ad-hoc 签名影响）。

---

## 系统版本：怎么在没有那台机器的情况下负责任 / Claiming version support you cannot test

包按 **macOS 14.0** 编译（`Package.swift` 的 `.macOS(.v14)`），bundle 声明 **26.0**。这不是矛盾，是分工：低地板让任何高于 14 的 API 在**编译期**就被挡住（代码里没有一个 `#available`，这条不变量是被编译器保证的），声明的地板是实际推理过的最老系统。

会随系统变的全是私有接口，一律 `dlsym` 运行时解析。因此支持性不靠版本号断言，靠自检：

- `Platform.compatibilityReport()` —— 13 个私有符号 + 芯片 + 系统版本 + CGS 结构体布局。
- `pwelumenctl compat` 打印它；设置 › 系统显示同一份。
- CGS 模式表的布局**自校验**：结构体第 184 字节存着自己的长度，读回来不是 212 就说明 Apple 动过，`CGSModeTable` 直接退回公开 API 并把**实际读到的值**写进日志 —— 这是在一台你没有的机器上唯一有用的那个数字。

Intel：`IOAVService` 不存在，首次启动弹一次说明（`intelWarningShown`），之后不再打扰。
