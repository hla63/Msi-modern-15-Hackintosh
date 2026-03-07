// ---------------------------------------------------------------------------
// MSIMuteLEDAgent.swift
// LaunchAgent — surveillance bidirectionnelle : CoreAudio ↔ EC + CGEventTap
//
// v4.1.0 :
//   - CGEventTap intercepte F14 (keycode 107) = touche F5 mute mic physique
//     mappée via SSDT-MSI-KEY_FIX (e071 → ADB 4f).
//     L'événement est annulé (pas de comportement par défaut) et le mute mic
//     CoreAudio est togglé, ce qui déclenche le listener CoreAudio existant
//     qui met à jour la LED via le kext.
//   - Polling EC maintenu pour robustesse mais inactif si EC ne change pas.
//
// Registres EC (MSI Modern 15 — confirmés via DSDT) :
//   0x2B bit2 = MICL  (1 = mic muet)
//   0x2C bit2 = MUTL  (1 = speaker muet)
// ---------------------------------------------------------------------------

import Foundation
import CoreAudio
import IOKit
import CoreGraphics
import CoreGraphics

// ---------------------------------------------------------------------------
// MARK: – Sélecteurs & types partagés
// ---------------------------------------------------------------------------

enum MSIMuteLEDSelector: UInt32 {
    case setMuteState = 0
    case getMuteState = 1
    case dumpEC       = 2
}

struct MSIMuteState {
    var speakerMuted: UInt8
    var micMuted:     UInt8
    var reserved0:    UInt8 = 0
    var reserved1:    UInt8 = 0
}

private let kECOffsetMic:     Int   = 0x2B
private let kECOffsetSpeaker: Int   = 0x2C
private let kECBitLED:        UInt8 = 0x04

// Keycode macOS pour ADB 0x4f (VoodooPS2 → CGKeyCode 79, confirmé en debug)
private let kF14KeyCode: CGKeyCode = 79
// Keycode macOS pour ADB 0x6f (F12 rotation → CGKeyCode 111, confirmé en debug)
private let kF13KeyCode: CGKeyCode = 111

// ---------------------------------------------------------------------------
// MARK: – Wrapper IOKit
// ---------------------------------------------------------------------------

final class MSIMuteLEDClient {

    private var connection:      io_connect_t = 0
    private var notifyPort:      IONotificationPortRef? = nil
    private var addedIterator:   io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    var isConnected: Bool { connection != 0 }

    func connect() -> Bool {
        guard !isConnected else { return true }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("MSIMuteLEDDriver"))
        guard service != 0 else {
            NSLog("[MSIMuteLEDAgent] Service introuvable (kext chargé ?)")
            return false
        }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else {
            NSLog("[MSIMuteLEDAgent] IOServiceOpen failed: 0x%08X", kr)
            return false
        }
        connection = conn
        NSLog("[MSIMuteLEDAgent] Connecté au kext (conn=0x%X)", conn)
        return true
    }

    func disconnect() {
        guard isConnected else { return }
        IOServiceClose(connection)
        connection = 0
    }

    func setMuteState(speaker: Bool, mic: Bool) -> Bool {
        guard isConnected else { return false }
        var state = MSIMuteState(speakerMuted: speaker ? 1 : 0,
                                 micMuted:     mic     ? 1 : 0)
        let kr = withUnsafeBytes(of: &state) { ptr in
            IOConnectCallStructMethod(
                connection,
                MSIMuteLEDSelector.setMuteState.rawValue,
                ptr.baseAddress, MemoryLayout<MSIMuteState>.size,
                nil, nil)
        }
        return kr == KERN_SUCCESS
    }

    func readECMuteState() -> (micMuted: Bool, speakerMuted: Bool)? {
        guard isConnected else { return nil }
        var outBytes = [UInt8](repeating: 0, count: 256)
        var outSize  = outBytes.count
        let kr = outBytes.withUnsafeMutableBytes { ptr in
            IOConnectCallStructMethod(
                connection,
                MSIMuteLEDSelector.dumpEC.rawValue,
                nil, 0,
                ptr.baseAddress, &outSize)
        }
        guard kr == KERN_SUCCESS, outSize > kECOffsetSpeaker else { return nil }
        return (
            micMuted:     (outBytes[kECOffsetMic]     & kECBitLED) != 0,
            speakerMuted: (outBytes[kECOffsetSpeaker] & kECBitLED) != 0
        )
    }

    func watchService() {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notifyPort else { return }
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddMatchingNotification(
            port, kIOMatchedNotification,
            IOServiceMatching("MSIMuteLEDDriver"),
            { rawCtx, it in
                let me = Unmanaged<MSIMuteLEDClient>.fromOpaque(rawCtx!).takeUnretainedValue()
                while IOIteratorNext(it) != 0 {}
                _ = me.connect()
            }, ctx, &addedIterator)
        while IOIteratorNext(addedIterator) != 0 {}
        IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification,
            IOServiceMatching("MSIMuteLEDDriver"),
            { rawCtx, it in
                let me = Unmanaged<MSIMuteLEDClient>.fromOpaque(rawCtx!).takeUnretainedValue()
                while IOIteratorNext(it) != 0 {}
                me.disconnect()
            }, ctx, &removedIterator)
        while IOIteratorNext(removedIterator) != 0 {}
    }
}

