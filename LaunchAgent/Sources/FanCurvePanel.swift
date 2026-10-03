// FanCurvePanel.swift
//
// CPU fan curve editor.

import AppKit

// ---------------------------------------------------------------------------
// MARK: – FanCurvePanel
// NSPanel flottant — éditeur de courbe fan CPU (6 breakpoints temp + vitesse)
//
// Layout par ligne :
//   [Pt N]  [Temp: 50°C]  [————◉————]  [Spd: 0%]  [————◉————]
//
// Contraintes validées en temps réel :
//   - temp[i] strictement croissant (20–95°C)
//   - speed[i] croissant ou égal (0–100%)

final class FanCurvePanel: NSObject {

    static var shared: FanCurvePanel?

    private var panel:    NSPanel!
    private var tempSliders:  [NSSlider] = []
    private var speedSliders: [NSSlider] = []
    private var tempLabels:   [NSTextField] = []
    private var speedLabels:  [NSTextField] = []
    private var applyBtn:    NSButton!
    private var resetBtn:    NSButton!
    private var profilePopup: NSPopUpButton!
    private var saveBtn:     NSButton!
    private var deleteBtn:   NSButton!
    // Applies the curve, then calls the completion on main with the result.
    typealias ApplyHandler = (MSIFanCurve, @escaping (Bool) -> Void) -> Void

    private var onApply:   ApplyHandler?
    private var curve:     MSIFanCurve

