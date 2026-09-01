# Third-party notices

**PWE Lumen Bar bundles no third-party code.** The package has no dependencies
(`Package.swift` declares none), nothing is vendored, and no font, image or
library from anyone else ships inside the app.

What it uses instead:

| Source | What for |
|---|---|
| Apple frameworks — AppKit, SwiftUI, CoreGraphics, IOKit, CoreAudio, CryptoKit, ScreenCaptureKit | Everything the app does |
| Apple private interfaces — `SkyLight`, `CoreDisplay`, `DisplayServices`, `IOAVService` | Rotation, the HiDPI mode table, brightness on Apple panels, DDC/CI over I²C |

The private interfaces are resolved with `dlsym` at run time and each one
degrades on its own if it disappears — `pwelumenctl compat` reports what
resolved on the machine in front of you. They are Apple's, not ours, and are
used from a directly distributed app: this is one of the reasons the app cannot
go to the Mac App Store.

The Paradise Production wing in the icon and the interface is generated from
`01 BRAND ASSETS/source/wing_gen.py` and is the property of PWE Group Pty Ltd.
