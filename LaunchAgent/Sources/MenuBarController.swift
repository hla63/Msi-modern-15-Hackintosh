// MenuBarController.swift
//
// Status bar item, menu and preferences state.

import AppKit

// ---------------------------------------------------------------------------
// MARK: – Barre de menu
// ---------------------------------------------------------------------------

/// Reports when the status menu opens and closes. NSMenuDelegate requires
/// an NSObject, which MenuBarController is not; NSMenu.delegate is weak, so
/// MenuBarController keeps the strong reference.
final class MenuOpenTracker: NSObject, NSMenuDelegate {
    var onOpen:  (() -> Void)?
    var onClose: (() -> Void)?
    func menuWillOpen(_ menu: NSMenu) { onOpen?() }
    func menuDidClose(_ menu: NSMenu) { onClose?() }
}

final class MenuBarController {
    let menuTracker = MenuOpenTracker()
    var statusItem:  NSStatusItem!
    private var micItem:     NSMenuItem!
    private var speakerItem: NSMenuItem!
    private var camItem:     NSMenuItem!
    private var trackpadItem: NSMenuItem!
    private var rotItem:     NSMenuItem!
    private var cpuFanItem:  NSMenuItem!
    private var gpuFanItem:  NSMenuItem!
    // Nouveaux items — fan mode
    private var fanModeAutoItem:     NSMenuItem!
    private var fanModeSilentItem:   NSMenuItem!
    private var fanModeAdvItem:      NSMenuItem!
    // Cooler Boost + temp
    private var coolerBoostItem:     NSMenuItem!
    private var cpuTempItem:         NSMenuItem!
    // Dump EC
    private var ecDumpItem: NSMenuItem!
    // Batterie
    private var batteryLimitItem:         NSMenuItem!
    private(set) var currentBatteryLimit: UInt8 = 100
    // Rétroéclairage clavier
    private var kbBacklightOffItem:  NSMenuItem!
    private var kbBacklightLowItem:  NSMenuItem!
    private var kbBacklightMedItem:  NSMenuItem!
    private var kbBacklightHighItem: NSMenuItem!
    // Accessibilité (CGEventTap)
    private var accessibilityItem:     NSMenuItem!
    private var sepAfterAccessibility: NSMenuItem!

    // ── Préférences (types et clés : Preferences.swift) ──────────────────────
    // Lecture seule hors de cette classe : les modifier par les set…/tapPref…
    // ci-dessous, qui les enregistrent aussi dans UserDefaults.
    private(set) var prefIconStyle    = IconStyle.led
    private(set) var prefRotationMode = RotationMode.flip180
    private(set) var prefShowOSD      = true

    // ── Préférences — conditions de changement de couleur LED ────────────────
    // Vert  : aucun des états surveillés n'est actif
    // Orange: mic ou speaker muet (si surveillé)
    // Rouge : mic ET speaker muets (si surveillés), ou caméra coupée (si surveillée)
    private(set) var prefLEDWatchMic = true
    private(set) var prefLEDWatchSpk = true
    private(set) var prefLEDCamColor = CameraLEDColor.red

    // ── Préférences — sections visibles ──────────────────────────────────────
    private(set) var prefShowAudio      = true
    private(set) var prefShowMonitoring = true
    private(set) var prefShowFan        = true
    var prefShowBattery    = true
    var prefShowRotation   = true
    var prefShowBacklight  = true

    // Groupes d'items pour masquage/affichage
    private var audioItems:      [NSMenuItem] = []
    private var monitoringItems: [NSMenuItem] = []
    private var fanItems:        [NSMenuItem] = []
    private var batteryItems:    [NSMenuItem] = []
    private var rotationItems:   [NSMenuItem] = []
    private var backlightItems:  [NSMenuItem] = []

    // Séparateurs associés aux sections
    private var sepAfterAudio:     NSMenuItem!
    private var sepAfterMonitor:   NSMenuItem!
    private var sepAfterFan:       NSMenuItem!
    private var sepAfterBattery:   NSMenuItem!
    private var sepAfterRotation:  NSMenuItem!
    private var sepAfterBacklight: NSMenuItem!

