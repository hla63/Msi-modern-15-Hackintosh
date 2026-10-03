// MuteOSD.swift
//
// On-screen display for mic / camera / touchpad toggles.

import AppKit

// ---------------------------------------------------------------------------
// MARK: – Splash OSD mute mic
// ---------------------------------------------------------------------------

final class MuteOSD {

    private static var window: NSWindow?
    private static var hideTimer: Timer?

    static func show(muted: Bool, isMic: Bool, isCam: Bool = false, isTrackpad: Bool = false) {
        hideTimer?.invalidate()

        // Créer la fenêtre si besoin
        if window == nil { window = makeWindow() }
        guard let win = window else { return }

        // Mettre à jour le contenu
        // contentView = NSVisualEffectView → OSDView est dans ses subviews
        let osdView = (win.contentView as? NSVisualEffectView)?.subviews.first as? OSDView
                   ?? win.contentView as? OSDView
        osdView?.configure(muted: muted, isMic: isMic, isCam: isCam, isTrackpad: isTrackpad)

        // Centrer légèrement en bas de l'écran (style macOS)
        if let screen = NSScreen.main {
            let sw = screen.frame.width, sh = screen.frame.height
            let ww = win.frame.width
            win.setFrameOrigin(NSPoint(
                x: screen.frame.minX + (sw - ww) / 2,
                y: screen.frame.minY + sh * 0.13
            ))
        }

        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            win.animator().alphaValue = 1.0
        }

        // Disparaître après 1.8s
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { _ in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                win.animator().alphaValue = 0
            }, completionHandler: {
                win.orderOut(nil)
            })
        }
    }

    private static func makeWindow() -> NSWindow {
        let size: CGFloat = 200
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )
        win.isOpaque           = false
        win.backgroundColor    = .clear
        win.level              = .screenSaver
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // NSVisualEffectView pour le fond flou — identique à l'OSD macOS
        let vfx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        vfx.material    = .hudWindow   // gris neutre comme l'OSD volume/luminosité
        vfx.blendingMode = .behindWindow
        vfx.state       = .active
        vfx.wantsLayer  = true
        vfx.layer?.cornerRadius = 20
        vfx.layer?.masksToBounds = true

        let osdView = OSDView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        osdView.wantsLayer = true
        osdView.layer?.backgroundColor = NSColor.clear.cgColor
        vfx.addSubview(osdView)
        win.contentView = vfx

        return win
    }
}

// Vue OSD — fond flou + icône + texte
private final class OSDView: NSView {

    private var muted:  Bool = true
    private var isMic:  Bool = true
    private var isCam:  Bool = false
    private var isTrackpad: Bool = false

    func configure(muted: Bool, isMic: Bool, isCam: Bool = false, isTrackpad: Bool = false) {
        self.muted = muted
        self.isMic = isMic
        self.isCam = isCam
        self.isTrackpad = isTrackpad
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let size = b.width

        // Le fond est géré par NSVisualEffectView — on dessine seulement l'icône et le texte

        // ── SF Symbol principal ────────────────────────────────────────────
        let symName: String
        if isCam {
            symName = "camera.fill"  // barre dessinée manuellement si coupée
        } else if isTrackpad {
            symName = "rectangle.and.hand.point.up.left.fill"  // idem
        } else if isMic {
            symName = muted ? "mic.slash.fill" : "mic.fill"
        } else {
            symName = muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        }

        // Dessiner l'icône SF Symbol en respectant son ratio naturel
        if let sym = NSImage(systemSymbolName: symName, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 52, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
            let img = sym.withSymbolConfiguration(cfg) ?? sym
            // Utiliser la taille naturelle de l'image (pas de déformation)
            let iw = img.size.width
            let ih = img.size.height
            let iconX = (size - iw) / 2
            let iconY = (size - ih) / 2 + 14
            img.draw(in: NSRect(x: iconX, y: iconY, width: iw, height: ih),
                     from: .zero, operation: .sourceOver, fraction: 1.0,
                     respectFlipped: true, hints: nil)
        }

        // Barre diagonale rouge pour caméra coupée
        if (isCam || isTrackpad) && muted, let sym2 = NSImage(systemSymbolName: symName, accessibilityDescription: nil) {
            let cfg2 = NSImage.SymbolConfiguration(pointSize: 52, weight: .medium)
            let img2 = sym2.withSymbolConfiguration(cfg2) ?? sym2
            let iw2 = img2.size.width, ih2 = img2.size.height
            let ix2 = (size - iw2) / 2, iy2 = (size - ih2) / 2 + 14
            let x1 = ix2 + iw2 * 0.10, y1 = iy2 + ih2 * 0.90
            let x2 = ix2 + iw2 * 0.90, y2 = iy2 + ih2 * 0.10
            let slash = NSBezierPath()
            slash.move(to:  CGPoint(x: x1, y: y1))
            slash.line(to:  CGPoint(x: x2, y: y2))
            slash.lineWidth  = 7
            slash.lineCapStyle = .round
            // Bordure blanche pour lisibilité
            NSColor.white.withAlphaComponent(0.6).setStroke()
            slash.lineWidth = 9
            slash.stroke()
            NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0).setStroke()
            slash.lineWidth = 6
            slash.stroke()
        }

        // ── Texte en bas ──────────────────────────────────────────────────
        let label: String
        if isCam {
            label = muted ? "Caméra coupée" : "Caméra active"
        } else if isTrackpad {
            label = muted ? "Trackpad désactivé" : "Trackpad actif"
        } else if isMic {
            label = muted ? "Mic muet" : "Mic actif"
        } else {
            label = muted ? "Coupé" : "Actif"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let sw = str.size().width
        str.draw(at: CGPoint(x: (size - sw) / 2, y: 16))
    }
}
