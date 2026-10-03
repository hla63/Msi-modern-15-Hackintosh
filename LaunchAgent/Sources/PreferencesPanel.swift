// PreferencesPanel.swift
//
// Preferences window.

import AppKit

// ---------------------------------------------------------------------------
// MARK: – Fenêtre Préférences
// ---------------------------------------------------------------------------

final class PreferencesPanel: NSObject {

    // Lazily created on first open and kept for the agent's lifetime
    static var shared: PreferencesPanel?
    private var panel: NSPanel!
    private weak var controller: MenuBarController?

    static func show(controller: MenuBarController) {
        if shared == nil { shared = PreferencesPanel() }
        shared!.controller = controller
        shared!.reload()
        shared!.panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private override init() {
        super.init()
        buildPanel()
    }

    // Références aux checkboxes pour reload()
    private var cbAudio:      NSButton!
    private var cbOSD:        NSButton!
    private var cbMonitor:    NSButton!
    private var cbFan:        NSButton!
    private var cbBattery:    NSButton!
    private var cbRotation:   NSButton!
    private var cbBacklight:  NSButton!
    private var cbLEDMic:     NSButton!
    private var cbLEDSpk:     NSButton!
    private var rbCamRouge:   NSButton!
    private var rbCamOrange:  NSButton!
    private var rbCamJaune:   NSButton!
    private var rbCamNone:    NSButton!
    private var rbLED:        NSButton!
    private var rbEC:         NSButton!
    private var rbRot180:     NSButton!
    private var rbRotCycle:   NSButton!

    private func buildPanel() {
        let W: CGFloat = 320
        let H: CGFloat = 560

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask:   [.titled, .closable, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.title = "Préférences — MSIECToolbox"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.center()

        let root = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        panel.contentView = root

        var y = H - 20

        func sectionLabel(_ text: String) {
            let f = NSTextField(frame: NSRect(x: 16, y: y - 18, width: W - 32, height: 16))
            f.stringValue = text
            f.isEditable = false; f.isBezeled = false; f.drawsBackground = false
            f.font = NSFont.boldSystemFont(ofSize: 11)
            f.textColor = .secondaryLabelColor
            root.addSubview(f)
            y -= 22
        }

        func checkbox(_ title: String, action: Selector) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: self, action: action)
            b.frame = NSRect(x: 20, y: y - 20, width: W - 40, height: 20)
            b.font = NSFont.systemFont(ofSize: 12)
            root.addSubview(b)
            y -= 24
            return b
        }

        func separator() {
            let line = NSBox(frame: NSRect(x: 16, y: y - 4, width: W - 32, height: 1))
            line.boxType = .separator
            root.addSubview(line)
            y -= 12
        }

        func radioButton(_ title: String, action: Selector) -> NSButton {
            let b = NSButton(radioButtonWithTitle: title, target: self, action: action)
            b.frame = NSRect(x: 20, y: y - 20, width: W - 40, height: 20)
            b.font = NSFont.systemFont(ofSize: 12)
            root.addSubview(b)
            y -= 24
            return b
        }

        // ── Sections visibles ─────────────────────────────────────────────
        sectionLabel("Sections du menu")
        cbAudio     = checkbox("Mic / Speaker / Caméra",    action: #selector(tapCbAudio))
        cbMonitor   = checkbox("Surveillance (temp/RPM)",   action: #selector(tapCbMonitor))
        cbFan       = checkbox("Mode ventilation",          action: #selector(tapCbFan))
        cbBattery   = checkbox("Limite de charge",          action: #selector(tapCbBattery))
        cbRotation  = checkbox("Rotation écran",            action: #selector(tapCbRotation))
        cbBacklight = checkbox("Rétroéclairage clavier",    action: #selector(tapCbBacklight))

        separator()

        // ── Couleur LED ───────────────────────────────────────────────────
        sectionLabel("Couleur LED — surveiller")
        cbLEDMic = checkbox("Mic muet → orange / rouge",    action: #selector(tapCbLEDMic))
        cbLEDSpk = checkbox("Speaker muet → orange / rouge", action: #selector(tapCbLEDSpk))
        let camHeader = NSTextField(frame: NSRect(x: 20, y: y - 18, width: W - 40, height: 16))
        camHeader.stringValue = "Caméra coupée →"
        camHeader.isEditable = false; camHeader.isBezeled = false; camHeader.drawsBackground = false
        camHeader.font = NSFont.systemFont(ofSize: 12)
        root.addSubview(camHeader)
        y -= 22

        rbCamRouge  = radioButton("Rouge",              action: #selector(tapRbCamRouge))
        rbCamOrange = radioButton("Orange",             action: #selector(tapRbCamOrange))
        rbCamJaune  = radioButton("Jaune + label \"cam\"", action: #selector(tapRbCamJaune))
        rbCamNone   = radioButton("Non concerné",       action: #selector(tapRbCamNone))

        separator()

        // ── Icône barre de menus ──────────────────────────────────────────
        sectionLabel("Icône barre de menus")
        rbLED = radioButton("LEDs dynamiques", action: #selector(tapRbLED))
        rbEC  = radioButton("Badge EC",         action: #selector(tapRbEC))

        separator()

        // ── Mode rotation ────────────────────────────────────────────────
        sectionLabel("Rotation écran (F12)")
        rbRot180  = radioButton("Bascule 0° / 180°",         action: #selector(tapRb180))
        rbRotCycle = radioButton("Cycle 0° → 90° → 180° → 270°", action: #selector(tapRbCycle))

        separator()

        // ── OSD ──────────────────────────────────────────────────────────
        sectionLabel("Notifications visuelles")
        cbOSD = checkbox("Afficher l'OSD (mic / caméra)", action: #selector(tapCbOSD))

        // Footer
        let note = NSTextField(frame: NSRect(x: 16, y: 12, width: W - 32, height: 16))
        note.stringValue = "Les préférences sont sauvegardées automatiquement"
        note.isEditable = false; note.isBezeled = false; note.drawsBackground = false
        note.font = NSFont.systemFont(ofSize: 9); note.textColor = .tertiaryLabelColor
        root.addSubview(note)
    }

    func reload() {
        guard let c = controller else { return }
        cbAudio.state     = c.prefShowAudio      ? .on : .off
        cbMonitor.state   = c.prefShowMonitoring  ? .on : .off
        cbFan.state       = c.prefShowFan         ? .on : .off
        cbBattery.state   = c.prefShowBattery     ? .on : .off
        cbRotation.state  = c.prefShowRotation    ? .on : .off
        cbBacklight.state = c.prefShowBacklight   ? .on : .off
        cbLEDMic.state    = c.prefLEDWatchMic     ? .on : .off
        cbLEDSpk.state    = c.prefLEDWatchSpk     ? .on : .off
        rbCamRouge.state  = (c.prefLEDCamColor == .red)     ? .on : .off
        rbCamOrange.state = (c.prefLEDCamColor == .orange)  ? .on : .off
        rbCamJaune.state  = (c.prefLEDCamColor == .yellow)  ? .on : .off
        rbCamNone.state   = (c.prefLEDCamColor == .ignored) ? .on : .off
        rbLED.state       = (c.prefIconStyle == .led) ? .on : .off
        rbEC.state        = (c.prefIconStyle == .ec)  ? .on : .off
        rbRot180.state    = (c.prefRotationMode == .flip180) ? .on : .off
        rbRotCycle.state  = (c.prefRotationMode == .cycle90) ? .on : .off
        cbOSD.state       = c.prefShowOSD ? .on : .off
    }

    @objc private func tapCbAudio()     { controller?.tapPrefAudio() }
    @objc private func tapCbMonitor()   { controller?.tapPrefMonitoring() }
    @objc private func tapCbFan()       { controller?.tapPrefFan() }
    @objc private func tapCbBattery()   { controller?.tapPrefBattery() }
    @objc private func tapCbRotation()  { controller?.tapPrefRotation() }
    @objc private func tapCbBacklight() { controller?.tapPrefBacklight() }
    @objc private func tapCbLEDMic()    { controller?.tapPrefLEDMic();     reload() }
    @objc private func tapCbLEDSpk()    { controller?.tapPrefLEDSpk();     reload() }
    @objc private func tapRbCamRouge()  { controller?.setCameraLEDColor(.red);     reload() }
    @objc private func tapRbCamOrange() { controller?.setCameraLEDColor(.orange);  reload() }
    @objc private func tapRbCamJaune()  { controller?.setCameraLEDColor(.yellow);  reload() }
    @objc private func tapRbCamNone()   { controller?.setCameraLEDColor(.ignored); reload() }
    @objc private func tapRbLED()       { controller?.tapPrefIconLED();     reload() }
    @objc private func tapRbEC()        { controller?.tapPrefIconEC();      reload() }
    @objc private func tapCbOSD()   { controller?.toggleShowOSD();             reload() }
    @objc private func tapRb180()   { controller?.setRotationMode(.flip180);   reload() }
    @objc private func tapRbCycle() { controller?.setRotationMode(.cycle90);   reload() }
}
