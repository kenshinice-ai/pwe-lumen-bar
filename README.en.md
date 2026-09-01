# Lumen

English · [中文](README.md)

A macOS menu bar display controller. Per-display brightness, contrast, warmth, volume, resolution / HiDPI, orientation, input source, colour profile, power and screenshots — the MacBook's own panel included.

> **Supports only Apple Silicon (M-series), on macOS 26 and 27.**
>
> Nothing in Lumen's own code needs an API newer than macOS 14 — the package is
> compiled against that floor so a newer one cannot creep in unnoticed.
> Everything version-sensitive is private and resolved at run time, so run
> `lumenctl compat` to see, on your machine, whether every entry point Lumen
> depends on is present. Development and verification happen on 27.
> Resolution goes through the private CGS mode table, rotation through SkyLight, DDC through `IOAVService` —
> all three are Apple Silicon paths. The Intel equivalents have been removed from the code and are not supported.

## Getting started

```bash
./scripts/build-app.sh
cp -R build/Lumen.app /Applications/ && open /Applications/Lumen.app
```

Click the display icon in the menu bar to open the panel. **Scroll on the icon** to change the brightness of whatever display the pointer is on without opening anything; **right-click** to switch presets. The interface follows the system language and can be forced to Chinese or English in Settings.

**Two switches worth turning on** (both in Settings, both off by default):

| Switch | What it does |
|---|---|
| Global shortcuts | `⌃⌥↑↓` brightness, `⌃⌥←→` volume, `⌃⌥M` mute, `⌃⌥S` capture, `⌃⌥P` off/on — **acting on the display under the pointer**. Rebindable, and needs no Accessibility permission |
| Remember each display's settings | Restores brightness / warmth / resolution / orientation after undocking and redocking |

## Capability matrix

Every capability is **probed at run time**. What cannot be probed is greyed out with the reason stated — never a slider that moves and does nothing.

| Capability | Built-in | External | Path |
|---|---|---|---|
| Brightness | ✅ | ✅ | `DisplayServices` → DDC `0x10` → gamma software dimming (three-step fallback) |
| Contrast | — | ✅ | DDC `0x12` |
| Colour temperature | ✅ | ✅ | Gamma curve, composed into one table with software dimming |
| Screenshot | ✅ | ✅ | ScreenCaptureKit, at full pixel resolution |
| Colour profile | ✅ | ✅ | ColorSync — switch or reset to factory (public API) |
| Arrangement | ✅ | ✅ | `CGConfigureDisplayOrigin`, committed as one transaction |
| Presets | ✅ | ✅ | Brightness / warmth / volume / resolution / orientation / position / colour profile in one click |
| Follow built-in brightness | — | ✅ | External displays track the ambient-adjusted built-in panel at the ratio captured when enabled |
| Display details | ✅ | ✅ | Physical size, native resolution, PPI, white point; raw EDID exported when available |
| Volume / mute | ✅ | ✅ | CoreAudio device matching → DDC `0x62` / `0x8D` |
| Resolution / HiDPI | ✅ | ✅ | Private CGS mode table, public API as fallback |
| Refresh rate | ✅ | ✅ | As above |
| Input source | — | ✅ | DDC `0x60` |
| Rotation | ✅ | ✅ | SkyLight `SLSSetDisplayRotation` |
| **Turn one display off / on** | ✅ | ✅ | DDC power where supported, otherwise taken off the desktop — both reversible |
| Remove from desktop | ✅ | ✅ | Private `CGSConfigureDisplayEnabled` |
| Main display / mirror | ✅ | ✅ | Public CoreGraphics API |

## The connection decides which controls exist

`kCGDisplayIsAirPlay` and `kCGDisplayIsVirtualDevice` in `CoreDisplay_DisplayCreateInfoDictionary` identify displays with no physical link, definitively. AirPlay screens and DisplayLink-style virtual displays **have no I2C channel**, so Lumen skips DDC entirely for them — saving three failed retries (about a second) on every refresh — and says plainly that only software dimming is available.