// ---------------------------------------------------------------------------
// MARK: – Observateur principal
// ---------------------------------------------------------------------------

final class MuteObserver {

    private let client: MSIMuteLEDClient

    private var lastSpeaker     = false
    private var lastMic         = false
    private var lastSentSpeaker = false
    private var lastSentMic     = false

    private var displayRotated  = false  // false = 0°, true = 180°
    private let kDisplayID      = "CC868235-2DF0-05C3-7FEE-80DFD78D701F"

    private var currentOutputID: AudioDeviceID = AudioDeviceID(kAudioObjectUnknown)
    private var currentInputID:  AudioDeviceID = AudioDeviceID(kAudioObjectUnknown)

    private var pollTimer: DispatchSourceTimer?
    private var eventTap:  CFMachPort?

    init(client: MSIMuteLEDClient) { self.client = client }

    func start() {
        signal(SIGTERM) { _ in
            NSLog("[MSIMuteLEDAgent] SIGTERM – arrêt propre")
            CFRunLoopStop(CFRunLoopGetMain())
        }

        _ = client.connect()
        client.watchService()
        installDeviceChangeListeners()
        installMuteListeners(force: true)
        startECPolling()
        installKeyEventTap()  // tap unique pour F14 (mic) + F13 (rotation)

        NSLog("[MSIMuteLEDAgent] Démarré v4.2.0 – CGEventTap F14 (mic) + F13 (rotation) + polling EC 200ms")
        CFRunLoopRun()

        pollTimer?.cancel()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        client.disconnect()
        NSLog("[MSIMuteLEDAgent] Arrêté proprement")
    }

    // ── CGEventTap unique — F14 (mic mute) + F13 (rotation écran) ───────────

