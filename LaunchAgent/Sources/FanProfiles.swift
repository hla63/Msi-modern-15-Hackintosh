// FanProfiles.swift
//
// Saved fan curve profiles (UserDefaults "fan_profiles").

import Foundation

// ---------------------------------------------------------------------------
// MARK: – Profils de courbe fan
// ---------------------------------------------------------------------------

struct FanProfile: Codable {
    var name:   String
    var temps:  [UInt8]
    var speeds: [UInt8]

    func toCurve() -> MSIFanCurve {
        var c = MSIFanCurve()
        if temps.count == 6 && speeds.count == 6 {
            c.temps  = (temps[0],  temps[1],  temps[2],  temps[3],  temps[4],  temps[5])
            c.speeds = (speeds[0], speeds[1], speeds[2], speeds[3], speeds[4], speeds[5])
        }
        return c
    }

    static func fromCurve(_ curve: MSIFanCurve, name: String) -> FanProfile {
        FanProfile(name: name, temps: curve.tempsArray, speeds: curve.speedsArray)
    }
}

final class FanProfileManager {
    static let shared = FanProfileManager()
    private let udKey = "fan_profiles"
    private(set) var profiles: [FanProfile] = []

    private init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let decoded = try? JSONDecoder().decode([FanProfile].self, from: data)
        else { profiles = []; return }
        profiles = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: udKey)
    }

    func add(_ profile: FanProfile) {
        profiles.removeAll { $0.name == profile.name }
        profiles.append(profile)
        save()
    }

    func delete(name: String) {
        profiles.removeAll { $0.name == name }
        save()
    }

    func profile(named name: String) -> FanProfile? {
        profiles.first { $0.name == name }
    }
}
