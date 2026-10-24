import Foundation

public final class PairingArbitrator {
    public enum SelectedProvider {
        case localLockdown
        case remoteAnisette
    }
    
    public static func resolveActiveProvider() -> SelectedProvider {
        let hasLocalPairing = checkLocalPairingValidity()
        let hasRemoteConfig = checkRemoteConfigValidity()
        
        // FIX: Always prioritize Local Lockdown if a valid pairing file exists.
        // Never flip a coin or randomize provider selection.
        if hasLocalPairing {
            print("[PairingArbitrator] Valid local pairing file detected. Forcing Local Lockdown.")
            return .localLockdown
        }
        
        if hasRemoteConfig {
            print("[PairingArbitrator] No local pairing file found. Falling back to Remote Anisette.")
            return .remoteAnisette
        }
        
        print("[PairingArbitrator] Neither local pairing nor remote config found. Defaulting to Local Lockdown.")
        return .localLockdown
    }
    
    private static func checkLocalPairingValidity() -> Bool {
        guard let pf = PairingFileManager.shared.fetchPairingFile(),
              let data = pf.data(using: .utf8),
              data.count > 100 else {
            return false
        }
        return true
    }
    
    private static func checkRemoteConfigValidity() -> Bool {
        let fileManager = FileManager.default
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        let configPath = docsDir.appendingPathComponent("remote_config.json")
        return fileManager.fileExists(atPath: configPath.path)
    }
}