    private func installKeyEventTap() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap:              .cgSessionEventTap,
            place:            .headInsertEventTap,
            options:          .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard type == .keyDown else { return Unmanaged.passRetained(event) }
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let me = Unmanaged<MuteObserver>.fromOpaque(userInfo!).takeUnretainedValue()
                switch CGKeyCode(keyCode) {
                case kF14KeyCode:
                    NSLog("[MSIMuteLEDAgent] F14 intercepté → toggle mic mute")
                    me.toggleMicMute()
                    return nil   // annuler l'événement
                case kF13KeyCode:
                    NSLog("[MSIMuteLEDAgent] F13 intercepté → toggle rotation écran")
                    me.toggleDisplayRotation()
                    return nil   // annuler l'événement
                default:
                    return Unmanaged.passRetained(event)
                }
            },
            userInfo: ctx)
        else {
            NSLog("[MSIMuteLEDAgent] CGEventTap échoué — vérifier autorisation Accessibilité")
            NSLog("[MSIMuteLEDAgent] → Réglages Système > Confidentialité > Accessibilité")
            return
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        NSLog("[MSIMuteLEDAgent] CGEventTap installé — F14 (keycode=%d) + F13 (keycode=%d)",
              kF14KeyCode, kF13KeyCode)
    }



    private func toggleMicMute() {
        let deviceID = defaultInputDevice()
        guard deviceID != kAudioObjectUnknown else { return }
        let current = readMute(deviceID: deviceID, input: true)
        setAudioMute(deviceID: deviceID, input: true, muted: !current)
    }

    private func toggleDisplayRotation() {
        let newDegree  = displayRotated ? 0 : 180
        displayRotated = !displayRotated

        NSLog("[MSIMuteLEDAgent] Rotation écran → %d°", newDegree)

        // Spec complète nécessaire pour que displayplacer fonctionne
        // dans les deux sens (0°→180° et 180°→0°)
        let spec = "id:\(kDisplayID) res:1920x1080 color_depth:4 enabled:true scaling:off origin:(0,0) degree:\(newDegree)"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/displayplacer")
        task.arguments = [spec]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = pipe
        task.launch()
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !out.isEmpty { NSLog("[MSIMuteLEDAgent] displayplacer: %@", out) }
        NSLog("[MSIMuteLEDAgent] Rotation terminée (exit=%d)", task.terminationStatus)
    }

    // ── Polling EC ──────────────────────────────────────────────────────────

    private func startECPolling() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.2, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.pollEC() }
        timer.resume()
        pollTimer = timer
    }

    private func pollEC() {
        guard let ecState = client.readECMuteState() else { return }
        let speakerChanged = ecState.speakerMuted != lastSentSpeaker
        let micChanged     = ecState.micMuted     != lastSentMic
        guard speakerChanged || micChanged else { return }

        NSLog("[MSIMuteLEDAgent] EC poll → speaker=%d mic=%d",
              ecState.speakerMuted ? 1 : 0, ecState.micMuted ? 1 : 0)

        if speakerChanged { setAudioMute(deviceID: defaultOutputDevice(), input: false, muted: ecState.speakerMuted) }
        if micChanged     { setAudioMute(deviceID: defaultInputDevice(),  input: true,  muted: ecState.micMuted) }

        lastSentSpeaker = ecState.speakerMuted
        lastSentMic     = ecState.micMuted
        lastSpeaker     = ecState.speakerMuted
        lastMic         = ecState.micMuted
    }

    // ── CoreAudio → EC ──────────────────────────────────────────────────────

    private func installDeviceChangeListeners() {
        var addrOut = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var addrIn = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addrOut, DispatchQueue.main) {
                [weak self] _, _ in self?.installMuteListeners(force: false); self?.refresh()
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addrIn, DispatchQueue.main) {
                [weak self] _, _ in self?.installMuteListeners(force: false); self?.refresh()
        }
    }

    private func installMuteListeners(force: Bool) {
        let newOut = defaultOutputDevice()
        let newIn  = defaultInputDevice()
        if force || newOut != currentOutputID {
            currentOutputID = newOut
            addMuteListener(on: newOut, input: false)
        }
        if force || newIn != currentInputID {
            currentInputID = newIn
            addMuteListener(on: newIn, input: true)
        }
    }

    private func addMuteListener(on deviceID: AudioDeviceID, input: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        var addr = muteAddress(input: input)
        AudioObjectAddPropertyListenerBlock(deviceID, &addr, DispatchQueue.main) {
            [weak self] _, _ in self?.refresh()
        }
    }

    private func refresh() {
        let spk = readMute(deviceID: defaultOutputDevice(), input: false)
        let mic = readMute(deviceID: defaultInputDevice(),  input: true)
        guard spk != lastSpeaker || mic != lastMic else { return }
        lastSpeaker = spk; lastMic = mic
        NSLog("[MSIMuteLEDAgent] CoreAudio → EC: speaker=%d mic=%d",
              spk ? 1 : 0, mic ? 1 : 0)
        if client.setMuteState(speaker: spk, mic: mic) {
            lastSentSpeaker = spk; lastSentMic = mic
        }
    }

    // ── Helpers CoreAudio ────────────────────────────────────────────────────

    private func setAudioMute(deviceID: AudioDeviceID, input: Bool, muted: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        var value: UInt32 = muted ? 1 : 0
        var addr = muteAddress(input: input)
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil,
                                   UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func muteAddress(input: Bool) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope:    input ? kAudioDevicePropertyScopeInput
                             : kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain)
    }

    private func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz, &id)
        return id
    }

    private func defaultInputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz, &id)
        return id
    }

    private func readMute(deviceID: AudioDeviceID, input: Bool) -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var muted: UInt32 = 0
        var sz = UInt32(MemoryLayout<UInt32>.size)
        var addr = muteAddress(input: input)
        let kr = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &sz, &muted)
        return kr == noErr && muted != 0
    }
}

// ---------------------------------------------------------------------------
// MARK: – Point d'entrée
// ---------------------------------------------------------------------------

let ioClient = MSIMuteLEDClient()
let observer = MuteObserver(client: ioClient)
observer.start()
