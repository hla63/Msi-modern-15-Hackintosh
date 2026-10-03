// ECDumpPanel.swift
//
// EC register table window (256 registers, optional 2 s auto-refresh).

import AppKit

// ---------------------------------------------------------------------------
// MARK: – Fenêtre Table EC
// ---------------------------------------------------------------------------

// Asynchronous EC dump: the 256 reads run on the EC queue, `done` is called
// on main with the bytes (nil on failure).
typealias ECDumpFetcher = (@escaping ([UInt8]?) -> Void) -> Void

final class ECDumpPanel: NSObject, NSWindowDelegate {

    static var shared: ECDumpPanel?

    private var panel:       NSPanel!
    private var cells:       [[NSTextField]] = []  // 16 lignes × 16 colonnes
    private var fetcher:     ECDumpFetcher?
    private var autoRefreshTimer: Timer?
    private var autoRefreshCb: NSButton!

    static func show(fetcher: @escaping ECDumpFetcher) {
        if shared == nil { shared = ECDumpPanel() }
        shared!.fetcher = fetcher
        shared!.refresh()
        shared!.panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private override init() {
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        let colW:    CGFloat = 30
        let rowH:    CGFloat = 18
        let labelW:  CGFloat = 36
        let marginL: CGFloat = 12
        let marginB: CGFloat = 50
        let headerH: CGFloat = 24
        let cols = 16
        let rows = 16
        let W = marginL + labelW + CGFloat(cols) * colW + 12
        let H = marginB + headerH + CGFloat(rows) * rowH + 12

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask:   [.titled, .closable, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.title = "Table EC — MSI Modern 15 A10M"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()

        let root = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        panel.contentView = root

        func makeLabel(_ text: String, x: CGFloat, y: CGFloat,
                        w: CGFloat, h: CGFloat = 16,
                        mono: Bool = false, bold: Bool = false,
                        align: NSTextAlignment = .center) -> NSTextField {
            let f = NSTextField(frame: NSRect(x: x, y: y, width: w, height: h))
            f.stringValue = text
            f.isEditable = false; f.isBezeled = false; f.drawsBackground = false
            f.alignment = align
            if bold        { f.font = NSFont.boldSystemFont(ofSize: 10) }
            else if mono   { f.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular) }
            else           { f.font = NSFont.systemFont(ofSize: 10) }
            return f
        }

        // En-tête colonnes (_0 … _F)
        let hY = H - headerH
        root.addSubview(makeLabel("", x: marginL, y: hY, w: labelW, bold: true))
        for col in 0..<cols {
            let x = marginL + labelW + CGFloat(col) * colW
            root.addSubview(makeLabel(String(format: "_%X", col),
                                       x: x, y: hY, w: colW, bold: true))
        }

        // Lignes
        for row in 0..<rows {
            let y = H - headerH - CGFloat(row + 1) * rowH - 2

            // Label ligne (0x0_ … 0xF_)
            let rl = makeLabel(String(format: "0x%X_", row),
                                x: marginL, y: y, w: labelW, mono: true, bold: true, align: .left)
            root.addSubview(rl)

            var rowCells: [NSTextField] = []
            for col in 0..<cols {
                let x = marginL + labelW + CGFloat(col) * colW
                let cell = makeLabel("00", x: x, y: y, w: colW, mono: true)
                root.addSubview(cell)
                rowCells.append(cell)
            }
            cells.append(rowCells)
        }

        // Footer
        let refreshBtn = NSButton(frame: NSRect(x: W - 110, y: 12, width: 95, height: 26))
        refreshBtn.title = "Rafraîchir"
        refreshBtn.bezelStyle = .rounded
        refreshBtn.keyEquivalent = "\r"
        refreshBtn.target = self
        refreshBtn.action = #selector(tapRefresh)
        root.addSubview(refreshBtn)

        autoRefreshCb = NSButton(checkboxWithTitle: "Auto (2s)", target: self,
                                  action: #selector(tapAutoRefresh))
        autoRefreshCb.frame = NSRect(x: W - 220, y: 14, width: 100, height: 20)
        autoRefreshCb.font = NSFont.systemFont(ofSize: 11)
        root.addSubview(autoRefreshCb)

        let note = NSTextField(frame: NSRect(x: marginL, y: 15, width: 180, height: 18))
        note.stringValue = "256 registres EC — kext direct"
        note.isEditable = false; note.isBezeled = false; note.drawsBackground = false
        note.font = NSFont.systemFont(ofSize: 9); note.textColor = .secondaryLabelColor
        root.addSubview(note)
    }

    func refresh() {
        fetcher?({ [weak self] bytes in
            guard let self = self, let bytes = bytes, bytes.count >= 256 else { return }
            for row in 0..<16 {
                for col in 0..<16 {
                    let val = bytes[row * 16 + col]
                    let cell = self.cells[row][col]
                    cell.stringValue = String(format: "%02X", val)
                    // Mettre en évidence les valeurs non-nulles
                    cell.textColor = (val == 0) ? .tertiaryLabelColor : .labelColor
                }
            }
        })
    }

    @objc private func tapRefresh() { refresh() }

    @objc private func tapAutoRefresh() {
        if autoRefreshCb.state == .on {
            autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        } else {
            autoRefreshTimer?.invalidate()
            autoRefreshTimer = nil
        }
    }

    // Closing the window must stop the auto-refresh, which otherwise keeps
    // dumping 256 EC registers every 2 s for nothing.
    func windowWillClose(_ notification: Notification) {
        ECDumpPanel.stop()
    }

    // Arrêter le timer quand le panel se ferme
    static func stop() {
        shared?.autoRefreshTimer?.invalidate()
        shared?.autoRefreshTimer = nil
        shared?.autoRefreshCb?.state = .off
    }
}
