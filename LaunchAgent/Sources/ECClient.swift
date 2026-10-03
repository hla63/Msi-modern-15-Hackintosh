// ECClient.swift
//
// IOKit client of MSIECToolboxDriver. Every call blocks on the EC bus:
// run them on MSIECToolboxClient.queue (see client.run), never on main.

import Foundation
import IOKit

// Classe dédiée pour le contexte IOKit — les tuples Swift ne peuvent pas être
// castés en AnyObject pour les callbacks IOKit.
private final class WatchBox {
    let client:       MSIECToolboxClient
    let onConnect:    () -> Void
    let onDisconnect: () -> Void
    init(_ c: MSIECToolboxClient, _ onC: @escaping () -> Void, _ onD: @escaping () -> Void) {
        client = c; onConnect = onC; onDisconnect = onD
    }
}

final class MSIECToolboxClient {

    // Every IOKit call below blocks while the kext waits for the EC bus
    // (tens of ms when the EC is slow). They must all run on this serial
    // queue, never on main: the CGEventTap is on the main run loop and every
    // keystroke of the system waits for it.
    let queue = DispatchQueue(label: "com.msi.MSIECToolboxAgent.ec", qos: .utility)

    /// Runs `work` on `queue`, then `done` with its result on the main queue.
    func run<T>(_ work: @escaping (MSIECToolboxClient) -> T,
                done: @escaping (T) -> Void = { _ in }) {
        queue.async {
            let result = work(self)
            DispatchQueue.main.async { done(result) }
        }
    }

    private var connection:      io_connect_t = 0
    private var notifyPort:      IONotificationPortRef? = nil
    private var addedIterator:   io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var watchCtx:        Unmanaged<WatchBox>? = nil

    var isConnected: Bool { connection != 0 }

