
# Welcome to my Efi repository

Changelog:
Adding Opencore 0.8.7 version


Hi! This is my very first time hackintosh machine.I'm a beginner of hackintosh.Help apreciated.
# My config
- Mac Os Monterey 12.6.**2**
- Motherboard  **MSI MS-1551** with latest Bios version E1551IMS.10F
- Core i5 10210u
- Intel uhd graphics
- Intel Kaby Lake HDMI @ Intel Comet Point-LP PCH 
- Realtek ALC 233 (seen as ALC 235) layout 29
- Screen CMN N156HCE-EN1 [15.6" LCD]
- SAMSUNG MZVLB512HAJQ-00000 (512 Go, PCI-E 3.0 x4) (**Disabled on macos/works for windows**)
- Sabrent 1to (works good Mac os & Ubuntu partition.Triple boot)
- Memory samsung 8 go
- Intel Comet Point-LP PCH - USB 3.1 xHCI Host Controller
- **Realtek USB 2.0 Card Reader (work with https://github.com/0xFireWolf/RealtekCardReader)**
- Intel(R) Wireless-AC 9560 works with https://github.com/OpenIntelWireless/itlwm/releases
- Intel bluetooth works. https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases
- **Thanks OpenIntelWireless team**
- Keyboard works (brightness & audio mute/vol -/+) with ssdt
- trackpad works (with gesture & trackpad pref)
# What doesn't works
- PM980 doesn't work correctly under Macos.I deactivated it with SSDT.
- Mute key work exept for Led status (always on or always off.Depends on the last state under windows)
- Usb C to HDMI adapter doesn't work correctly (flickering)
- DRM for AppleTV or Netflix on Safari


# Tips

- Make sure you have disabled secure boot in bios.
- You had to disabled CFG Lock in bios.
- At startup press suppr key to enter in bios.
- **Go to Advanced menu & press the magic combo keys**
- Press ALT + RIGHT-CTRL + RIGHT-SHIFT together then press F2 for see hidden feature
- Note (press also fn keys for azerty users)
- go to advanced->power & Performance ->CPU - Power Management Control ->CPU lock Configuration ->CFG lock

# Thanks

- Acidanthera for opencore & most kexts
- Daliansky for OC-little & XiaoXinPro-13-hackintosh repository
- lietxa for https://github.com/lietxia/XiaoXinAir14IML_2019_hackintosh repository
- mledour for MSI-FNKEY SSDT https://github.com/mledour/MSI-GF63-9RCX_OpenCore-Hackintosh
- zxystd for intelbluetooth, itlwmx & heliport https://github.com/OpenIntelWireless/itlwm
- dortania https://dortania.github.io
- Pierre Dandumont for ² key https://www.journaldulapin.com/2020/05/28/faire-un-²-avec-un-clavier-apple/
- pqrs-org for Karabiner https://karabiner-elements.pqrs.org
- FaneCH for https://github.com/FaneCH/Vostro-3490-hackintosh HDMI out works !!!
- 0xFireWolf for https://github.com/0xFireWolf/RealtekCardReader Sdcard reader works !!!
- 5T33Z0 for https://github.com/5T33Z0/OC-Little-Translated/tree/f4490b9f46b828182cc0c0886a7388e982344e6c Oclittle translated