    static func show(current: MSIFanCurve, onApply: @escaping ApplyHandler) {
        if shared == nil { shared = FanCurvePanel() }
        shared!.configure(curve: current, onApply: onApply)
        shared!.panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private override init() {
        curve = MSIFanCurve()
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        let W: CGFloat = 680
        let rowH: CGFloat = 36
        let headerH: CGFloat = 30
        let footerH: CGFloat = 80
        let H = headerH + CGFloat(6) * rowH + footerH + 20

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask:   [.titled, .closable, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.title        = "Courbe fan CPU — Mode Avancé"
        panel.level        = .floating
        panel.isReleasedWhenClosed = false
        panel.center()

        let root = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        panel.contentView = root

        // ── En-tête ──────────────────────────────────────────────────────────
        func label(_ t: String, x: CGFloat, y: CGFloat, w: CGFloat, bold: Bool = false) -> NSTextField {
            let f = NSTextField(frame: NSRect(x: x, y: y, width: w, height: 18))
            f.stringValue = t
            f.isEditable = false; f.isBezeled = false; f.drawsBackground = false
            f.alignment = .center
            if bold { f.font = NSFont.boldSystemFont(ofSize: 11) }
            else     { f.font = NSFont.systemFont(ofSize: 11) }
            return f
        }
        let hY = H - headerH
        root.addSubview(label("Point", x: 10,  y: hY, w: 40,  bold: true))
        root.addSubview(label("Température (°C)", x: 55, y: hY, w: 185, bold: true))
        root.addSubview(label("Vitesse fan (%)", x: 270, y: hY, w: 185, bold: true))
        root.addSubview(label("Défaut", x: 465, y: hY, w: 50,  bold: true))

        let defaultCurve = MSIFanCurve()

        for i in 0..<6 {
            let y = H - headerH - CGFloat(i + 1) * rowH

            // Numéro du point
            root.addSubview(label("\(i+1)", x: 10, y: y + 9, w: 40))

            // Température slider
            let tSlider = NSSlider(frame: NSRect(x: 55, y: y + 6, width: 130, height: 22))
            tSlider.minValue = 20; tSlider.maxValue = 95
            tSlider.integerValue = Int(defaultCurve.tempsArray[i])
            tSlider.tag = i
            tSlider.target = self; tSlider.action = #selector(tempChanged(_:))
            root.addSubview(tSlider)
            tempSliders.append(tSlider)

            let tLabel = NSTextField(frame: NSRect(x: 190, y: y + 9, width: 50, height: 18))
            tLabel.isEditable = false; tLabel.isBezeled = false; tLabel.drawsBackground = false
            tLabel.alignment = .left
            tLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            tLabel.stringValue = "\(defaultCurve.tempsArray[i]) °C"
            root.addSubview(tLabel)
            tempLabels.append(tLabel)

            // Vitesse slider
            let sSlider = NSSlider(frame: NSRect(x: 270, y: y + 6, width: 130, height: 22))
            sSlider.minValue = 0; sSlider.maxValue = 100
            sSlider.integerValue = Int(defaultCurve.speedsArray[i])
            sSlider.tag = i
            sSlider.target = self; sSlider.action = #selector(speedChanged(_:))
            root.addSubview(sSlider)
            speedSliders.append(sSlider)

            let sLabel = NSTextField(frame: NSRect(x: 405, y: y + 9, width: 50, height: 18))
            sLabel.isEditable = false; sLabel.isBezeled = false; sLabel.drawsBackground = false
            sLabel.alignment = .left
            sLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            sLabel.stringValue = "\(defaultCurve.speedsArray[i]) %"
            root.addSubview(sLabel)
            speedLabels.append(sLabel)

            // Valeur défaut firmware
            root.addSubview(label("\(defaultCurve.tempsArray[i])/\(defaultCurve.speedsArray[i])",
                                   x: 460, y: y + 9, w: 55))
        }

        // ── Footer — ligne 1 : profils ──────────────────────────────────────
        let profileLabel = NSTextField(frame: NSRect(x: 10, y: 52, width: 60, height: 18))
        profileLabel.stringValue = "Profil :"
        profileLabel.isEditable = false; profileLabel.isBezeled = false; profileLabel.drawsBackground = false
        profileLabel.font = NSFont.systemFont(ofSize: 11)
        root.addSubview(profileLabel)

        profilePopup = NSPopUpButton(frame: NSRect(x: 72, y: 48, width: 200, height: 26))
        profilePopup.font = NSFont.systemFont(ofSize: 11)
        profilePopup.target = self; profilePopup.action = #selector(tapLoadProfile)
        root.addSubview(profilePopup)

        saveBtn = NSButton(frame: NSRect(x: 280, y: 48, width: 100, height: 26))
        saveBtn.title = "Sauvegarder..."
        saveBtn.bezelStyle = .rounded
        saveBtn.target = self; saveBtn.action = #selector(tapSaveProfile)
        root.addSubview(saveBtn)

        deleteBtn = NSButton(frame: NSRect(x: 386, y: 48, width: 80, height: 26))
        deleteBtn.title = "Supprimer"
        deleteBtn.bezelStyle = .rounded
        deleteBtn.target = self; deleteBtn.action = #selector(tapDeleteProfile)
        root.addSubview(deleteBtn)

        // ── Footer — ligne 2 : apply / reset ─────────────────────────────────
        applyBtn = NSButton(frame: NSRect(x: W - 110, y: 12, width: 95, height: 28))
        applyBtn.title = "Appliquer"
        applyBtn.bezelStyle = .rounded
        applyBtn.keyEquivalent = "\r"
        applyBtn.target = self; applyBtn.action = #selector(tapApply)
        root.addSubview(applyBtn)

        resetBtn = NSButton(frame: NSRect(x: W - 220, y: 12, width: 100, height: 28))
        resetBtn.title = "Défaut firmware"
        resetBtn.bezelStyle = .rounded
        resetBtn.target = self; resetBtn.action = #selector(tapReset)
        root.addSubview(resetBtn)

        let note = NSTextField(frame: NSRect(x: 10, y: 15, width: 290, height: 24))
        note.stringValue = "Point 7 : 100% fixe (non éditable) — mode Advanced requis"
        note.isEditable = false; note.isBezeled = false; note.drawsBackground = false
        note.font = NSFont.systemFont(ofSize: 9); note.textColor = .secondaryLabelColor
        root.addSubview(note)
    }

    private func configure(curve: MSIFanCurve, onApply: @escaping ApplyHandler) {
        self.onApply = onApply
        self.curve   = curve
        let t = curve.tempsArray
        let s = curve.speedsArray
        for i in 0..<6 {
            tempSliders[i].integerValue  = Int(t[i])
            speedSliders[i].integerValue = Int(s[i])
            tempLabels[i].stringValue    = "\(t[i]) °C"
            speedLabels[i].stringValue   = "\(s[i]) %"
        }
        reloadProfilePopup()
    }

    func reloadProfilePopup() {
        profilePopup.removeAllItems()
        profilePopup.addItem(withTitle: "— Choisir un profil —")
        FanProfileManager.shared.profiles.forEach { profilePopup.addItem(withTitle: $0.name) }
        deleteBtn.isEnabled = FanProfileManager.shared.profiles.count > 0
    }

    @objc private func tapLoadProfile() {
        let name = profilePopup.titleOfSelectedItem ?? ""
        guard let profile = FanProfileManager.shared.profile(named: name) else { return }
        configure(curve: profile.toCurve(), onApply: onApply ?? { _, done in done(false) })
    }

    @objc private func tapSaveProfile() {
        let alert = NSAlert()
        alert.messageText = "Sauvegarder le profil"
        alert.informativeText = "Entrez un nom pour ce profil :"
        alert.addButton(withTitle: "Sauvegarder")
        alert.addButton(withTitle: "Annuler")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.placeholderString = "Ex : Silencieux, Jeu, Turbo..."
        alert.accessoryView = tf
        alert.window.initialFirstResponder = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let profile = FanProfile.fromCurve(readCurve(), name: name)
        FanProfileManager.shared.add(profile)
        reloadProfilePopup()
        // Sélectionner le profil sauvegardé
        profilePopup.selectItem(withTitle: name)
        NSLog("[MSIECToolboxAgent] Profil sauvegardé : %@", name)
    }

    @objc private func tapDeleteProfile() {
        let name = profilePopup.titleOfSelectedItem ?? ""
        guard FanProfileManager.shared.profile(named: name) != nil else { return }
        let alert = NSAlert()
        alert.messageText = "Supprimer le profil \"\(name)\""
        alert.informativeText = "Cette action est irréversible."
        alert.addButton(withTitle: "Supprimer")
        alert.addButton(withTitle: "Annuler")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        FanProfileManager.shared.delete(name: name)
        reloadProfilePopup()
        NSLog("[MSIECToolboxAgent] Profil supprimé : %@", name)
    }

    private func readCurve() -> MSIFanCurve {
        let t = tempSliders.map  { UInt8($0.integerValue) }
        let s = speedSliders.map { UInt8($0.integerValue) }
        return MSIFanCurve(
            temps:  (t[0],t[1],t[2],t[3],t[4],t[5]),
            speeds: (s[0],s[1],s[2],s[3],s[4],s[5])
        )
    }

    @objc private func tempChanged(_ sender: NSSlider) {
        let i = sender.tag
        var val = sender.integerValue
        // Contrainte : temp[i] > temp[i-1]
        if i > 0 { val = max(val, tempSliders[i-1].integerValue + 1) }
        // Contrainte : temp[i] < temp[i+1]
        if i < 5 { val = min(val, tempSliders[i+1].integerValue - 1) }
        sender.integerValue = val
        tempLabels[i].stringValue = "\(val) °C"
    }

    @objc private func speedChanged(_ sender: NSSlider) {
        let i = sender.tag
        var val = sender.integerValue
        if i > 0 { val = max(val, speedSliders[i-1].integerValue) }
        if i < 5 { val = min(val, speedSliders[i+1].integerValue) }
        sender.integerValue = val
        speedLabels[i].stringValue = "\(val) %"
    }

    @objc private func tapApply() {
        let curve = readCurve()
        if let problem = FanCurvePanel.floorViolation(curve) {
            let alert = NSAlert()
            alert.messageText = "Courbe refusée"
            alert.informativeText = problem
            alert.runModal()
            return
        }
        guard let onApply = onApply else { return }
        applyBtn.isEnabled = false
        onApply(curve) { [weak self] ok in
            guard let self = self else { return }
            self.applyBtn.isEnabled = true
            if ok {
                self.panel.orderOut(nil)
            } else {
                let alert = NSAlert()
                alert.messageText = "Courbe non appliquée"
                alert.informativeText = "Le kext a refusé la courbe ou n'est pas chargé. "
                                      + "Le mode de ventilation n'a pas été modifié."
                alert.runModal()
            }
        }
    }

    // Same rule as the kext (kMSIFanCurveFloor*): checked here so the user
    // gets an explanation instead of a silent kIOReturnBadArgument.
    static func floorViolation(_ curve: MSIFanCurve) -> String? {
        let t = curve.tempsArray, s = curve.speedsArray
        for i in 0..<6 where t[i] >= FanCurveFloor.tempC && s[i] < FanCurveFloor.speedPct {
            return "Point \(i + 1) : à \(t[i]) °C la vitesse doit être d'au moins \(FanCurveFloor.speedPct) % "
                 + "(sécurité thermique à partir de \(FanCurveFloor.tempC) °C)."
        }
        if s[5] < FanCurveFloor.speedPct {
            return "Le dernier point doit demander au moins \(FanCurveFloor.speedPct) %."
        }
        return nil
    }

    @objc private func tapReset() {
        configure(curve: MSIFanCurve(), onApply: onApply ?? { _, done in done(false) })
    }
}