    func connect() -> Bool {
        guard !isConnected else { return true }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("MSIECToolboxDriver"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { return false }
        connection = conn
        NSLog("[MSIECToolboxAgent] Connecté au kext (conn=0x%X)", conn)
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
                connection, MSIECToolboxSelector.setMuteState.rawValue,
                ptr.baseAddress, MemoryLayout<MSIMuteState>.size, nil, nil)
        }
        return kr == KERN_SUCCESS
    }

    func setCameraState(cameraOff: Bool) -> Bool {
        guard isConnected else { return false }
        var state = MSICameraState(cameraOff: cameraOff ? 1 : 0)
        let kr = withUnsafeBytes(of: &state) { ptr in
            IOConnectCallStructMethod(
                connection, MSIECToolboxSelector.setCameraState.rawValue,
                ptr.baseAddress, MemoryLayout<MSICameraState>.size, nil, nil)
        }
        if kr != KERN_SUCCESS {
            NSLog("[MSIECToolboxAgent] setCameraState failed: 0x%08X", kr)
        }
        return kr == KERN_SUCCESS
    }

    func readFanRPM() -> (cpuRPM: Int, gpuRPM: Int)? {
        guard isConnected else { return nil }
        var out   = MSIFanState(gpuRPM: 0, cpuRPM: 0)
        var outSz = MemoryLayout<MSIFanState>.size
        let kr = withUnsafeMutableBytes(of: &out) { ptr in
            IOConnectCallStructMethod(
                connection, MSIECToolboxSelector.readFanRPM.rawValue,
                nil, 0, ptr.baseAddress, &outSz)
        }
        guard kr == KERN_SUCCESS else { return nil }
        return (cpuRPM: Int(out.cpuRPM), gpuRPM: Int(out.gpuRPM))
    }

    // ── Nouvelles méthodes fan/performance ───────────────────────────────────

    @discardableResult
    func setFanMode(_ mode: FanMode) -> Bool {
        guard isConnected else { return false }
        var state = MSIFanModeState(mode: mode.rawValue)
        let kr = withUnsafeBytes(of: &state) { ptr in
            IOConnectCallStructMethod(
                connection, MSIECToolboxSelector.setFanMode.rawValue,
                ptr.baseAddress, MemoryLayout<MSIFanModeState>.size, nil, nil)
        }
        if kr != KERN_SUCCESS { NSLog("[MSIECToolboxAgent] setFanMode \(mode.label) failed: 0x%08X", kr) }
        return kr == KERN_SUCCESS
    }

    @discardableResult
    func setCoolerBoost(_ enable: Bool) -> Bool {
        guard isConnected else { return false }
        var state = MSICoolerBoostState(enabled: enable ? 1 : 0)
        let kr = withUnsafeBytes(of: &state) { ptr in
            IOConnectCallStructMethod(
                connection, MSIECToolboxSelector.setCoolerBoost.rawValue,
                ptr.baseAddress, MemoryLayout<MSICoolerBoostState>.size, nil, nil)
        }
        if kr != KERN_SUCCESS { NSLog("[MSIECToolboxAgent] setCoolerBoost failed: 0x%08X", kr) }
        return kr == KERN_SUCCESS
    }

    @discardableResult
    func setKbBacklight(level: UInt8) -> Bool {
        guard isConnected else { return false }
        var state = MSIKbBacklightState(level: level)
        let kr = withUnsafeBytes(of: &state) { ptr in
            IOConnectCallStructMethod(
                connection, MSIECToolboxSelector.setKbBacklight.rawValue,
                ptr.baseAddress, MemoryLayout<MSIKbBacklightState>.size, nil, nil)
        }
        if kr != KERN_SUCCESS { NSLog("[MSIECToolboxAgent] setKbBacklight %d failed: 0x%08X", level, kr) }
        return kr == KERN_SUCCESS
    }

    func getKbBacklight() -> UInt8? {
        guard isConnected else { return nil }
        var out   = MSIKbBacklightState(level: 0)
        var outSz = MemoryLayout<MSIKbBacklightState>.size
        let kr = withUnsafeMutableBytes(of: &out) { ptr in
            IOConnectCallStructMethod(
                connection, MSIECToolboxSelector.getKbBacklight.rawValue,
                nil, 0, ptr.baseAddress, &outSz)
        }
        return kr == KERN_SUCCESS ? out.level : nil
    }

    func setBatteryCharge(percent: UInt8) -> Bool {
        guard isConnected else { return false }
        var state = MSIBatteryChargeState(percent: percent)
        let kr = withUnsafeBytes(of: &state) { ptr in
            IOConnectCallStructMethod(connection, MSIECToolboxSelector.setBatteryCharge.rawValue,
                ptr.baseAddress, MemoryLayout<MSIBatteryChargeState>.size, nil, nil)
        }
        if kr != KERN_SUCCESS { NSLog("[MSIECToolboxAgent] setBatteryCharge %d%% failed: 0x%08X", percent, kr) }
        return kr == KERN_SUCCESS
    }

    func getBatteryCharge() -> UInt8? {
        guard isConnected else { return nil }
        var out   = MSIBatteryChargeState(percent: 100)
        var outSz = MemoryLayout<MSIBatteryChargeState>.size
        let kr = withUnsafeMutableBytes(of: &out) { ptr in
            IOConnectCallStructMethod(connection, MSIECToolboxSelector.getBatteryCharge.rawValue,
                nil, 0, ptr.baseAddress, &outSz)
        }
        return kr == KERN_SUCCESS ? out.percent : nil
    }

    func setFanCurve(_ curve: MSIFanCurve) -> Bool {
        guard isConnected else { return false }
        var c = curve
        let kr = withUnsafeBytes(of: &c) { ptr in
            IOConnectCallStructMethod(connection, MSIECToolboxSelector.setFanCurve.rawValue,
                ptr.baseAddress, MemoryLayout<MSIFanCurve>.size, nil, nil)
        }
        if kr != KERN_SUCCESS { NSLog("[MSIECToolboxAgent] setFanCurve failed: 0x%08X", kr) }
        return kr == KERN_SUCCESS
    }

    /// Returns the touchpad state after the request, nil if the kext or the
    /// touchpad driver is unavailable.
    func setTouchpad(_ request: TouchpadRequest) -> Bool? {
        guard isConnected else { return nil }
        var input  = MSITouchpadState(request: request.rawValue)
        var output = MSITouchpadState(request: 0)
        var outSz  = MemoryLayout<MSITouchpadState>.size
        let kr = withUnsafeBytes(of: &input) { inPtr in
            withUnsafeMutableBytes(of: &output) { outPtr in
                IOConnectCallStructMethod(connection, MSIECToolboxSelector.setTouchpad.rawValue,
                    inPtr.baseAddress, MemoryLayout<MSITouchpadState>.size,
                    outPtr.baseAddress, &outSz)
            }
        }
        guard kr == KERN_SUCCESS else {
            NSLog("[MSIECToolboxAgent] setTouchpad failed: 0x%08X", kr)
            return nil
        }
        return output.enabled != 0
    }

    func getFanCurve() -> MSIFanCurve? {
        guard isConnected else { return nil }
        var out   = MSIFanCurve()
        var outSz = MemoryLayout<MSIFanCurve>.size
        let kr = withUnsafeMutableBytes(of: &out) { ptr in
            IOConnectCallStructMethod(connection, MSIECToolboxSelector.getFanCurve.rawValue,
                nil, 0, ptr.baseAddress, &outSz)
        }
        return kr == KERN_SUCCESS ? out : nil
    }

    func readSystemState() -> MSISystemState? {
        guard isConnected else { return nil }
        var out   = MSISystemState(cpuTempC: 0, gpuTempC: 0, cpuFanPct: 0,
                                   gpuFanPct: 0, fanMode: 0, shiftMode: 0, coolerBoost: 0)
        var outSz = MemoryLayout<MSISystemState>.size
        let kr = withUnsafeMutableBytes(of: &out) { ptr in
            IOConnectCallStructMethod(
                connection, MSIECToolboxSelector.getSystemState.rawValue,
                nil, 0, ptr.baseAddress, &outSz)
        }
        guard kr == KERN_SUCCESS else { return nil }
        return out
    }

    // 256 EC reads: for the EC table window only, never for polling.
    func dumpEC() -> [UInt8]? {
        guard isConnected else { return nil }
        // Allouer 256 bytes directement — MSIECDump est un struct C non constructible en Swift
        var buffer = [UInt8](repeating: 0, count: 256)
        let kr = buffer.withUnsafeMutableBytes { ptr -> kern_return_t in
            var sz = ptr.count
            return IOConnectCallStructMethod(
                connection, MSIECToolboxSelector.dumpEC.rawValue,
                nil, 0, ptr.baseAddress, &sz)
        }
        guard kr == KERN_SUCCESS else { return nil }
        return buffer
    }

        func readECMuteState() -> (micMuted: Bool, speakerMuted: Bool, cameraOff: Bool)? {
        guard isConnected else { return nil }
        var out    = MSIAllState(micMuted: 0, speakerMuted: 0, cameraOff: 0, reserved: 0)
        var outSz  = MemoryLayout<MSIAllState>.size
        let kr = withUnsafeMutableBytes(of: &out) { ptr in
            IOConnectCallStructMethod(
                connection, MSIECToolboxSelector.getAllState.rawValue,
                nil, 0, ptr.baseAddress, &outSz)
        }
        guard kr == KERN_SUCCESS else { return nil }
        return (micMuted: out.micMuted != 0,
                speakerMuted: out.speakerMuted != 0,
                cameraOff: out.cameraOff != 0)
    }

    // The WatchBox context is retained (passRetained) for as long as the
    // notifications are registered, and released by stopWatching().
    func watchService(onConnect: @escaping () -> Void, onDisconnect: @escaping () -> Void) {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notifyPort else { return }
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        let box = WatchBox(self, onConnect, onDisconnect)
        watchCtx = Unmanaged.passRetained(box)

        guard let ctx = watchCtx?.toOpaque() else { return }

        IOServiceAddMatchingNotification(
            port, kIOMatchedNotification,
            IOServiceMatching("MSIECToolboxDriver"),
            { rawCtx, it in
                let b = Unmanaged<WatchBox>.fromOpaque(rawCtx!).takeUnretainedValue()
                while IOIteratorNext(it) != 0 {}
                b.client.run({ _ = $0.connect() }) { b.onConnect() }
            }, ctx, &addedIterator)
        while IOIteratorNext(addedIterator) != 0 {}

        IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification,
            IOServiceMatching("MSIECToolboxDriver"),
            { rawCtx, it in
                let b = Unmanaged<WatchBox>.fromOpaque(rawCtx!).takeUnretainedValue()
                while IOIteratorNext(it) != 0 {}
                b.client.run({ $0.disconnect() }) { b.onDisconnect() }
            }, ctx, &removedIterator)
        while IOIteratorNext(removedIterator) != 0 {}
    }

    func stopWatching() {
        watchCtx?.release()
        watchCtx = nil
        if addedIterator   != 0 { IOObjectRelease(addedIterator);   addedIterator   = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let port = notifyPort {
            let src = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
    }
}
