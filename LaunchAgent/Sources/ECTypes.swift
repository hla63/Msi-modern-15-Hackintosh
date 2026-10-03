// ECTypes.swift
//
// Mirror of the kext ABI (MSIECToolbox/Sources/MSIECToolboxShared.h):
// selectors, structs exchanged with IOConnectCallStructMethod and shared constants.
// Keep in sync with the header — Swift does not import it.

import Foundation

// ---------------------------------------------------------------------------
// MARK: – Sélecteurs & types partagés
// ---------------------------------------------------------------------------

enum MSIECToolboxSelector: UInt32 {
    case setMuteState     = 0
    case getMuteState     = 1
    case dumpEC           = 2
    case setCameraState   = 3
    case getAllState       = 4
    case readFanRPM       = 5
    case setFanMode       = 6
    case setCoolerBoost   = 7
    case setShiftMode     = 8
    case getSystemState   = 9
    case setKbBacklight   = 10  // MSIKbBacklightState → EC 0xF3
    case getKbBacklight   = 11
    case setBatteryCharge = 12
    case getBatteryCharge = 13
    case setFanCurve      = 14
    case getFanCurve      = 15
    case setTouchpad      = 16  // MSITouchpadState in/out — relayed to VoodooI2C/VoodooPS2
}

enum FanMode: UInt8 {
    case auto_    = 0
    case silent   = 1
    case advanced = 2

    var label: String {
        switch self {
        case .auto_:    return "Auto"
        case .silent:   return "Silencieux"
        case .advanced: return "Avancé"
        }
    }
}

struct MSIMuteState {
    var speakerMuted: UInt8
    var micMuted:     UInt8
    var reserved0:    UInt8 = 0
    var reserved1:    UInt8 = 0
}

struct MSICameraState {
    var cameraOff: UInt8
    var reserved0: UInt8 = 0
    var reserved1: UInt8 = 0
    var reserved2: UInt8 = 0
}

struct MSIAllState {
    var micMuted:     UInt8
    var speakerMuted: UInt8
    var cameraOff:    UInt8
    var reserved:     UInt8 = 0
}

struct MSIFanState {
    var gpuRPM: UInt16
    var cpuRPM: UInt16
}

struct MSIFanModeState {
    var mode:      UInt8
    var reserved0: UInt8 = 0
    var reserved1: UInt8 = 0
    var reserved2: UInt8 = 0
}

struct MSICoolerBoostState {
    var enabled:   UInt8
    var reserved0: UInt8 = 0
    var reserved1: UInt8 = 0
    var reserved2: UInt8 = 0
}

struct MSISystemState {
    var cpuTempC:    UInt8
    var gpuTempC:    UInt8
    var cpuFanPct:   UInt8
    var gpuFanPct:   UInt8
    var fanMode:     UInt8
    var shiftMode:   UInt8
    var coolerBoost: UInt8
    var validMask:   UInt8 = 0   // MSIStateValid bits — a cleared bit means the EC read failed

    func isValid(_ bit: UInt8) -> Bool { validMask & bit != 0 }
}

// Mirror of kMSIStateValid* (MSIECToolboxShared.h)
enum MSIStateValid {
    static let cpuTemp:     UInt8 = 1 << 0
    static let gpuTemp:     UInt8 = 1 << 1
    static let cpuFanPct:   UInt8 = 1 << 2
    static let gpuFanPct:   UInt8 = 1 << 3
    static let fanMode:     UInt8 = 1 << 4
    static let shiftMode:   UInt8 = 1 << 5
    static let coolerBoost: UInt8 = 1 << 6
}

// Mirror of kMSIFanCurveFloorTempC / kMSIFanCurveFloorSpeedPct (MSIECToolboxShared.h).
// The kext rejects any curve below this floor.
enum FanCurveFloor {
    static let tempC:    UInt8 = 70
    static let speedPct: UInt8 = 50
}

struct MSIBatteryChargeState {
    var percent:   UInt8
    var reserved0: UInt8 = 0
    var reserved1: UInt8 = 0
    var reserved2: UInt8 = 0
}

struct MSIFanCurve {
    var temps:  (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) = (50,58,65,70,90,95)
    var speeds: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) = (0,58,65,72,80,85)


    var tempsArray:  [UInt8] { [temps.0,  temps.1,  temps.2,  temps.3,  temps.4,  temps.5]  }
    var speedsArray: [UInt8] { [speeds.0, speeds.1, speeds.2, speeds.3, speeds.4, speeds.5] }
}

// Mirror of MSITouchpadState / kMSITouchpad* (MSIECToolboxShared.h)
struct MSITouchpadState {
    var request:   UInt8
    var enabled:   UInt8 = 0
    var reserved0: UInt8 = 0
    var reserved1: UInt8 = 0
}

enum TouchpadRequest: UInt8 {
    case query = 0, disable = 1, enable = 2, toggle = 3
}

struct MSIKbBacklightState {
    var level:     UInt8
    var reserved0: UInt8 = 0
    var reserved1: UInt8 = 0
    var reserved2: UInt8 = 0
}

// Registres EC (référence — utilisés dans le kext C++, pas en Swift)
// kECOffsetMic=0x2B  kECOffsetSpeaker=0x2C  kECOffsetCamera=0x2E
// kECCameraOff=0x49  kECBitLED=0x04