## Why HiDPI needs a private API

On macOS 27 / M1, the public `CGDisplayCopyAllDisplayModes` returns **three modes for the built-in display, and does not include the one currently in use**:

```
Public API:  2560×1600 1x   2048×1280 1x   1920×1200 1x
Private CGS: 960×600 2x   1024×640 2x   1280×800 2x   1440×900 2x ←current
             1680×1050 2x   1920×1200 1x   2048×1280 1x   2560×1600 1x
```

The documented `kCGDisplayShowDuplicateLowResolutionModes` option has **no effect at all** on this release. Every HiDPI mode lives only in the window server's own table. The struct offsets were confirmed against hardware (`Sources/LumenCore/CGSModeTable.swift`), and **offset 184 holds the struct's own length, 212** — if that stops reading back as 212 the layout has moved, and the whole private path is abandoned in favour of the public API rather than trusting misaligned memory.

## Three safety decisions

1. **Resolution and orientation changes both go through a 15-second countdown.** Doing nothing reverts. A mode a monitor cannot display is unrecoverable from a menu bar app — the menu lives on the screen that just went dark.
2. **Software dimming is always restored on quit.** Gamma changes outlive the process; not undoing them leaves a permanently dim screen with no interface left to fix it.
3. **Removing the last display from the desktop is refused**, so the machine cannot be left with no picture.

## Rotation: a wrong road, and a conclusion that was wrong with it

The first version used IOKit's `IOServiceRequestProbe(kIOFBSetTransform)` — the **Intel-era** path. On this M1 it answers `kIOReturnUnsupported` for *every* display, which led to the conclusion that the built-in panel could not rotate.

That conclusion was wrong. The correct path is SkyLight's `SLSSetDisplayRotation(displayID, degrees)` — no connection ID. With that in place, **both the built-in panel and the Studio Display rotate normally**; macOS simply hides the control for the built-in one in System Settings.

The lesson: `kCGDisplaySupportsRotation` claimed `true` for the built-in panel while the IOKit probe claimed `false`. Neither was trustworthy — **only the result from the right API counted**. Capability is now decided by asking SkyLight for the angle already in effect and seeing whether it is accepted.

## Automation

The `lumen://` URL scheme, usable from the Shortcuts "Open URLs" action:

```
lumen://brightness?display=cursor&value=60     display = cursor / main / builtin / ID / name fragment
lumen://brightness?display=main&delta=-10      relative
lumen://volume?display=LG&value=30
lumen://warmth?display=main&value=40
lumen://mute?display=main&state=toggle
lumen://preset?name=Work
lumen://rotate?display=2&angle=90
lumen://mode?display=main&id=cgs:3
lumen://input?display=LG&source=hdmi1
lumen://arrange?tile          lumen://sleep
```

**Screen capture is deliberately absent from the URL scheme.** Any app or web page can open a custom URL, and Lumen holds Screen Recording permission — exposing capture there would hand silent screenshots to anything that can open a link. The other commands only change display settings, which are visible and reversible.

## Command line

`lumenctl` shares the engines with the interface. Add `--lang zh|en` to switch the output language.

```bash
lumenctl diag                        # which channel each display uses
lumenctl modes 1 --all               # every mode, HiDPI included
lumenctl set-mode 1 cgs:2 --revert 3 # switch and auto-revert after 3s
lumenctl brightness 1 70
lumenctl input 1 hdmi1
lumenctl rotate-probe 1              # probe the rotation channel without rotating
lumenctl capture 1                   # capture this display to the desktop
lumenctl color 1 "Display P3"
lumenctl arrange 2 left              # put display 2 left of the main one
lumenctl details 1                   # full report, EDID availability included
lumenctl preset save Work            # save / apply / delete presets
lumenctl off 2                       # turn one display off (reversible)
lumenctl on                          # turn it back on
lumenctl remember on|off|show|clear
```

## Layout

