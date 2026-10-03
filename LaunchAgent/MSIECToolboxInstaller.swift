import Foundation
import ServiceManagement

// Enregistre ou réenregistre l'agent via SMAppService (macOS 13+)
// Pas de notification "Éléments en arrière-plan" répétée avec cette API.

let service = SMAppService.agent(plistName: "com.msi.MSIECToolboxAgent.plist")

func printStatus() {
    switch service.status {
    case .enabled:          print("[MSIECToolbox] ✅ Agent actif")
    case .requiresApproval: print("[MSIECToolbox] ⚠️  En attente approbation — ouvre Réglages Système > Général > Ouverture")
    case .notFound:         print("[MSIECToolbox] ❌ Plist introuvable dans le bundle")
    case .notRegistered:    print("[MSIECToolbox] ℹ️  Non enregistré")
    @unknown default:       print("[MSIECToolbox] ❓ Statut inconnu")
    }
}

let args = CommandLine.arguments
let cmd  = args.count > 1 ? args[1] : "register"

switch cmd {
case "unregister":
    do {
        try service.unregister()
        print("[MSIECToolbox] Agent désenregistré")
    } catch {
        print("[MSIECToolbox] Erreur: \(error)")
    }

case "status":
    printStatus()

default: // "register"
    switch service.status {
    case .enabled:
        // Déjà actif : NE PAS rappeler register() pour éviter la
        // notification "Éléments en arrière-plan" à chaque démarrage.
        print("[MSIECToolbox] Agent déjà actif — rien à faire")
    case .requiresApproval:
        print("[MSIECToolbox] En attente d'approbation")
        SMAppService.openSystemSettingsLoginItems()
    default:
        do {
            try service.register()
            print("[MSIECToolbox] ✅ Agent enregistré avec succès")
            printStatus()
        } catch {
            print("[MSIECToolbox] ❌ Erreur: \(error)")
        }
    }
}
