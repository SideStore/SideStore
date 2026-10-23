import Foundation

public final class PairingArbitrator {
    public enum SelectedProvider {
        case localLockdown
        case remoteAnisette
    }
    
    public static func resolveActiveProvider() -> SelectedProvider {
        let hasLocalPairing = checkLocalPairingValidity()
        let hasRemoteConfig = checkRemoteConfigValidity()
        
        // If BOTH files/sources are available, flip a coin to decide
        if hasLocalPairing && hasRemoteConfig {
            let coinFlip = Bool.random()
            print("[PairingArbitrator] Both files detected. Coin flip result: \(coinFlip ? "Local Lockdown" : "Remote Anisette")")
            return coinFlip ? .localLockdown : .remoteAnisette
        }
        
        // Fallbacks if only one is present
        if hasLocalPairing {
            return .localLockdown
        } else {
            return .remoteAnisette
        }
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
