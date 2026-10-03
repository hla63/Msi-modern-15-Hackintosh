
# Welcome to my EFI repository

Changelog:
- Updating for OpenCore 1.0.**8** and macOS Sonoma
- config.plist synced with my working config (audited & cleaned up), kexts updated (Lilu 1.7.2, VirtualSMC 1.3.8, WhateverGreen 1.7.1, AppleALC 1.9.8, VoodooPS2 2.3.7)
- Updating realtek card reader
- Added [Advanced Map](https://github.com/notjosh/AdvancedMap)
# My config
- macOS Sonoma 14.7.**6**
- Motherboard  **MSI MS-1551** with latest Bios version E1551IMS.10F
- Core i5-10210u
- Intel UHD 620 Mobile graphics
- Intel Kaby Lake HDMI @ Intel Comet Point-LP PCH 
- Realtek ALC 233 (seen as ALC 235) layout 29
- Screen CMN N156HCE-EN1 [15.6" LCD]
- PM980a (doesn't works with macos)
- Sabrent ssd 1to
- **UPDATED 32 GB** ram
- Intel Comet Point-LP PCH - USB 3.1 xHCI Host Controller
- **UPDATED Realtek USB 2.0 Card Reader (thx bismillah-100 https://github.com/0xFireWolf/RealtekCardReader/pull/61)**
- Intel(R) Wireless-AC 9560 works with https://github.com/OpenIntelWireless/itlwm/releases
- Intel bluetooth works. https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases
- **Thanks OpenIntelWireless team**
- Keyboard works (brightness & audio mute/vol -/+) with ssdt
- trackpad works (with gesture & trackpad pref)
- Mute key LED should work **(see launch agent for details sonoma works /maybe sequoia works too)**
# What doesn't works
- USB C to HDMI adapter doesn't work correctly (flickering)
- DRM for AppleTV or Netflix on Safari
- unplugging Graphic Drawing Tablet Pad with USB-C will cause a restart
- =>**resolved under sonoma tx to Claude Ai** https://github.com/hla63/Msi-modern-15-Hackintosh/issues/8

# Tips

- **The EFI will not boot until you generate your own MLB, ROM, SystemSerialNumber and SystemUUID** (PlatformInfo → Generic in config.plist, e.g. with [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) for MacBookPro16,3).
- Make sure you have disabled secure boot in bios.
- You had to disabled CFG Lock in bios.
- At startup press suppr key to enter in bios.
- **Go to Advanced menu & press the magic combo keys**
- Press ALT + RIGHT-CTRL + RIGHT-SHIFT together then press F2 for see hidden feature
- Note (press also fn keys for azerty users)
- go to advanced->power & Performance ->CPU - Power Management Control ->CPU lock Configuration ->CFG lock
- **IF YOU CANNOT GET YOUR CAMERA TO WORK PRESS THE CAMERA BUTTON ON YOUR KEYBOARD AND IT WILL TURN ON**
- **Not included in this repo (disabled in config.plist):** my own MSI EC kexts `SMCMSIFan.kext` & `MSIECToolbox.kext`. Add them to `Kexts/` and set `Enabled` to true if you have them.
- The FydeOS custom entry in `Misc → Entries` is an example (disabled): adapt the device path to your own disk to use it. Ubuntu is detected automatically by OpenLinuxBoot + ext4_x64.
- The second NVMe slot (`PciRoot(0x0)/Pci(0x1D,0x0)`) is disabled for macOS with `class-code = 0` because Samsung PM98x drives are not compatible. Remove this DeviceProperty if you have a compatible SSD in that slot.

# Boot chime (optional)

The boot chime is **disabled** but ready: `AudioDxe.efi` is loaded and `UEFI → Audio → AudioSupport` is `true`, only the chime itself is off.

- To enable it, set `UEFI → Audio → PlayChime` to `Enabled` (always play) or `Auto` (follows the macOS "Play sound on startup" setting).
- Volume: `UEFI → Audio → MaximumGain` and the `SystemAudioVolume` NVRAM value. The sound files are in `OC/Resources/Audio`.
- To disable everything, set `PlayChime` to `Disabled` (current setting), or also set `AudioSupport` to `false` and disable `AudioDxe.efi` in `UEFI → Drivers`.

# Thanks

- Acidanthera for opencore & most kexts
- Daliansky for OC-little & XiaoXinPro-13-hackintosh repository
- bismillah-100 for https://github.com/0xFireWolf/RealtekCardReader/pull/61
- CillyCil for sonoma update https://github.com/CillyCil
- lietxa for https://github.com/lietxia/XiaoXinAir14IML_2019_hackintosh repository
- mledour for MSI-FNKEY SSDT https://github.com/mledour/MSI-GF63-9RCX_OpenCore-Hackintosh
- zxystd for intelbluetooth, itlwmx & heliport https://github.com/OpenIntelWireless/itlwm
- dortania https://dortania.github.io
- Pierre Dandumont for ² key https://www.journaldulapin.com/2020/05/28/faire-un-²-avec-un-clavier-apple/
- pqrs-org for Karabiner https://karabiner-elements.pqrs.org
- FaneCH for https://github.com/FaneCH/Vostro-3490-hackintosh HDMI out works !!!
- 0xFireWolf for https://github.com/0xFireWolf/RealtekCardReader Sdcard reader works !!!
- 5T33Z0 for https://github.com/5T33Z0/OC-Little-Translated/tree/f4490b9f46b828182cc0c0886a7388e982344e6c Oclittle translated
- Andres garcia sobrado for repo https://github.com/AndresGarciaSobrado91/MSI-Modern15-Hackintosh
