# Welcome to my EFI repository

Changelog:
- Updating for OpenCore 1.0.**8** and macOS Sonoma
- config.plist synced with my working config (audited & cleaned up), kexts updated (Lilu 1.7.2, VirtualSMC 1.3.8, WhateverGreen 1.7.1, AppleALC 1.9.8, VoodooPS2 2.3.7, VoodooI2C 2.9.1)
- Updating realtek card reader
- Added [AdvancedMap](https://github.com/notjosh/AdvancedMap) (3D / advanced Apple Maps): included in `Kexts/` but **not enabled** in config.plist (its author says it seems to require a dGPU)
# My config
- macOS Sonoma 14.7.**6**
- Motherboard  **MSI MS-1551** with latest Bios version E1551IMS.10F
- Core i5-10210u
- Intel UHD 620 Mobile graphics
- Intel Kaby Lake HDMI @ Intel Comet Point-LP PCH 
- Realtek ALC 233 (seen as ALC 235) layout 29
- Screen CMN N156HCE-EN1 [15.6" LCD]
- Samsung PM980a NVMe in the second slot: not compatible with macOS, disabled (see Tips)
- Sabrent NVMe SSD 1 TB (macOS)
- **UPDATED 32 GB** ram
- Intel Comet Point-LP PCH - USB 3.1 xHCI Host Controller
- **UPDATED Realtek USB 2.0 Card Reader (thx bismillah-100 https://github.com/0xFireWolf/RealtekCardReader/pull/61)**
- Intel(R) Wireless-AC 9560 works with [AirportItlwm](https://github.com/OpenIntelWireless/itlwm/releases) 2.3.0, Sonoma 14.4+ build (`AirportItlwm-sonoma.kext`, native Wi-Fi, no OCLP patch needed). **It will not load on Sequoia** (`MaxKernel` 23.9.9): Sequoia needs another solution (itlwm + HeliPort, or OCLP root patches)
- Intel bluetooth works. https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases
- **Thanks OpenIntelWireless team**
- Keyboard works (brightness & audio mute/vol -/+) with ssdt
- trackpad works (with gesture & trackpad pref)
- Mute key LED, fan readings and MSI EC features work with [MSI-EC-TOOLBOX](https://github.com/hla63/MSI-EC-TOOLBOX) (`MSIECToolbox.kext` + `SMCMSIFan.kext` + menu bar agent, see below)
# What doesn't work
- USB C to HDMI adapter doesn't work correctly (flickering)
- DRM for AppleTV or Netflix on Safari

# Fixed
- Unplugging a USB-C drawing tablet caused a restart: fixed by the IOHIDDevice kernel patch in `Kernel → Patch` ([issue #8](https://github.com/hla63/Msi-modern-15-Hackintosh/issues/8)). The patch only applies to macOS 14.6 / 14.7 (Darwin 23.6.0) and must be checked after each macOS update.

# Tips

- **The EFI will not boot until you generate your own MLB, ROM, SystemSerialNumber and SystemUUID** (PlatformInfo → Generic in config.plist, e.g. with [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) for MacBookPro16,3).
- Make sure you have disabled secure boot in bios.
- You have to disable CFG Lock in bios (a BIOS update or reset re-enables it).
- At startup press suppr key to enter in bios.
- **Go to Advanced menu & press the magic combo keys**
- Press ALT + RIGHT-CTRL + RIGHT-SHIFT together then press F2 for see hidden feature
- Note (press also fn keys for azerty users)
- go to advanced->power & Performance ->CPU - Power Management Control ->CPU lock Configuration ->CFG lock
- **IF YOU CANNOT GET YOUR CAMERA TO WORK PRESS THE CAMERA BUTTON ON YOUR KEYBOARD AND IT WILL TURN ON**
- `SMCMSIFan.kext` (fan readings for VirtualSMC) and `MSIECToolbox.kext` (MSI EC features) are my own kexts, built for this laptop's embedded controller.
- The FydeOS custom entry in `Misc → Entries` is an example (disabled): adapt the device path to your own disk to use it. Ubuntu is detected automatically by OpenLinuxBoot + ext4_x64.
- The second NVMe slot (`PciRoot(0x0)/Pci(0x1D,0x0)`) is disabled for macOS with `class-code = 0` because Samsung PM98x drives are not compatible. Remove this DeviceProperty if you have a compatible SSD in that slot.
- **VoodooI2C**: this EFI uses the latest official release, 2.9.1 (Nov. 2024). A more up-to-date build exists in [Baio1977/VoodooI2C](https://github.com/Baio1977/VoodooI2C) (2.9.1.a): it is the official VoodooI2C development branch, which includes 5 fixes merged after 2.9.1 but never released (reworked I2C bus timings, new D0 power state handling for Cannon/Comet/Ice Lake I2C controllers, clock gating limited to Broadwell/Lynx Point, updated VoodooI2CHID). Worth a try if the trackpad misbehaves (e.g. after wake); replace `VoodooI2C.kext` and `VoodooI2CHID.kext` together, keep a backup of your EFI. It is not an official release.

# LaunchAgent (MSIECToolbox menu bar agent)

The `LaunchAgent` folder is a copy of [MSI-EC-TOOLBOX/LaunchAgent](https://github.com/hla63/MSI-EC-TOOLBOX/tree/main/LaunchAgent) (mute key + LED sync, mute OSD, fan profiles, EC tools). It needs `MSIECToolbox.kext` loaded.

- Build and install it **without sudo** (the script asks for sudo itself): `cd LaunchAgent && ./build_and_install.sh`
- Requires Xcode command line tools (`swiftc`), macOS 13+.
- Logs: `log stream --predicate 'process == "MSIECToolboxAgent"'`
- See the MSI-EC-TOOLBOX README for details and code-signing options (`SIGN_IDENTITY`).

# Sleep

**Boom 3D prevents automatic sleep.** Its virtual audio device (`GDAudioDevice`) keeps an audio stream open even when nothing is playing, so macOS never goes to sleep on idle (manual sleep and closing the lid still work). `pmset -g` then shows `sleep prevented by coreaudiod`.

- Check: `pmset -g assertions | grep -i coreaudiod` (a `GDAudioDevice` line means Boom 3D is holding the audio stream)
- Fix: enable the **sleep when inactive** option in Boom 3D's settings, then run the check again: it should print nothing.
- Otherwise: quit Boom 3D, or switch the sound output to the built-in speakers when you don't need its effects.

**Hibernation is not set up** (HibernationFixup disabled), so disable automatic hibernation/standby to avoid losing your session after a long sleep:

```
sudo pmset -a hibernatemode 0 standby 0
sudo rm -f /var/vm/sleepimage
```

# Orange microphone dot & SIP (csr-active-config)

Boom 3D keeps the microphone input open, so macOS permanently shows the orange "microphone in use" dot in the menu bar. I hide it with [Recording Indicator Utility](https://github.com/cormiertyshawn895/RecordingIndicatorUtility) (works on Sonoma; discontinued and **not compatible with macOS Sequoia 15.4 or later**).

Recording Indicator Utility requires SIP to be disabled, which is why `NVRAM → Add → 7C436110-AB2A-4BBB-A880-FE41995C9F82 → csr-active-config` is set to `03080000` (0x803). With this value `csrutil status` reports SIP as disabled, which is what the utility checks.

- Check the current state: `csrutil status`
- If you don't use Recording Indicator Utility (or any other tool/patch that needs SIP disabled), first turn the indicator back on and click "Raise Security Settings" in the utility, then set `csr-active-config` to `00000000` to fully enable SIP. It is listed in `NVRAM → Delete`, so the new value is applied at the next boot.
- With SIP disabled: macOS updates are downloaded as full installers, Apple Pay is disabled, and Netflix / Apple TV+ stream in HD instead of 4K.
- Before upgrading to Sequoia 15.4 or later, turn the recording indicator back on in the utility. Otherwise, run `sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.systemstatusd.plist` to fix the high CPU usage it can cause.
- [YellowDot](https://lowtechguys.com/yellowdot/) does not need SIP changes, but according to the Recording Indicator Utility FAQ it only supports macOS 12.1 and earlier.

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
- lietxia for https://github.com/lietxia/XiaoXinAir14IML_2019_hackintosh repository
- mledour for MSI-FNKEY SSDT https://github.com/mledour/MSI-GF63-9RCX_OpenCore-Hackintosh
- zxystd for intelbluetooth, itlwmx & heliport https://github.com/OpenIntelWireless/itlwm
- dortania https://dortania.github.io
- Pierre Dandumont for ² key https://www.journaldulapin.com/2020/05/28/faire-un-²-avec-un-clavier-apple/
- pqrs-org for Karabiner https://karabiner-elements.pqrs.org
- FaneCH for https://github.com/FaneCH/Vostro-3490-hackintosh HDMI out works !!!
- 0xFireWolf for https://github.com/0xFireWolf/RealtekCardReader Sdcard reader works !!!
- 5T33Z0 for https://github.com/5T33Z0/OC-Little-Translated/tree/f4490b9f46b828182cc0c0886a7388e982344e6c Oclittle translated
- Andres garcia sobrado for repo https://github.com/AndresGarciaSobrado91/MSI-Modern15-Hackintosh
- Claude (Anthropic) via [Claude Code](https://claude.com/claude-code) for the OpenCore 1.0.8 update, config.plist & ACPI audit, sleep troubleshooting and repo cleanup
