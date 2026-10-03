// Preferences.swift
//
// Typed preferences stored in UserDefaults. Raw values are the strings
// already stored by earlier versions of the agent: never rename them, or
// existing settings are silently reset to their defaults.

import Foundation

/// UserDefaults keys.
enum PrefKey: String {
    case iconStyle      = "pref_icon_style"
    case rotationMode   = "pref_rotation_mode"
    case showOSD        = "pref_show_osd"
    case ledWatchMic    = "pref_led_watch_mic"
    case ledWatchSpk    = "pref_led_watch_spk"
    case ledCamColor    = "pref_led_cam_color"
    case showAudio      = "pref_show_audio"
    case showMonitoring = "pref_show_monitoring"
    case showFan        = "pref_show_fan"
    case showBattery    = "pref_show_battery"
    case showRotation   = "pref_show_rotation"
    case showBacklight  = "pref_show_backlight"
}

/// Status bar icon.
enum IconStyle: String {
    case led        // coloured mute/camera LED (default)
    case ec         // fixed "EC" badge
}

/// What F12 does.
enum RotationMode: String {
    case flip180 = "180"      // 0° ↔ 180° (default)
    case cycle90 = "90cycle"  // 0° → 90° → 180° → 270°
}

/// Status LED colour while the camera is off. Not called `none`: that case
/// would clash with Optional.none in optional chains (controller?.…).
enum CameraLEDColor: String {
    case red     = "rouge"    // default
    case orange  = "orange"
    case yellow  = "jaune"
    case ignored = "none"     // camera state not shown by the LED
}

extension UserDefaults {
    func bool(_ key: PrefKey, default value: Bool) -> Bool {
        (object(forKey: key.rawValue) as? Bool) ?? value
    }

    /// Unknown or missing stored strings fall back to `value`.
    func pref<T: RawRepresentable>(_ key: PrefKey, default value: T) -> T where T.RawValue == String {
        string(forKey: key.rawValue).flatMap(T.init(rawValue:)) ?? value
    }

    func set(_ value: Bool, for key: PrefKey) {
        set(value, forKey: key.rawValue)
    }

    func set<T: RawRepresentable>(_ value: T, for key: PrefKey) where T.RawValue == String {
        set(value.rawValue, forKey: key.rawValue)
    }
}
