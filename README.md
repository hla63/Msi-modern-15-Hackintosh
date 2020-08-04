# Welcome to my w.i.p Efi repository

Hi! This is my very first time hackintosh machine.I'm a beginner of hackintosh.Help apreciated.
# My config
- Motherboard  **MSI MS-1551**
- Core i5 10210u
- Intel uhd graphics
- Intel Kaby Lake HDMI @ Intel Comet Point-LP PCH (not tested)
- Realtek ALC 233 (seen as ALC 235) (works with latest AppleALC 1.5.1)
- Screen CMN N156HCE-EN1 [15.6" LCD]
- SAMSUNG MZVLB512HAJQ-00000 (512 Go, PCI-E 3.0 x4) (**doesn't work properly on mac os**)
- Sabrent 1to (works good .Mac os partition)
- Memory samsung 8 go
- Intel Comet Point-LP PCH - USB 3.1 xHCI Host Controller
- **Realtek USB 2.0 Card Reader (doesn't work)**
- Intel(R) Wireless-AC 9560 160MHz Works with latest itlwmx.kext https://github.com/OpenIntelWireless/itlwm/releases
- Intel bluetooth works. https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases
- **Thanks OpenIntelWireless team**
- Keyboard works good (brightness & audio mute/vol -/+) with ssdt
- trackpad works most of the time (with gesture & trackpad pref)

# Tips

- Make sure you have disabled secure boot in bios.
- You had to disabled CFG Lock in bios.

- At startup press suppr key
-**Go to Advanced menu & press the magic combo keys**

- Press ALT + RIGHT-CTRL + RIGHT-SHIFT together then press F2 for see hidden feature
- Note (press also fn keys for azerty users)
- go to advanced->power & Performance ->CPU - Power Management Control ->CPU lock Configuration ->CFG lock