```
LumenCore/   Engines. No UI, fully drivable from the command line
  Dyn            every private symbol resolved via dlsym; missing ones degrade
                 the feature instead of killing the app at launch
  CGSModeTable   the private mode table, with a layout version guard
  ConnectionType connection detection, which gates DDC
  L10n           Chinese / English copy
  ModeEngine / BrightnessEngine / AudioEngine / RotationEngine
  PowerEngine / InputEngine / CaptureEngine
  ColorEngine / ArrangementEngine / PresetEngine / DisplayDetails
  SettingsStore  keyed by EDID identity, not by the display ID that changes
LumenUI/     Menu views, controller, global shortcuts, settings window, URL commands
             StatusItemController manages the status item directly, because
             MenuBarExtra cannot see scroll events
Lumen/       App shell (plain AppKit)
lumenctl/    Command line
scripts/     Packaging and vector icon generation
```

The icon is vector: `scripts/make-icons.swift` runs one Core Graphics drawing routine to emit `Resources/AppIcon.pdf`, the menu bar's `MenuBarIcon.pdf` (a template image, crisp at any scale factor) and every `.icns` size.

## Verified / not verified

**Verified on this M1 MacBook Air, macOS 27.0**: display enumeration, HiDPI mode enumeration, resolution switching and revert, `DisplayServices` brightness read/write, CoreAudio volume read/write, rotation capability probing, soft-disconnect symbol availability, global shortcut registration (6/6, no conflicts), per-display settings memory, gamma composition of warmth and dimming (verified by reading the table back), per-display capture at 2880×1800, full preset round-trip, the URL scheme, and colour profile enumeration.

**External display results** (Apple Studio Display 5K, 1 September 2026):

| Item | Result |
|---|---|
| Enumeration, 25 modes / 9 HiDPI | ✅ native 5120×2880, 218 PPI |
| Brightness | ✅ via `DisplayServices` — Apple displays do not need DDC |
| Volume | ✅ matched "Studio Display Speakers", carried over **USB** |
| Rotation | ✅ 2560×1440 ↔ 1440×2560, round trip |
| Turn off / on | ✅ online display count 2 → 1 → 2 |
| `kDisplayTransportType` | wired external = **1** (built-in = 0) |
| DDC/CI | ❌ the Studio Display answers no VCP at all — Apple displays use their own protocol |

**Still unverified**: the DDC chain on a third-party monitor (contrast `0x12`, volume `0x62`, input source `0x60`, backlight off `0xD6`) and DDC multi-channel pairing. Both need a non-Apple display.

## Four bugs the external display exposed

1. **Rotation was broken everywhere** — the Intel IOKit path. Switching to SkyLight made both displays rotate (above).
2. **Framebuffer service matching could target the wrong panel** — the built-in display's `ProductID & 0xFFFF` is 13377 while `CGDisplayModelNumber` is 41033. When identity matching missed, the code fell back to "the first candidate service", which with two displays attached was the Studio Display's. It now prefers the exact `IODisplayLocation` path CoreDisplay reports, and **returns nil rather than guessing** when nothing matches.
3. **The Studio Display's volume was invisible** — its audio arrives over **USB**, and the fuzzy match required HDMI/DisplayPort, rejecting a device literally named "Studio Display Speakers". Name matching no longer depends on transport.
4. **DDC was reported as available when it was not** — merely creating an `IOAVService` counted as support, but the Studio Display answers nothing. Availability now requires reading back a real VCP value.

## Next

- EDID override to force HiDPI on displays that report none (needs admin rights and a restart; behaviour on macOS 27 still unverified)
- Nits-normalised brightness across displays
- Native App Intents for Shortcuts — SwiftPM cannot emit `Metadata.appintents`, which needs an Xcode project; the URL scheme covers the same ground today

## One thing deliberately not built

**Virtual / dummy displays.** `CGVirtualDisplayCreate` **does not exist** on macOS 27 — the symbol has been renamed or moved to another framework. No promises until that is understood.
