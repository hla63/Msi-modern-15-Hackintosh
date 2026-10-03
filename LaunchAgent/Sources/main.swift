// main.swift
//
// MSIECToolboxAgent — LaunchAgent for MSI Modern 15 (menu bar, Fn keys,
// mute LEDs, fans, camera, touchpad, rotation). Entry point.
//
// Files: ECTypes (kext ABI mirror), ECClient (IOKit), MenuBarController,
// MuteObserver (app delegate), MuteOSD, PreferencesPanel, ECDumpPanel,
// FanCurvePanel, FanProfiles. Only this file may contain top-level code.

import AppKit

// ---------------------------------------------------------------------------
// MARK: – Point d'entrée NSApplication
// ---------------------------------------------------------------------------

// ── Guard instance unique ─────────────────────────────────────────────────
// Évite deux instances simultanées (double lancement manuel + launchd).
// Per-user temporary directory ($TMPDIR, mode 0700): /tmp is shared, so
// another user could pre-create the file and keep the agent from starting.
let pidFile = FileManager.default.temporaryDirectory
    .appendingPathComponent("MSIECToolboxAgent.pid").path
let myPID   = ProcessInfo.processInfo.processIdentifier

func isProcessRunning(_ pid: Int32) -> Bool {
    pid != myPID && kill(pid, 0) == 0
}

if let existing = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
   let existingPID = Int32(existing),
   isProcessRunning(existingPID) {
    NSLog("[MSIECToolboxAgent] ⚠️  Instance déjà en cours (PID %d) — arrêt", existingPID)
    exit(0)
}

try? String(myPID).write(toFile: pidFile, atomically: true, encoding: .utf8)

let app      = NSApplication.shared
let client   = MSIECToolboxClient()
let menuBar  = MenuBarController()
let observer = MuteObserver(client: client, menuBar: menuBar)

app.setActivationPolicy(.accessory)  // pas d'icône dans le Dock
app.delegate = observer
app.run()
