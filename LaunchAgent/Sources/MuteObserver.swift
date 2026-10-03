// MuteObserver.swift
//
// Application delegate: CGEventTap (Fn keys), CoreAudio mute sync,
// EC polling, rotation, and the actions behind the menu items.

import AppKit
import ApplicationServices
import CoreAudio
import IOKit

// ---------------------------------------------------------------------------
// MARK: – Touches Fn (keycodes produits par ACPI/SSDT-MSI-KEY_FIX.dsl)
// ---------------------------------------------------------------------------

private let kMicKeyCode:        CGKeyCode = 79  // F5 mute mic    (e071→ADB 4f)
private let kRotationKeyCode:   CGKeyCode = 111 // F12 rotation   (e072→ADB 6f)
private let kCameraKeyCode:     CGKeyCode = 80  // F6 caméra      (e06e→ADB 50, F19) — was 118 = standard F4
private let kBacklightKeyCode:  CGKeyCode = 100 // F8 backlight   (keycode standard macOS)
private let kTouchpadKeyCode:   CGKeyCode = 90  // F4 trackpad (Ctrl+Win+F24, PS2 76→ADB 5a, F20)

// ---------------------------------------------------------------------------
// MARK: – Observateur principal
// ---------------------------------------------------------------------------

final class MuteObserver: NSObject, NSApplicationDelegate {

    private let client:  MSIECToolboxClient
    private let menuBar: MenuBarController

    // Last mute state successfully written to the kext. refresh() compares
    // CoreAudio with it to avoid sending the same state twice; applyPoll()
    // compares the EC LEDs with it (see "Mute sync direction" in CLAUDE.md).
    // Not updated when setMuteState fails, so the next CoreAudio change retries.
    private var lastSentSpeaker = false
    private var lastSentMic     = false

    private var rotationInProgress = false
    private var displayObserver:   NSObjectProtocol?
    private let kDisplayID         = "CC868235-2DF0-05C3-7FEE-80DFD78D701F"

    private var currentOutputID: AudioDeviceID = AudioDeviceID(kAudioObjectUnknown)
    private var currentInputID:  AudioDeviceID = AudioDeviceID(kAudioObjectUnknown)

    private var pollTimer:   DispatchSourceTimer?
    private var eventTap:    CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var lastCamState = false  // mis à jour par pollEC() via EC 0x2E

