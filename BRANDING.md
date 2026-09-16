# PWE Lumen Bar — 品牌化记录 / Branding

> 2026-09-01 立档。上游权威：`00 PLANNING 2026/08-品牌识别标准.md`（v1.1）与
> `design-system/paradise-production/MASTER.md`。本文件只记录**这个产品**的决定，
> 以及它与上游标准的每一处偏离。冲突时以上游为准；下面每条偏离都写明了理由。

---

## 一、名字

原名 **Lumen**。改名的理由不是风格，是占位：

- [anishathalye/lumen](https://github.com/anishathalye/lumen) 是一个 macOS 菜单栏自动亮度 app，
  bundle id `com.anishathalye.Lumen`，在 MacUpdate、AlternativeTo 都有条目 ——
  **同平台、同品类、同名**。
- 另有 Lumen Technologies（NYSE: LUMN）与 Laravel Lumen 框架占据搜索与商标位。

定名 **PWE Lumen Bar**：`PWE`（家族前缀）+ `Lumen`（产品名，光的单位，与功能同源）+
`Bar`（品类，菜单栏），与 `PWE Loan Bar` 同构。保留 Lumen 是明知冲突的选择 ——
复合名降低了商标风险，但不解决搜索位；产品走直接分发 + 授权邮件，不依赖商店检索。

改名在**签名分发之前**完成，没有任何已发布版本，因此不需要设置迁移。

## 二、标识符总表

| 项 | 值 |
|---|---|
| 显示名 | `PWE Lumen Bar` |
| App bundle | `PWE Lumen Bar.app` |
| Bundle ID | `com.pwegroup.pwelumenbar` |
| 设置域 | `com.pwegroup.pwelumenbar.settings` |
| URL scheme | `pwelumen://` |
| 命令行 | `pwelumenctl` |
| SwiftPM 包 / 目标 | `PWEDisplayBar` → `PWELumenBar` · `LumenBarCore` · `LumenBarUI` |
| 日志 | `~/Library/Logs/PWE Lumen Bar/pwelumenbar.log` |
| 授权保险库 | `~/.pwe-lumenbar-signing`（签名私钥、ledger、每一张已签发的密钥） |
| Team ID | `2SQV3H5MH9`（Developer ID Application: Li Liu） |

前缀统一到 `com.pwegroup.*`，对齐法律主体 PWE Group Pty Ltd，与 `com.pwegroup.pweloanbar`
一致。**PWE MAC MONITOR 目前是 `com.pwe.macmonitor`** —— 它已经发布，改动会作废用户的
授权与权限，因此不在本次统一范围内；新项目一律用 `com.pwegroup.*`。

## 三、应用图标

navy `#0E1729` 圆角底 + 琥珀 `#F5B335` 翅膀（宽度 60%），与
`01 BRAND ASSETS/logo/app-icon-512.svg`、PWE Loan Bar、PWE MAC MONITOR 同一构造 ——
那个方块**就是**家族身份。

**本产品唯一的增补：翅尖外侧两颗四角星。** 理由与边界：

- 三个 PWE 应用在 `/Applications` 与聚光灯里长成同一个图标是真实的缺陷。
- 标准 §7 禁止的是**改动翅膀本身**（改色、拉伸、加效果）。星芒是底面上的独立元素，
  不接触翅膀，用的是品牌色 —— 不构成对标识的改动。
- 星芒同时是分辨率菜单里标记 HiDPI 的那个形状，图标与界面用同一个形状说「锐利」。
- 小尺寸下第二颗星会退化成一个斑点，因此 64px 以下只画大的那一颗。

几何来自 `Sources/LumenBarUI/Brand/BrandMark.swift`，由
`scripts/import-wing.py` 从 `01 BRAND ASSETS/source/wing_gen.py` 的输出导入，
**不手工编辑**（标准 §2 / §7）。图标由 `scripts/icon/main.swift` 与 BrandMark
一起编译后生成 —— 图标里的翅膀和界面里的翅膀是同一份几何，不可能走形。

## 四、菜单栏图标：仍然是显示器字形，不是翅膀

两条独立理由，任一条都足够：

1. 标准 §7.1 的仪表破例已由 PWE MAC MONITOR 实尺验证：**22px 高度下逐羽辨色不成立**
   （见 `07 TOOLS/PWE Monitor/docs/wing-states.md`）。
2. 同一条菜单栏上如果两个 PWE 应用都是翅膀，用户分不出哪个是哪个。
   菜单栏图标的职责是功能识别，不是身份。

## 五、界面用色

**控件跟随系统强调色。** 滑块、按钮、开关一律用用户在「系统设置」里选的颜色。
一个无视用户强调色的系统工具读起来是坏了，不是有品牌。

**品牌色只出现在产品说话的地方**：菜单面板标题、欢迎窗、设置里的「关于」、图标。

`Brand.accent` 是计算属性而不是常量，因为标准 §5 的硬规则要在**每一个调用点**成立：
琥珀 `#F5B335` 只能落在深底，浅底一律 `#A16207`。取色时按当前 appearance 解析，
不靠下一个人记得这条规则。深浅两种模式都由 `swift run pwelumenshots` 渲染出来核对过。

## 六、署名：中英分开

| 场合 | 署名 |
|---|---|
| 中文界面、`README.md`、`docs/GUIDE.md` | 天域文创出品 |
| 英文界面、`README.en.md`、`docs/GUIDE.en.md` | A PARADISE PRODUCTION |
| 同一份文件同时面向两种读者（磁盘映像里的说明与条款） | 两种并列 |

**与标准 §1 的偏离**：标准规定的署名格式是并列的
`A PARADISE PRODUCTION · 天域文创出品`。一个已经运行在单一语言下的界面，
印上另一种语言的半行，对每个读者都是一半噪音。所以按语言分开，
只在一份文件必须同时服务两种读者时才用并列形式。

**这条是产品级决定，建议回写进品牌标准**（对所有双语产品都成立）。

版权字符串：`© 2026 PWE Group Pty Ltd`；bundle 的 `NSHumanReadableCopyright` 是
`© 2026 PWE Group Pty Ltd · A PARADISE PRODUCTION`（Finder 显示，单值，用英文）。

## 七、字体：不嵌入 Playfair

标准 §6 的字体系统（Playfair Display + Inter）适用于品牌物料。这是一个 macOS 系统工具，
界面一律用系统字体 SF —— 在系统工具里换字体，读起来是异物而不是品牌。
为一个产品名嵌入 400KB 字体并承担 OFL 的随附义务，不划算。

字体出现在**站点页与磁盘映像背景**这类品牌物料上（走网页字体或直接栅格化），
不进应用包。

## 八、分发链（与 PWE Loan Bar 同一条）

| 环节 | 命令 |
|---|---|
| 开发构建 | `./scripts/build-app.sh --install` |
| 发布 | `./scripts/package.sh --notarize` → `dist/PWE Lumen Bar <版本>.dmg` |
| 签发授权 | `./tools/issue.sh --email …`（`--cn` 出中文邮件） |
| 查账 | `./tools/issue.sh --list` |

- 一切带签名的东西都在 iCloud 之外组装：iCloud 的 file provider 会在几秒内把
  `com.apple.FinderInfo` 贴回目录，而 codesign 拒绝校验带它的 bundle。
- 开发构建也用 Developer ID 证书签名 —— macOS 把「辅助功能」授权绑在代码签名哈希上，
  ad-hoc 签名每次重建都会静默作废它，这正是「权限给了但媒体键不工作」的成因。
- `pwelumen://activate?email=…&key=…` 是授权邮件的一键激活入口。密钥是应用自己校验的
  签名，所以链接不比手动粘贴更可信 —— 错的密钥只是验不过。

## 九、与上游标准的偏离清单

| 偏离 | 位置 | 理由 |
|---|---|---|
| 图标增加两颗星芒 | 应用图标 | 三个家族应用图标全同是真实缺陷；星芒不接触翅膀，见 §三 |
| 署名按语言拆开 | 界面与单语文档 | 见 §六，建议回写标准 |
| 界面不使用品牌字体 | 全部界面 | 系统工具用系统字体，见 §七 |
| 控件不使用品牌色 | 全部控件 | 尊重用户的系统强调色，见 §五 |

翅膀几何、五根羽毛、颜色值、浅底不得用亮琥珀 —— **这四条没有偏离**。

## 十、未决

- **定价：Pro 一次性 A$9.99**（2026-09-01 定）。写法跟随家族惯例（Loan Bar 用 `A$58`），
  产品页与购买邮件里都是 A$ —— **如果要卖美元，产品页、邮件模板和 `tools/config.sh` 三处一起改。**
  应用本身免费，没有试用期。
- 产品页与使用指南在 `site/public/lumen/`（`/lumen` 与 `/lumen/guide`），已复制进
  `PWE Loan Bar/site/public/`，集团首页也加了卡片，`deploy.sh` 已接上（样式指纹、
  磁盘映像暂存、上线自检）。🔴 **部署本身是对外发布动作，等确认。**
- ✅ 已上线：<https://pwestudio.site/lumen> 与 <https://pwestudio.site/lumen/guide>，
  安装包由 `deploy.sh` 从本项目 `dist/` 暂存，线上文件与本地公证过的那一份 sha256 一致。
  `tools/config.sh` 的 `DOWNLOAD_URL` 已填上。
- **图注一律双语，两份文件一套几何。** 说明图原本只有中文；`scripts/docs-en-figures.py`
  从中文原图生成 `-en.svg` 双胞胎（只换字串与必要的排版补丁），中文原图仍是几何的唯一来源。
  找不到要替换的字串就直接报错退出 —— 半中半英的英文图不许发出去。
  `hidpi-explained.svg` 例外：它一开始就是双语画的，两边共用。
  `scripts/site-figures.py` 把站点用到的图拷进 `site/public/lumen/img/`，
  并按 viewBox 裁出首页那张只有面板的主图（矢量裁剪，不损失清晰度）。
- 面板图目前仍是示意图而非真机截图。示意图与真机已逐项对齐（含徽章文案「主屏」缩短那次改动），
  但真机截图更可信 —— popover 脚本抓不到，需要人在键盘前截一张。
- 版本号定在 `1.0.0`（`scripts/version.sh`），首发前确认。