    var onToggleMic:      (() -> Void)?
    var onToggleSpeaker:  (() -> Void)?
    var onToggleCamera:   (() -> Void)?
    var onToggleTrackpad: (() -> Void)?
    var onToggleRotation: (() -> Void)?
    var onSetFanMode:     ((FanMode)   -> Void)?
    var onToggleCoolerBoost:  (() -> Void)?
    var onToggleBatteryLimit: (() -> Void)?
    var onOpenFanCurve:       (() -> Void)?
    var onSetKbBacklight:   ((UInt8) -> Void)?
    var onRequestECDump:    (() -> Void)?
    var onRequestPreferences: (() -> Void)?
    private(set) var currentKbBacklightLevel: UInt8 = 0

    // État courant
    private var micMuted     = false
    private var speakerMuted = false
    var headphoneConnected = false  // mis à jour par MuteObserver.refresh()
    private var cameraActive = true
    var currentFanMode   = FanMode.auto_
    private var coolerBoostOn    = false
    var currentCoolerBoostOn: Bool { coolerBoostOn }

    func setup() {
        // Charger les préférences sauvegardées
        let ud = UserDefaults.standard
        prefIconStyle      = ud.pref(.iconStyle,    default: IconStyle.led)
        prefRotationMode   = ud.pref(.rotationMode, default: RotationMode.flip180)
        prefLEDCamColor    = ud.pref(.ledCamColor,  default: CameraLEDColor.red)
        prefShowOSD        = ud.bool(.showOSD,        default: true)
        prefLEDWatchMic    = ud.bool(.ledWatchMic,    default: true)
        prefLEDWatchSpk    = ud.bool(.ledWatchSpk,    default: true)
        prefShowAudio      = ud.bool(.showAudio,      default: true)
        prefShowMonitoring = ud.bool(.showMonitoring, default: true)
        prefShowFan        = ud.bool(.showFan,        default: true)
        prefShowBattery    = ud.bool(.showBattery,    default: true)
        prefShowRotation   = ud.bool(.showRotation,   default: true)
        prefShowBacklight  = ud.bool(.showBacklight,  default: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        buildMenu()

        // Forcer le premier dessin de l'icône après que le menu est prêt
        // Réinitialiser le cache pour que updateLED() ne soit pas bloqué par le guard
        lastLEDMic = !micMuted
        lastLEDSpk = !speakerMuted
        lastLEDCam = !cameraActive
        if prefIconStyle == .ec {
            statusItem.length = 28
            statusItem.button?.image = makeECBadgeImage()
            statusItem.button?.imageScaling = .scaleProportionallyDown
        } else {
            updateLED()
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        micItem     = makeItem(title: "Mic : Actif",        sfSymbol: "mic.fill",            action: #selector(tapMic))
        speakerItem = makeItem(title: "Speaker : Actif",    sfSymbol: "speaker.wave.2.fill",  action: #selector(tapSpeaker))
        camItem     = makeItem(title: "Caméra : Active",    sfSymbol: "camera.fill",          action: #selector(tapCamera))
        rotItem     = makeItem(title: "Rotation : 0°",      sfSymbol: "rotate.right.fill",    action: #selector(tapRotation))
        camItem.isEnabled = true
        trackpadItem = makeItem(title: "Trackpad : Actif", sfSymbol: "rectangle.and.hand.point.up.left.fill",
                                action: #selector(tapTrackpad))

        // Fans + température (lecture seule)
        cpuFanItem = makeItem(title: "CPU Fan : — RPM", sfSymbol: "cpu", action: nil)
        gpuFanItem = makeItem(title: "GPU Fan : — RPM", sfSymbol: "fan.fill", action: nil)
        cpuTempItem = makeItem(title: "CPU : — °C", sfSymbol: "thermometer.medium", action: nil)
        cpuFanItem.isEnabled  = false
        gpuFanItem.isEnabled  = false
        cpuTempItem.isEnabled = false

        // ── Mode ventilation ─────────────────────────────────────────────────
        let fanHeader = NSMenuItem(title: "Mode ventilation", action: nil, keyEquivalent: "")
        fanHeader.isEnabled = false
        fanModeAutoItem   = makeItem(title: FanMode.auto_.label,   sfSymbol: "fanblades",       action: #selector(tapFanAuto))
        fanModeSilentItem = makeItem(title: FanMode.silent.label,  sfSymbol: "fanblades.slash",  action: #selector(tapFanSilent))
        fanModeAdvItem    = makeItem(title: FanMode.advanced.label, sfSymbol: "slider.horizontal.3", action: #selector(tapFanAdvanced))
        updateFanModeItems(mode: .auto_)

        // Cooler Boost
        coolerBoostItem = makeItem(title: "Cooler Boost : OFF", sfSymbol: "flame", action: #selector(tapCoolerBoost))

        // ── Batterie ──────────────────────────────────────────────────────────
        batteryLimitItem = makeItem(title: "Charge : 100%", sfSymbol: "battery.100", action: #selector(tapBatteryLimit))

        // ── Avertissement Accessibilité (masqué tant que le tap fonctionne) ──
        accessibilityItem = NSMenuItem(title: "Touches Fn inactives — autoriser dans Accessibilité…",
                                       action: #selector(tapAccessibilityWarning), keyEquivalent: "")
        accessibilityItem.target = self
        accessibilityItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                          accessibilityDescription: nil)
        accessibilityItem.toolTip = "Retirer MSIECToolboxAgent de la liste (−) puis le ré-ajouter (+) : "
                                  + "après une réinstallation, cocher la case ne suffit pas."
        accessibilityItem.isHidden = true
        sepAfterAccessibility = NSMenuItem.separator()
        sepAfterAccessibility.isHidden = true
        menu.addItem(accessibilityItem)
        menu.addItem(sepAfterAccessibility)

        // ── Assemblage du menu ───────────────────────────────────────────────
        audioItems = [micItem, speakerItem, camItem, trackpadItem]
        menu.addItem(micItem)
        menu.addItem(speakerItem)
        menu.addItem(camItem)
        menu.addItem(trackpadItem)
        sepAfterAudio = NSMenuItem.separator()
        menu.addItem(sepAfterAudio)
        ecDumpItem = makeItem(title: "Table EC", sfSymbol: "tablecells", action: #selector(tapECDump))
        monitoringItems = [cpuFanItem, gpuFanItem, cpuTempItem, ecDumpItem]
        menu.addItem(cpuFanItem)
        menu.addItem(gpuFanItem)
        menu.addItem(cpuTempItem)
        menu.addItem(ecDumpItem)
        sepAfterMonitor = NSMenuItem.separator()
        menu.addItem(sepAfterMonitor)
        menu.addItem(fanHeader)
        menu.addItem(fanModeAutoItem)
        menu.addItem(fanModeSilentItem)
        let fanCurveItem = makeItem(title: "  Modifier la courbe...", sfSymbol: "waveform.path", action: #selector(tapFanCurve))
        fanCurveItem.indentationLevel = 1
        menu.addItem(fanModeAdvItem)
        menu.addItem(fanCurveItem)
        fanItems = [fanHeader, fanModeAutoItem, fanModeSilentItem, fanModeAdvItem, fanCurveItem, coolerBoostItem]
        menu.addItem(coolerBoostItem)
        sepAfterFan = NSMenuItem.separator()
        menu.addItem(sepAfterFan)
        batteryItems = [batteryLimitItem]
        menu.addItem(batteryLimitItem)
        sepAfterBattery = NSMenuItem.separator()
        menu.addItem(sepAfterBattery)
        rotationItems = [rotItem]
        menu.addItem(rotItem)
        sepAfterRotation = NSMenuItem.separator()
        menu.addItem(sepAfterRotation)

        // ── Rétroéclairage clavier ─────────────────────────────────────────────
        let kbHeader = NSMenuItem(title: "Rétroéclairage clavier", action: nil, keyEquivalent: "")
        kbHeader.isEnabled = false
        kbBacklightOffItem  = makeItem(title: "Off",    sfSymbol: "keyboard",      action: #selector(tapKbOff))
        kbBacklightLowItem  = makeItem(title: "Faible", sfSymbol: "keyboard",      action: #selector(tapKbLow))
        kbBacklightMedItem  = makeItem(title: "Moyen",  sfSymbol: "keyboard.fill", action: #selector(tapKbMed))
        kbBacklightHighItem = makeItem(title: "Élevé",  sfSymbol: "keyboard.fill", action: #selector(tapKbHigh))
        updateKbBacklightItems(level: 0)

        menu.addItem(kbHeader)
        menu.addItem(kbBacklightOffItem)
        menu.addItem(kbBacklightLowItem)
        menu.addItem(kbBacklightMedItem)
        backlightItems = [kbHeader, kbBacklightOffItem, kbBacklightLowItem, kbBacklightMedItem, kbBacklightHighItem]
        menu.addItem(kbBacklightHighItem)
        sepAfterBacklight = NSMenuItem.separator()
        menu.addItem(sepAfterBacklight)

        // ── Item Préférences → panel ─────────────────────────────────────
        let prefItem = makeItem(title: "Préférences...", sfSymbol: "gearshape", action: #selector(tapPreferences))
        prefItem.keyEquivalent = ","
        menu.addItem(prefItem)
        menu.addItem(NSMenuItem.separator())

        // Appliquer les préférences initiales
        applyVisibilityPrefs()

        let quit = makeItem(title: "Quitter MSIECToolbox", sfSymbol: "power", action: #selector(tapQuit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        menu.delegate = menuTracker
        statusItem.menu = menu
    }

    // ── LED dessinée programmatiquement ──────────────────────────────────────
    // Layout barre :
    //   Tout OK           → 🟢  (une LED verte)
    //   Un muet           → 🟠 mic|spk  (label du muet)
    //   Les deux muets    → 🔴  (une LED rouge, pas de label)
    //   + caméra active   → toujours + 🔴 cam  à droite

    private enum LEDColor { case green, orange, red, yellow }

    private func makeStatusImage() -> NSImage {
        if prefIconStyle == .ec {
            return makeECBadgeImage()
        }
        // Utiliser les variables watched* pour largeur ET rendu (cohérence avec les prefs)
        let watchedMicMuted = prefLEDWatchMic && micMuted
        let watchedSpkMuted = prefLEDWatchSpk && speakerMuted
        let watchedCamOff   = prefLEDCamColor != .ignored && !cameraActive

        let watchedBothMuted    = watchedMicMuted && watchedSpkMuted
        let watchedOnlyOneMuted = (watchedMicMuted || watchedSpkMuted) && !watchedBothMuted

        // Width = 42 only when an audio label (mic/spk/out) is needed.
        // Camera state uses color only (yellow/orange/red) — no label — so it
        // stays in the same 18x18 frame as the green/orange/red indicators.
        let width: CGFloat = watchedOnlyOneMuted ? 42 : 18
        let img = NSImage(size: CGSize(width: width, height: 18))
        img.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: 18)).fill()

        // ── Règles couleur LED ───────────────────────────────────────────
        // Rouge  : mic+spk muets ET (caméra off surveillée OU caméra .ignored)
        // Orange : un seul audio mauvais, OU caméra seule (couleur = pref caméra)
        // Vert   : aucun état mauvais

        let camNone   = prefLEDCamColor == .ignored
        let isRouge   = watchedBothMuted && (watchedCamOff || camNone)

        // Camera-only bad state: color encodes the severity (yellow/orange/red).
        // No text label — keeps the icon the same 18x18 size as other states.
        let camOnlyOff = watchedCamOff && !watchedMicMuted && !watchedSpkMuted

        let ledColor: LEDColor
        if isRouge {
            ledColor = .red
        } else if camOnlyOff {
            ledColor = (prefLEDCamColor == .yellow) ? .yellow
                     : (prefLEDCamColor == .orange) ? .orange : .red
        } else if watchedMicMuted || watchedSpkMuted || watchedCamOff {
            ledColor = .orange
        } else {
            ledColor = .green
        }

        drawLED(at: CGPoint(x: 9, y: 9), color: ledColor, label: nil)
        if watchedOnlyOneMuted {
            drawLabel(watchedMicMuted ? "mic" : (headphoneConnected ? "out" : "spk"), x: 18,
                      color: NSColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1.0))
        }

        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private func makeECBadgeImage() -> NSImage {
        // Valise contour + "EC" transparent + clé à molette à droite
        // isTemplate=true → couleur adaptée light/dark + vibrancy automatique
        let W: CGFloat = 24
        let H: CGFloat = 18
        let img = NSImage(size: CGSize(width: W, height: H))
        img.lockFocus()

        let lw: CGFloat = 1.1

        // ── Corps valise (contour uniquement, fond transparent) ───────────
        let bX: CGFloat = 1,  bY: CGFloat = 1.5
        let bW: CGFloat = 19, bH: CGFloat = 11
        let body = NSBezierPath(roundedRect: NSRect(x: bX, y: bY, width: bW, height: bH),
                                 xRadius: 2, yRadius: 2)
        NSColor.black.setStroke()
        body.lineWidth = lw
        body.stroke()

        // ── Poignée (arche au-dessus, contour uniquement) ─────────────────
        let hW: CGFloat = 7, hH: CGFloat = 3
        let hX = bX + (bW - hW) / 2
        let hY = bY + bH - 0.5
        let handle = NSBezierPath()
        handle.move(to: CGPoint(x: hX, y: hY))
        handle.appendArc(withCenter: CGPoint(x: hX + hW / 2, y: hY + hH / 2),
                         radius: hW / 2,
                         startAngle: 180, endAngle: 0,
                         clockwise: true)
        handle.line(to: CGPoint(x: hX + hW, y: hY))
        NSColor.black.setStroke()
        handle.lineWidth = lw
        handle.stroke()

        // ── Texte "EC" centré dans le corps ──────────────────────────────
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 7),
            .foregroundColor: NSColor.black
        ]
        let str = NSAttributedString(string: "EC", attributes: attrs)
        let sz = str.size()
        str.draw(at: CGPoint(x: bX + (bW - sz.width) / 2,
                             y: bY + (bH - sz.height) / 2))

        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private func drawLED(at center: CGPoint, color: LEDColor, label: String?) {
        let nsColor: NSColor
        switch color {
        case .green:  nsColor = NSColor(red: 0.2,  green: 0.85, blue: 0.3,  alpha: 1.0)
        case .orange: nsColor = NSColor(red: 1.0,  green: 0.6,  blue: 0.05, alpha: 1.0)
        case .red:    nsColor = NSColor(red: 1.0,  green: 0.2,  blue: 0.2,  alpha: 1.0)
        case .yellow: nsColor = NSColor(red: 0.95, green: 0.8,  blue: 0.0,  alpha: 1.0)
        }
        let rect = NSRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
        nsColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
        // Reflet
        NSColor.white.withAlphaComponent(0.45).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 3.5, y: center.y + 0.5, width: 3, height: 3)).fill()
        // Label interne optionnel
        if let label = label {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 8),
                .foregroundColor: NSColor.white
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let sz  = str.size()
            str.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
        }
    }

    private func drawLabel(_ text: String, x: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(at: CGPoint(x: x, y: 9 - str.size().height / 2))
    }

    // Cache de l'état précédent — évite de redessiner l'image
    // si l'état n'a pas changé (updateLED() peut être appelé très fréquemment)
    private var lastLEDMic     = false
    private var lastLEDSpk     = false
    private var lastLEDCam     = true

    func updateLED() {
        DispatchQueue.main.async {
            // Redessiner seulement si l'état a changé
            let wMic = self.prefLEDWatchMic && self.micMuted
            let wSpk = self.prefLEDWatchSpk && self.speakerMuted
            let wCam = self.prefLEDCamColor != .ignored && !self.cameraActive
            guard wMic != (self.prefLEDWatchMic && self.lastLEDMic) ||
                  wSpk != (self.prefLEDWatchSpk && self.lastLEDSpk) ||
                  wCam != (self.prefLEDCamColor != .ignored && !self.lastLEDCam) ||
                  self.micMuted     != self.lastLEDMic ||
                  self.speakerMuted != self.lastLEDSpk ||
                  self.cameraActive != self.lastLEDCam else { return }
            self.lastLEDMic = self.micMuted
            self.lastLEDSpk = self.speakerMuted
            self.lastLEDCam = self.cameraActive
            if self.prefIconStyle == .ec {
                self.statusItem.length = 28
            } else {
                let wm = self.prefLEDWatchMic && self.micMuted
                let ws = self.prefLEDWatchSpk && self.speakerMuted
                let watchedOne = (wm || ws) && !(wm && ws)
                self.statusItem.length = watchedOne ? 46 : 22
            }
            self.statusItem.button?.image = self.makeStatusImage()
            self.statusItem.button?.imageScaling = .scaleProportionallyDown
        }
    }

    // ── Mise à jour des items ─────────────────────────────────────────────────

    func updateMicItem(muted: Bool) {
        micMuted = muted
        DispatchQueue.main.async {
            self.micItem.title = muted ? "Mic : Muet" : "Mic : Actif"
            self.micItem.image = self.sfImage(muted ? "mic.slash.fill" : "mic.fill", muted: muted)
        }
        updateLED()
    }

    func updateSpeakerItem(muted: Bool, headphone: Bool = false) {
        speakerMuted = muted
        DispatchQueue.main.async {
            let label = headphone ? "Out" : "Speaker"
            self.speakerItem.title = muted ? "\(label) : Muet" : "\(label) : Actif"
            self.speakerItem.image = self.sfImage(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", muted: muted)
        }
        updateLED()
    }

    func updateTrackpadItem(enabled: Bool) {
        trackpadItem.title = enabled ? "Trackpad : Actif" : "Trackpad : Désactivé"
        trackpadItem.image = sfImage("rectangle.and.hand.point.up.left.fill", muted: !enabled)
    }

    func updateCameraItem(active: Bool) {
        cameraActive = active
        DispatchQueue.main.async {
            self.camItem.title = active ? "Caméra : Active" : "Caméra : Coupée"
            self.camItem.image = self.sfImage("camera.fill", muted: !active)
        }
        updateLED()
    }

    func updateRotItem(degree: Int) {
        DispatchQueue.main.async {
            self.rotItem.title = "Rotation : \(degree)°"
        }
    }

    func updateFanItems(cpuRPM: Int, gpuRPM: Int) {
        DispatchQueue.main.async {
            let cpuStr = cpuRPM > 0 ? "\(cpuRPM) RPM" : "Arrêté"
            let gpuStr = gpuRPM > 0 ? "\(gpuRPM) RPM" : "Arrêté"
            self.cpuFanItem.title = "CPU Fan : \(cpuStr)"
            self.gpuFanItem.title = "GPU Fan : \(gpuStr)"
        }
    }

    func updateCpuTemp(text: String) {
        DispatchQueue.main.async { self.cpuTempItem.title = text }
    }

    // Fields whose EC read failed (validMask bit cleared) keep their previous
    // value: showing them as 0 °C / Auto / Boost OFF would make the toggles
    // act on a state that was never read.
    func updateSystemState(state: MSISystemState) {
        DispatchQueue.main.async {
            // Température
            if state.isValid(MSIStateValid.cpuTemp) {
                let cpuStr = state.cpuTempC > 0 ? "\(state.cpuTempC) °C" : "—"
                self.cpuTempItem.title = "CPU : \(cpuStr)"
            }

            // Fan mode
            if state.isValid(MSIStateValid.fanMode) {
                let fm = FanMode(rawValue: state.fanMode) ?? .auto_
                if fm != self.currentFanMode {
                    self.currentFanMode = fm
                    self.updateFanModeItems(mode: fm)
                }
            }

            // Cooler Boost
            if state.isValid(MSIStateValid.coolerBoost) {
                self.updateCoolerBoostItem(on: state.coolerBoost != 0)
            }
        }
    }

    func updateCoolerBoostItem(on boost: Bool) {
        guard boost != coolerBoostOn else { return }
        coolerBoostOn = boost
        coolerBoostItem.title = "Cooler Boost : \(boost ? "ON 🔥" : "OFF")"
        coolerBoostItem.image = sfImage("flame", muted: boost)
    }

    func updateFanModeItems(mode: FanMode) {
        fanModeAutoItem.state   = (mode == .auto_)    ? .on : .off
        fanModeSilentItem.state = (mode == .silent)   ? .on : .off
        fanModeAdvItem.state    = (mode == .advanced) ? .on : .off
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func makeItem(title: String, sfSymbol: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image  = sfImage(sfSymbol, muted: false)
        return item
    }

    // Cache — évite de recréer l'image à chaque changement d'état
    private var sfImageCache: [String: NSImage] = [:]

    private func sfImage(_ name: String, muted: Bool) -> NSImage? {
        let key = "\(name)-\(muted)"
        if let cached = sfImageCache[key] { return cached }
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        if muted {
    
            guard let tinted = img.copy() as? NSImage else { return img }
            tinted.lockFocus()
            NSColor.systemRed.withAlphaComponent(0.85).set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.isTemplate = false
            sfImageCache[key] = tinted
            return tinted
        }
        img.isTemplate = true
        sfImageCache[key] = img
        return img
    }

    @objc private func tapMic()      { onToggleMic?() }
    @objc private func tapSpeaker()  { onToggleSpeaker?() }
    @objc private func tapCamera()   { onToggleCamera?() }
    @objc private func tapTrackpad() { onToggleTrackpad?() }
    @objc private func tapRotation() { onToggleRotation?() }
    @objc private func tapFanAuto()      { onSetFanMode?(.auto_) }
    @objc private func tapFanSilent()    { onSetFanMode?(.silent) }
    @objc private func tapFanAdvanced()  { onSetFanMode?(.advanced) }
    @objc private func tapBatteryLimit() { onToggleBatteryLimit?() }
    @objc private func tapFanCurve()     { onOpenFanCurve?() }


    @objc private func tapCoolerBoost()  { onToggleCoolerBoost?() }

    func updateBatteryLimitItem(percent: UInt8) {
        guard percent != currentBatteryLimit else { return }
        currentBatteryLimit = percent
        let sym = percent <= 80 ? "battery.50" : "battery.100"
        batteryLimitItem.title = "Charge : \(percent)%"
        batteryLimitItem.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)
    }

    // ── Backlight ──────────────────────────────────────────────────────────────

    func updateKbBacklightItems(level: UInt8) {
        currentKbBacklightLevel = level
        kbBacklightOffItem.state  = (level == 0) ? .on : .off
        kbBacklightLowItem.state  = (level == 1) ? .on : .off
        kbBacklightMedItem.state  = (level == 2) ? .on : .off
        kbBacklightHighItem.state = (level == 3) ? .on : .off
    }

    @objc private func tapKbOff()  { onSetKbBacklight?(0) }
    @objc private func tapKbLow()  { onSetKbBacklight?(1) }
    @objc private func tapKbMed()  { onSetKbBacklight?(2) }
    @objc private func tapKbHigh() { onSetKbBacklight?(3) }

    @objc private func tapECDump() { onRequestECDump?() }

    // ── Accessibilité ─────────────────────────────────────────────────────────

    /// Shown while the Fn keys cannot be intercepted (Accessibility not
    /// granted, or granted to a previous signature of the agent).
    func setAccessibilityWarning(_ visible: Bool) {
        guard accessibilityItem.isHidden == visible else { return }
        accessibilityItem.isHidden     = !visible
        sepAfterAccessibility.isHidden = !visible
    }

    @objc private func tapAccessibilityWarning() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func tapPreferences() { onRequestPreferences?() }
    @objc private func tapQuit()     {
        NSLog("[MSIECToolboxAgent] Quitter depuis la barre de menu")
        NSApp.terminate(nil)
    }

    // ── Préférences — visibilité des sections ────────────────────────────────

    private func applyVisibilityPrefs() {
        setSection(audioItems,      sep: sepAfterAudio,     visible: prefShowAudio)
        setSection(monitoringItems, sep: sepAfterMonitor,   visible: prefShowMonitoring)
        setSection(fanItems,        sep: sepAfterFan,       visible: prefShowFan)
        setSection(batteryItems,    sep: sepAfterBattery,   visible: prefShowBattery)
        setSection(rotationItems,   sep: sepAfterRotation,  visible: prefShowRotation)
        setSection(backlightItems,  sep: sepAfterBacklight, visible: prefShowBacklight)
    }

    private func setSection(_ items: [NSMenuItem], sep: NSMenuItem?, visible: Bool) {
        items.forEach { $0.isHidden = !visible }
        sep?.isHidden = !visible
    }

    private func togglePref(_ key: PrefKey, current: inout Bool, items: [NSMenuItem],
                             sep: NSMenuItem?) {
        current.toggle()
        UserDefaults.standard.set(current, for: key)
        setSection(items, sep: sep, visible: current)
    }

    @objc func tapPrefAudio() {
        togglePref(.showAudio, current: &prefShowAudio,
                   items: audioItems, sep: sepAfterAudio)
    }
    @objc func tapPrefMonitoring() {
        togglePref(.showMonitoring, current: &prefShowMonitoring,
                   items: monitoringItems, sep: sepAfterMonitor)
    }
    @objc func tapPrefFan() {
        togglePref(.showFan, current: &prefShowFan,
                   items: fanItems, sep: sepAfterFan)
    }
    @objc func tapPrefBattery() {
        togglePref(.showBattery, current: &prefShowBattery,
                   items: batteryItems, sep: sepAfterBattery)
    }
    @objc func tapPrefRotation() {
        togglePref(.showRotation, current: &prefShowRotation,
                   items: rotationItems, sep: sepAfterRotation)
    }
    @objc func tapPrefBacklight() {
        togglePref(.showBacklight, current: &prefShowBacklight,
                   items: backlightItems, sep: sepAfterBacklight)
    }

    @objc func tapPrefLEDMic() {
        prefLEDWatchMic.toggle()
        UserDefaults.standard.set(prefLEDWatchMic, for: .ledWatchMic)
        lastLEDMic = !micMuted; updateLED()
    }

    @objc func tapPrefLEDSpk() {
        prefLEDWatchSpk.toggle()
        UserDefaults.standard.set(prefLEDWatchSpk, for: .ledWatchSpk)
        lastLEDSpk = !speakerMuted; updateLED()
    }

    func setCameraLEDColor(_ color: CameraLEDColor) {
        prefLEDCamColor = color
        UserDefaults.standard.set(color, for: .ledCamColor)
        lastLEDCam = !cameraActive; updateLED()
    }

    func setRotationMode(_ mode: RotationMode) {
        prefRotationMode = mode
        UserDefaults.standard.set(mode, for: .rotationMode)
    }

    func toggleShowOSD() {
        prefShowOSD.toggle()
        UserDefaults.standard.set(prefShowOSD, for: .showOSD)
    }

    @objc func tapPrefIconLED() {
        prefIconStyle = .led
        UserDefaults.standard.set(IconStyle.led, for: .iconStyle)
        lastLEDMic = !micMuted  // forcer le redraw
        updateLED()
    }

    @objc func tapPrefIconEC() {
        prefIconStyle = .ec
        UserDefaults.standard.set(IconStyle.ec, for: .iconStyle)
        statusItem.length = 28
        statusItem.button?.image = makeECBadgeImage()
        statusItem.button?.imageScaling = .scaleProportionallyDown
    }

}