    init(client: MSIECToolboxClient, menuBar: MenuBarController) {
        self.client  = client
        self.menuBar = menuBar
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.setup()
        menuBar.onToggleMic      = { [weak self] in self?.toggleMicMute() }
        menuBar.onToggleSpeaker  = { [weak self] in self?.toggleSpeakerMute() }
        menuBar.onToggleCamera   = { [weak self] in self?.toggleCameraState() }
        menuBar.onToggleTrackpad = { [weak self] in self?.toggleTrackpad() }
        menuBar.onToggleRotation = { [weak self] in self?.toggleDisplayRotation() }
        menuBar.onSetFanMode     = { [weak self] mode   in self?.setFanMode(mode) }
        menuBar.onSetKbBacklight    = { [weak self] level  in self?.setKbBacklight(level) }
        menuBar.onRequestECDump     = { [weak self] in self?.showECDump() }
        menuBar.onRequestPreferences = { [weak self] in self?.showPreferences() }
        menuBar.onToggleBatteryLimit = { [weak self] in self?.toggleBatteryLimit() }
        menuBar.onOpenFanCurve       = { [weak self] in self?.openFanCurvePanel() }
        menuBar.onToggleCoolerBoost = { [weak self] in self?.toggleCoolerBoost() }

        client.run({ c -> (kb: UInt8?, battery: UInt8?, trackpad: Bool?) in
            _ = c.connect()
            return (c.getKbBacklight(), c.getBatteryCharge(), c.setTouchpad(.query))
        }) { [weak self] initial in
            guard let self = self else { return }
            if let lvl = initial.kb       { self.menuBar.updateKbBacklightItems(level: lvl) }
            if let pct = initial.battery  { self.menuBar.updateBatteryLimitItem(percent: pct) }
            if let on  = initial.trackpad { self.menuBar.updateTrackpadItem(enabled: on) }
            // Menu and LEDs follow CoreAudio from the start, not only after
            // its first change. Queued before the first poll, so the poll
            // reads the LEDs already written.
            self.refresh()
        }
        client.watchService(
            onConnect:    { [weak self] in self?.refresh() },
            onDisconnect: { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.menuBar.updateFanItems(cpuRPM: 0, gpuRPM: 0)
                    self.menuBar.updateCpuTemp(text: "CPU : kext non chargé")
                }
                NSLog("[MSIECToolboxAgent] ⚠️ kext déconnecté — LEDs et fan désactivés")
            })
        // Rotation shown from the real display state, also when it changes
        // outside the agent (System Settings, another tool, agent restart).
        syncRotationItem()
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.syncRotationItem() }
        installDeviceChangeListeners()
        installMuteListeners(force: true)
        startECPolling()
        installKeyEventTap()

        NSLog("[MSIECToolboxAgent] Démarré v4.3.0 – barre de menu + CGEventTap + polling EC")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Supprimer le fichier PID : un PID recyclé ne doit pas être pris pour l'agent.
        try? FileManager.default.removeItem(atPath: pidFile)
        pollTimer?.cancel()
        accessibilityRetryTimer?.cancel()
        tapWatchdogTimer?.cancel()
        if let obs = screenObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = displayObserver { NotificationCenter.default.removeObserver(obs) }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes); eventTapSource = nil }
        client.stopWatching()
        client.queue.sync { client.disconnect() }
        NSLog("[MSIECToolboxAgent] Arrêté proprement")
    }

    // ── CGEventTap unique ────────────────────────────────────────────────────

    // Évite de journaliser deux fois l'absence d'autorisation Accessibilité
    private var accessibilityNotificationSent = false

    private func handleAccessibilityFailure() {
        if !accessibilityNotificationSent {
            accessibilityNotificationSent = true
            postAccessibilityNotification()
        }
        menuBar.setAccessibilityWarning(true)
        scheduleAccessibilityRetry()
    }

    private func installKeyEventTap() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary)

        if !trusted {
            NSLog("[MSIECToolboxAgent] ⚠️ Accessibilité non autorisée — tap clavier inactif")
            handleAccessibilityFailure()
            return
        }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap:              .cghidEventTap,
            place:            .headInsertEventTap,
            options:          .defaultTap,
            eventsOfInterest: debugKeys
                ? CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.flagsChanged.rawValue)
                : CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                // macOS disables the tap on Secure Input (auth dialogs) or when
                // the main run loop was too slow to answer (e.g. during a
                // display reconfiguration). This notification only arrives
                // with the next event, which is lost to us: the watchdog and
                // the screen-change observer re-enable the tap earlier.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    let me = Unmanaged<MuteObserver>.fromOpaque(userInfo!).takeUnretainedValue()
                    me.reenableTapIfNeeded(reason: type == .tapDisabledByTimeout
                                           ? "timeout" : "saisie sécurisée")
                    return nil
                }
                // passUnretained : le callback ne possède pas l'événement —
                // passRetained ajouterait un +1 jamais relâché (fuite d'un
                // CGEvent par frappe clavier système).
                let me = Unmanaged<MuteObserver>.fromOpaque(userInfo!).takeUnretainedValue()
                if me.debugKeys {
                    NSLog("[MSIECToolboxAgent] [debug_keys] type=%u keycode=%lld flags=0x%llX",
                          type.rawValue, event.getIntegerValueField(.keyboardEventKeycode),
                          event.flags.rawValue)
                }
                guard type == .keyDown else { return Unmanaged.passUnretained(event) }
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                switch CGKeyCode(keyCode) {
                case kMicKeyCode:
                    NSLog("[MSIECToolboxAgent] F5 (keycode 79) intercepté → toggle mic mute")
                    me.toggleMicMute()
                    return nil
                case kRotationKeyCode:
                    NSLog("[MSIECToolboxAgent] F12 (keycode 111) intercepté → toggle rotation écran")
                    me.toggleDisplayRotation()
                    return nil
                case kCameraKeyCode:
                    NSLog("[MSIECToolboxAgent] F6 (keycode 80) intercepté → toggle caméra")
                    me.toggleCameraState()
                    return nil
                case kTouchpadKeyCode:
                    // Arrives with Control+Command held (the hotkey's Ctrl+Win);
                    // only the key itself is swallowed, the modifiers pass through.
                    NSLog("[MSIECToolboxAgent] F4 (keycode 90) intercepté → toggle trackpad")
                    me.toggleTrackpad()
                    return nil
                case kBacklightKeyCode:
                    NSLog("[MSIECToolboxAgent] F8 (keycode 100) intercepté → toggle rétroéclairage clavier")
                    me.toggleKbBacklight()
                    return nil
                default:
                    return Unmanaged.passUnretained(event)
                }
            },
            userInfo: ctx)
        else {
            NSLog("[MSIECToolboxAgent] CGEventTap échoué — vérifier autorisation Accessibilité")
            handleAccessibilityFailure()
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapSource = source
        menuBar.setAccessibilityWarning(false)
        startTapWatchdog()
        NSLog("[MSIECToolboxAgent] CGEventTap installé — F4(90) + F5(79) + F6(80) + F8(100) + F12(111)")
    }

    // ── Tap watchdog ─────────────────────────────────────────────────────────
    //
    // A disabled tap lets the next Fn key through unhandled. Rotating to
    // 90°/270° is the heaviest display reconfiguration and makes the tap time
    // out, so the first F12 press after it was swallowed (holding the key
    // only worked thanks to auto-repeat). Re-enable as soon as the screen
    // configuration changes, and poll every 2 s as a safety net. The same
    // timer notices a permission revoked or invalidated by a new signature.

    private var tapWatchdogTimer: DispatchSourceTimer?

    // Opt-in diagnostic, to identify keys macOS does not handle (e.g. the
    // MSI touchpad key): logs every key event while enabled, so it is a
    // keylogger in the unified log — keep it off outside a short test.
    //   defaults write MSIECToolboxAgent debug_keys -bool true   (then restart the agent)
    fileprivate let debugKeys = UserDefaults.standard.bool(forKey: "debug_keys")
    private var screenObserver: NSObjectProtocol?

    fileprivate func reenableTapIfNeeded(reason: String) {
        guard let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[MSIECToolboxAgent] CGEventTap réactivé (%@)", reason)
    }

    private func startTapWatchdog() {
        guard tapWatchdogTimer == nil else { return }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.reenableTapIfNeeded(reason: "changement d'écran")
            }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.reenableTapIfNeeded(reason: "watchdog")
            self.menuBar.setAccessibilityWarning(!AXIsProcessTrusted())
        }
        timer.resume()
        tapWatchdogTimer = timer
    }

    // ── Notification Accessibilité ───────────────────────────────────────────

    private func postAccessibilityNotification() {
        // Log + avertissement dans le menu (setAccessibilityWarning) — pas
        // d'ouverture automatique de Réglages Système.
        NSLog("[MSIECToolboxAgent] ⚠️  Accessibilité non accordée — tap clavier désactivé")
        NSLog("[MSIECToolboxAgent]    Pour activer les touches Fn : Réglages Système > Confidentialité > Accessibilité")
    }

    // Réessaie toutes les 10s jusqu'à ce que l'autorisation soit accordée
    private var accessibilityRetryTimer: DispatchSourceTimer?

    private func scheduleAccessibilityRetry() {
        guard accessibilityRetryTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self = self, AXIsProcessTrusted() else { return }
            NSLog("[MSIECToolboxAgent] ✅ Accessibilité accordée — installation du tap")
            self.accessibilityRetryTimer?.cancel()
            self.accessibilityRetryTimer = nil
            self.installKeyEventTap()
        }
        timer.resume()
        accessibilityRetryTimer = timer
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    private func toggleMicMute() {
        let deviceID = defaultInputDevice()
        guard deviceID != kAudioObjectUnknown else {
            NSLog("[MSIECToolboxAgent] toggleMicMute : aucun périphérique d'entrée (entitlement audio-input / autorisation Micro ?)")
            return
        }
        let current = readMute(deviceID: deviceID, input: true)
        let newMuted = !current
        setAudioMute(deviceID: deviceID, input: true, muted: newMuted)
        if menuBar.prefShowOSD {
            DispatchQueue.main.async {
                MuteOSD.show(muted: newMuted, isMic: true)
            }
        }
    }

    private func toggleSpeakerMute() {
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }
        let current = readMute(deviceID: deviceID, input: false)
        setAudioMute(deviceID: deviceID, input: false, muted: !current)
    }

    // ── Rotation écran ───────────────────────────────────────────────────────
    //
    // The real rotation (CGDisplayRotation) is the only source of truth: the
    // next angle is computed from it and the menu always shows it. The
    // displayplacer exit code is not used — it rotates first, then looks up
    // `res:` in the new orientation, so a resolution miss returns 1 even
    // though the screen did turn.

    /// Internal panel (kDisplayID is its UUID, used for displayplacer), else the main display.
    private func rotationDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    /// Current rotation of the internal panel, normalised to 0/90/180/270.
    private func actualRotation() -> Int? {
        guard let id = rotationDisplayID() else { return nil }
        let deg = (Int(CGDisplayRotation(id).rounded()) % 360 + 360) % 360
        return (deg / 90) * 90
    }

    private func syncRotationItem() {
        if let deg = actualRotation() { menuBar.updateRotItem(degree: deg) }
    }

    private func toggleDisplayRotation() {
        // One rotation at a time: a held F12 (auto-repeat) or impatient
        // presses must not start several displayplacer runs on top of a
        // display reconfiguration.
        guard !rotationInProgress else {
            NSLog("[MSIECToolboxAgent] Rotation déjà en cours — appui ignoré")
            return
        }
        guard let current = actualRotation() else {
            NSLog("[MSIECToolboxAgent] Rotation : écran interne introuvable")
            return
        }
        let target = menuBar.prefRotationMode == .cycle90
            ? (current + 90) % 360
            : (current == 0 ? 180 : 0)
        // displayplacer matches res: after rotating, i.e. in the target orientation.
        let res = (target == 90 || target == 270) ? "1080x1920" : "1920x1080"
        let spec = "id:\(kDisplayID) res:\(res) color_depth:4 enabled:true scaling:off origin:(0,0) degree:\(target)"
        NSLog("[MSIECToolboxAgent] Rotation écran %d° → %d°", current, target)

        rotationInProgress = true
        // Exécution sur thread background pour ne pas geler la barre de menu
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let finish: (String?) -> Void = { problem in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.rotationInProgress = false
                    if let problem = problem { NSLog("[MSIECToolboxAgent] Rotation : %@", problem) }
                    let actual = self.actualRotation()
                    if let actual = actual, actual != target {
                        NSLog("[MSIECToolboxAgent] Rotation demandée %d°, écran à %d°", target, actual)
                    }
                    self.syncRotationItem()
                }
            }

            let path = "/usr/local/bin/displayplacer"
            guard FileManager.default.isExecutableFile(atPath: path) else {
                finish("\(path) introuvable (brew install displayplacer)")
                return
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = [spec]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError  = pipe
            do {
                try task.run()
            } catch {
                // terminationStatus on a process that never ran raises an
                // Objective-C exception and kills the agent.
                finish("lancement impossible : \(error.localizedDescription)")
                return
            }
            // Drain the pipe before waiting so a large output cannot block the child.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !out.isEmpty { NSLog("[MSIECToolboxAgent] displayplacer: %@", out) }
            NSLog("[MSIECToolboxAgent] displayplacer terminé (exit=%d)", task.terminationStatus)
            finish(nil)
        }
    }

    // ── Toggle caméra — simule F6 pour piloter le firmware MSI ──────────────
    //
    // Every kext call below goes through client.run: the IOKit call runs on
    // the EC queue and the result comes back on main. The CGEventTap calls
    // these actions directly, so they must never block.

    private func toggleCameraState() {
        let newState = !lastCamState  // lastCamState = cameraOff (true = coupée)
        client.run({ $0.setCameraState(cameraOff: newState) }) { [weak self] ok in
            guard let self = self else { return }
            if ok {
                NSLog("[MSIECToolboxAgent] setCameraState → cameraOff=%d", newState ? 1 : 0)
                self.lastCamState = newState
                self.menuBar.updateCameraItem(active: !newState)
                if self.menuBar.prefShowOSD {
                    MuteOSD.show(muted: newState, isMic: false, isCam: true)
                }
            } else {
                NSLog("[MSIECToolboxAgent] setCameraState échoué — kext non connecté ?")
            }
        }
    }

    // ── Trackpad (VoodooI2C / VoodooPS2, through the kext) ───────────────────

    private func toggleTrackpad() {
        client.run({ $0.setTouchpad(.toggle) }) { [weak self] enabled in
            guard let self = self else { return }
            guard let enabled = enabled else {
                NSLog("[MSIECToolboxAgent] Trackpad : bascule impossible (kext ou driver trackpad indisponible)")
                return
            }
            NSLog("[MSIECToolboxAgent] Trackpad → %@", enabled ? "actif" : "désactivé")
            self.menuBar.updateTrackpadItem(enabled: enabled)
            if self.menuBar.prefShowOSD {
                MuteOSD.show(muted: !enabled, isMic: false, isTrackpad: true)
            }
        }
    }

    // ── Fan mode, shift mode, cooler boost ───────────────────────────────────

    private func setFanMode(_ mode: FanMode) {
        client.run({ $0.setFanMode(mode) }) { ok in
            if ok { NSLog("[MSIECToolboxAgent] setFanMode → %@", mode.label) }
            // pollEC() confirmera le mode dans 500ms via getSystemState
        }
    }

    private func setKbBacklight(_ level: UInt8) {
        client.run({ $0.setKbBacklight(level: level) }) { [weak self] ok in
            if ok {
                NSLog("[MSIECToolboxAgent] setKbBacklight → %d", level)
                self?.menuBar.updateKbBacklightItems(level: level)
            } else {
                NSLog("[MSIECToolboxAgent] setKbBacklight %d — kext non connecté", level)
            }
        }
    }

    private func toggleKbBacklight() {
        // Read the current level from the EC in the same queue operation as
        // the write: it is not polled while the menu is closed, and the
        // firmware may have changed it.
        let cached = menuBar.currentKbBacklightLevel
        client.run({ c -> UInt8? in
            let next = ((c.getKbBacklight() ?? cached) + 1) % 4  // cycle 0→1→2→3→0
            return c.setKbBacklight(level: next) ? next : nil
        }) { [weak self] next in
            guard let next = next else {
                NSLog("[MSIECToolboxAgent] toggleKbBacklight — kext non connecté")
                return
            }
            NSLog("[MSIECToolboxAgent] toggleKbBacklight → %d", next)
            self?.menuBar.updateKbBacklightItems(level: next)
        }
    }

    private func showPreferences() {
        DispatchQueue.main.async {
            PreferencesPanel.show(controller: self.menuBar)
        }
    }

    private func showECDump() {
        let fetcher: ECDumpFetcher = { [weak self] done in
            guard let self = self else { done(nil); return }
            self.client.run({ $0.dumpEC() }, done: done)
        }
        DispatchQueue.main.async {
            ECDumpPanel.show(fetcher: fetcher)
        }
    }

    private func toggleBatteryLimit() {
        let current = menuBar.currentBatteryLimit
        let next: UInt8 = (current <= 80) ? 100 : 80
        client.run({ $0.setBatteryCharge(percent: next) }) { [weak self] ok in
            if ok {
                NSLog("[MSIECToolboxAgent] setBatteryCharge → %d%%", next)
                self?.menuBar.updateBatteryLimitItem(percent: next)
            } else {
                NSLog("[MSIECToolboxAgent] setBatteryCharge — kext non connecté")
            }
        }
    }

    private func openFanCurvePanel() {
        // Only read the current curve here: switching to Advanced mode waits
        // for "Appliquer", so closing the editor leaves the fan mode as is.
        client.run({ $0.getFanCurve() }) { [weak self] curve in
            guard self != nil else { return }
            FanCurvePanel.show(current: curve ?? MSIFanCurve()) { [weak self] newCurve, done in
                guard let self = self else { done(false); return }
                // The curve is only used in Advanced mode: write it first,
                // then switch, so the EC never runs Advanced on a stale curve.
                self.client.run({ c -> Bool in
                    guard c.setFanCurve(newCurve) else { return false }
                    return c.setFanMode(.advanced)
                }) { [weak self] ok in
                    NSLog(ok ? "[MSIECToolboxAgent] setFanCurve applied (mode Avancé)"
                             : "[MSIECToolboxAgent] setFanCurve failed — refusée par le kext ou kext non connecté")
                    if ok {
                        self?.menuBar.currentFanMode = .advanced
                        self?.menuBar.updateFanModeItems(mode: .advanced)
                    }
                    done(ok)
                }
            }
        }
    }

    private func toggleCoolerBoost() {
        let newState = !(menuBar.currentCoolerBoostOn)
        client.run({ $0.setCoolerBoost(newState) }) { [weak self] ok in
            guard ok else { return }
            NSLog("[MSIECToolboxAgent] coolerBoost → %@", newState ? "ON" : "OFF")
            self?.menuBar.updateCoolerBoostItem(on: newState)
        }
    }

    // ── Polling EC — adaptive ────────────────────────────────────────────────
    //
    // Menu closed: only the mute LEDs and the camera (getAllState, 3 EC reads)
    // once per second — all the status icon shows, and what the EC -> CoreAudio
    // mute sync needs. Menu open: an immediate refresh, then everything the
    // menu shows every 500 ms (backlight, temperatures, modes) and the fan RPM
    // every 2 s. About 3 EC reads/s instead of 24 most of the time.
    //
    // The timer fires on the EC queue (blocking reads) and hands a snapshot
    // to the main queue, where all agent state lives. pollFull and
    // rpmCountdown are only touched on client.queue.

    private enum PollInterval {
        static let menuClosed: DispatchTimeInterval = .seconds(1)
        static let menuOpen:   DispatchTimeInterval = .milliseconds(500)
        static let rpmEvery    = 4  // menu-open ticks between RPM / charge limit reads (2 s)
    }

    private struct PollSnapshot {
        let mute:      (micMuted: Bool, speakerMuted: Bool, cameraOff: Bool)?
        let backlight: UInt8?
        let system:    MSISystemState?
        let rpm:       (cpuRPM: Int, gpuRPM: Int)?
        let battery:   UInt8?  // can change behind the agent (BCLM via SMCMSIFan)
    }

    private var pollFull     = false  // client.queue only
    private var rpmCountdown = 0      // client.queue only

    private func startECPolling() {
        let timer = DispatchSource.makeTimerSource(queue: client.queue)
        timer.schedule(deadline: .now() + PollInterval.menuClosed,
                       repeating: PollInterval.menuClosed, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let full = self.pollFull
            var rpm: (cpuRPM: Int, gpuRPM: Int)? = nil
            var battery: UInt8? = nil
            if full {
                if self.rpmCountdown <= 0 {
                    rpm     = self.client.readFanRPM()
                    battery = self.client.getBatteryCharge()
                    self.rpmCountdown = PollInterval.rpmEvery
                }
                self.rpmCountdown -= 1
            }
            let snap = PollSnapshot(mute:      self.client.readECMuteState(),
                                    backlight: full ? self.client.getKbBacklight()  : nil,
                                    system:    full ? self.client.readSystemState() : nil,
                                    rpm:       rpm,
                                    battery:   battery)
            DispatchQueue.main.async { self.applyPoll(snap) }
        }
        timer.resume()
        pollTimer = timer

        menuBar.menuTracker.onOpen  = { [weak self] in self?.setPollMode(menuOpen: true) }
        menuBar.menuTracker.onClose = { [weak self] in self?.setPollMode(menuOpen: false) }
    }

    private func setPollMode(menuOpen: Bool) {
        // Queued before the reschedule below: the next tick (immediate when
        // the menu opens) already sees the new mode.
        client.queue.async { [weak self] in
            self?.pollFull     = menuOpen
            self?.rpmCountdown = 0
        }
        let interval = menuOpen ? PollInterval.menuOpen : PollInterval.menuClosed
        pollTimer?.schedule(deadline: menuOpen ? .now() : .now() + interval,
                            repeating: interval, leeway: .milliseconds(menuOpen ? 100 : 200))
    }

    private func applyPoll(_ snap: PollSnapshot) {
        // ── Mute / caméra via MSIAllState (sélecteur kMSIGetAllState) ──────
        if let mute = snap.mute {
            // EC → CoreAudio only in the muting direction. Any local process
            // can write the LED bits through the kext; following an EC
            // "unmuted" would let it switch the microphone back on behind the
            // user's back. An EC that reads unmuted while we last sent muted
            // gets the LED rewritten instead.
            if mute.speakerMuted && !lastSentSpeaker {
                setAudioMute(deviceID: defaultOutputDevice(), input: false, muted: true)
                lastSentSpeaker = true
                NSLog("[MSIECToolboxAgent] EC poll → speaker muet")
            }
            if mute.micMuted && !lastSentMic {
                setAudioMute(deviceID: defaultInputDevice(), input: true, muted: true)
                lastSentMic = true
                NSLog("[MSIECToolboxAgent] EC poll → mic muet")
            }
            if (!mute.speakerMuted && lastSentSpeaker) || (!mute.micMuted && lastSentMic) {
                let spk = lastSentSpeaker, mic = lastSentMic
                NSLog("[MSIECToolboxAgent] LED mute effacée hors agent — réécriture")
                client.run({ $0.setMuteState(speaker: spk, mic: mic) })
            }
            if mute.cameraOff != lastCamState {
                lastCamState = mute.cameraOff
                NSLog("[MSIECToolboxAgent] EC camera: %@", lastCamState ? "coupée" : "active")
                menuBar.updateCameraItem(active: !lastCamState)
            }
        }

        // ── Rétroéclairage clavier — sync si changé par firmware (Fn+F8) ──────
        if let lvl = snap.backlight, lvl != menuBar.currentKbBacklightLevel {
            menuBar.updateKbBacklightItems(level: lvl)
        }

        // ── Fan / température / modes via MSISystemState (sélecteur kMSIGetSystemState) ──
        if let sys = snap.system {
            menuBar.updateSystemState(state: sys)
        }
        if let rpm = snap.rpm {
            menuBar.updateFanItems(cpuRPM: rpm.cpuRPM, gpuRPM: rpm.gpuRPM)
        }
        if let pct = snap.battery {
            menuBar.updateBatteryLimitItem(percent: pct)
        }
    }

    // ── CoreAudio → EC ───────────────────────────────────────────────────────

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

    // Blocs listeners conservés pour pouvoir les retirer avant d'en ajouter
    // de nouveaux quand le périphérique audio par défaut change.
    private var outMuteListenerBlock: AudioObjectPropertyListenerBlock?
    private var inMuteListenerBlock:  AudioObjectPropertyListenerBlock?

    private func installMuteListeners(force: Bool) {
        let newOut = defaultOutputDevice()
        let newIn  = defaultInputDevice()
        if force || newOut != currentOutputID {
            // Retirer l'ancien listener
            if currentOutputID != kAudioObjectUnknown,
               let old = outMuteListenerBlock {
                var addr = muteAddress(input: false)
                AudioObjectRemovePropertyListenerBlock(currentOutputID, &addr,
                                                       DispatchQueue.main, old)
            }
            currentOutputID = newOut
            if newOut != kAudioObjectUnknown {
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
                outMuteListenerBlock = block
                var addr = muteAddress(input: false)
                AudioObjectAddPropertyListenerBlock(newOut, &addr, DispatchQueue.main, block)
            }
        }
        if force || newIn != currentInputID {
            if currentInputID != kAudioObjectUnknown,
               let old = inMuteListenerBlock {
                var addr = muteAddress(input: true)
                AudioObjectRemovePropertyListenerBlock(currentInputID, &addr,
                                                       DispatchQueue.main, old)
            }
            currentInputID = newIn
            if newIn != kAudioObjectUnknown {
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
                inMuteListenerBlock = block
                var addr = muteAddress(input: true)
                AudioObjectAddPropertyListenerBlock(newIn, &addr, DispatchQueue.main, block)
            }
        }
    }

    private func refresh() {
        let spk        = readMute(deviceID: defaultOutputDevice(), input: false)
        let mic        = readMute(deviceID: defaultInputDevice(),  input: true)
        let headphone  = isHeadphoneConnected()
        menuBar.headphoneConnected = headphone
        menuBar.updateMicItem(muted: mic)
        menuBar.updateSpeakerItem(muted: spk, headphone: headphone)
        guard spk != lastSentSpeaker || mic != lastSentMic else { return }
        NSLog("[MSIECToolboxAgent] CoreAudio → EC: speaker=%d mic=%d",
              spk ? 1 : 0, mic ? 1 : 0)
        // The EC queue is serial: a poll queued after this write reads the
        // new LED state, and its result reaches main after lastSent* is set.
        client.run({ $0.setMuteState(speaker: spk, mic: mic) }) { [weak self] ok in
            if ok { self?.lastSentSpeaker = spk; self?.lastSentMic = mic }
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

    // Retourne true si des écouteurs (ou tout périphérique de sortie externe)
    // sont branchés sur la prise jack. Détection via kAudioDevicePropertyDataSource :
    //   'hdpn' (0x6864706E) = Headphones
    //   'ispk' (0x6973706B) = Internal Speaker
    // Si la source courante est 'hdpn', on affiche "Out" au lieu de "Spk".
    private func isHeadphoneConnected() -> Bool {
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return false }
        var source: UInt32 = 0
        var sz = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &sz, &source)
        guard status == noErr else { return false }
        // 'hdpn' = 0x6864706E — source headphone jack
        return source == 0x6864706E
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
